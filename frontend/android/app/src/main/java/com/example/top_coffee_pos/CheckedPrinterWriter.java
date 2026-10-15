package com.example.top_coffee_pos;

import java.util.Arrays;
import java.util.concurrent.ScheduledThreadPoolExecutor;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.function.ToIntFunction;

/** Checked, paced transport. Successful writes confirm submission, never paper output. */
public final class CheckedPrinterWriter {
    private static final ScheduledThreadPoolExecutor WATCHDOG = new ScheduledThreadPoolExecutor(1, task -> {
        Thread thread = new Thread(task, "printer-write-timeout");
        thread.setDaemon(true);
        return thread;
    });
    static { WATCHDOG.setRemoveOnCancelPolicy(true); }

    private final ToIntFunction<byte[]> send;
    private final Runnable disconnect;
    private final long timeoutMs;
    private final long pacingMs;
    private final AtomicBoolean failed = new AtomicBoolean();

    public CheckedPrinterWriter(ToIntFunction<byte[]> send, Runnable disconnect) {
        this(send, disconnect, 10_000, 10);
    }

    // Package-private timing controls let the real production transport run in JVM checks.
    CheckedPrinterWriter(ToIntFunction<byte[]> send, Runnable disconnect, long timeoutMs, long pacingMs) {
        this.send = send;
        this.disconnect = disconnect;
        this.timeoutMs = timeoutMs;
        this.pacingMs = pacingMs;
    }

    private void abort() {
        if (failed.compareAndSet(false, true)) disconnect.run();
    }

    public synchronized void write(byte[] data) {
        if (failed.get()) throw new IllegalStateException("Printer connection failed. Check paper before making a COPY.");
        if (data.length == 0) return;
        AtomicBoolean active = new AtomicBoolean(true);
        var deadline = WATCHDOG.schedule(() -> {
            if (active.compareAndSet(true, false)) {
                abort(); // Closing the socket unblocks a stalled SDK write.
            }
        }, timeoutMs, TimeUnit.MILLISECONDS);
        try {
            for (int offset = 0; offset < data.length; offset += 512) {
                if (failed.get()) throw new IllegalStateException("Printer write timed out.");
                byte[] part = Arrays.copyOfRange(data, offset, Math.min(data.length, offset + 512));
                if (send.applyAsInt(part) != part.length) {
                    throw new IllegalStateException("Printer write was incomplete. Check paper before making a COPY.");
                }
                // Pace the actual bytes, rather than enqueueing entire raster bands.
                if (data.length > 512 && pacingMs > 0) Thread.sleep(pacingMs);
            }
            if (!active.compareAndSet(true, false)) {
                throw new IllegalStateException("Printer write timed out. Check paper before making a COPY.");
            }
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            abort();
            throw new IllegalStateException("Printer write interrupted. Check paper before making a COPY.", e);
        } catch (RuntimeException e) {
            abort();
            throw e;
        } finally {
            active.set(false);
            deadline.cancel(false);
        }
    }
}
