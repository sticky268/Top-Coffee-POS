package com.example.top_coffee_pos;

import java.io.ByteArrayOutputStream;
import java.util.Arrays;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

/** Runs the production writer on a plain JVM; no printer or sale is needed. */
public final class CheckedPrinterWriterTest {
    private static int checks;
    private static void check(boolean condition, String message) {
        checks++;
        if (!condition) throw new AssertionError(message);
    }
    private static void fails(Runnable action) {
        try { action.run(); } catch (IllegalStateException expected) { return; }
        throw new AssertionError("Write should fail, not report success");
    }

    public static void main(String[] args) throws Exception {
        for (int size : new int[] {0, 1, 511, 512, 513, 1736, 13832, 100_000}) {
            byte[] original = new byte[size];
            for (int i = 0; i < size; i++) original[i] = (byte) (i * 37);
            ByteArrayOutputStream output = new ByteArrayOutputStream();
            AtomicInteger closes = new AtomicInteger();
            CheckedPrinterWriter writer = new CheckedPrinterWriter(part -> {
                check(part.length <= 512, "Oversized TCP chunk");
                output.write(part, 0, part.length);
                return part.length;
            }, closes::incrementAndGet, 1000, 0);
            writer.write(original);
            byte[] cut = new byte[] {29, 86, 66, 1};
            writer.write(cut);
            byte[] all = output.toByteArray();
            check(Arrays.equals(original, Arrays.copyOf(all, size)), "Raster bytes changed or reordered");
            check(Arrays.equals(cut, Arrays.copyOfRange(all, size, all.length)), "Cut preceded image completion");
            check(closes.get() == 0, "Successful write disconnected");
        }

        for (int result : new int[] {-1, 0, 511}) {
            AtomicInteger calls = new AtomicInteger();
            AtomicInteger closes = new AtomicInteger();
            CheckedPrinterWriter writer = new CheckedPrinterWriter(part -> {
                return calls.incrementAndGet() == 2 ? result : part.length;
            }, closes::incrementAndGet, 1000, 0);
            fails(() -> writer.write(new byte[1736]));
            fails(() -> writer.write(new byte[] {29, 86, 66, 1}));
            check(calls.get() == 2, "Failed bytes were replayed or cut was sent");
            check(closes.get() == 1, "Failed session was not closed exactly once");
        }

        AtomicInteger exceptionCloses = new AtomicInteger();
        CheckedPrinterWriter throwing = new CheckedPrinterWriter(part -> {
            throw new IllegalStateException("Socket failed");
        }, exceptionCloses::incrementAndGet, 1000, 0);
        fails(() -> throwing.write(new byte[10]));
        check(exceptionCloses.get() == 1, "Exception left the connection open");

        CountDownLatch released = new CountDownLatch(1);
        AtomicInteger timeouts = new AtomicInteger();
        CheckedPrinterWriter stalled = new CheckedPrinterWriter(part -> {
            try {
                check(released.await(2, TimeUnit.SECONDS), "Watchdog did not unblock the write");
            } catch (InterruptedException e) { throw new AssertionError(e); }
            return part.length; // A late success must still be reported as uncertain.
        }, () -> { timeouts.incrementAndGet(); released.countDown(); }, 30, 0);
        fails(() -> stalled.write(new byte[20]));
        fails(() -> stalled.write(new byte[20]));
        check(timeouts.get() == 1, "Timed-out job was replayed");

        AtomicInteger successfulCloses = new AtomicInteger();
        CheckedPrinterWriter complete = new CheckedPrinterWriter(part -> part.length,
                successfulCloses::incrementAndGet, 30, 0);
        complete.write(new byte[20]);
        Thread.sleep(80);
        check(successfulCloses.get() == 0, "Cancelled watchdog closed a completed session");

        AtomicInteger interruptedCloses = new AtomicInteger();
        CheckedPrinterWriter interrupted = new CheckedPrinterWriter(part -> part.length,
                interruptedCloses::incrementAndGet, 1000, 10);
        Thread.currentThread().interrupt();
        fails(() -> interrupted.write(new byte[1736]));
        check(Thread.interrupted(), "Interrupted status was lost");
        check(interruptedCloses.get() == 1, "Interrupted session remained open");
        System.out.println("PASS: " + checks + " native writer assertions (ordering, failure, timeout, interruption)");
    }
}
