package com.example.top_coffee_pos

import java.lang.reflect.Proxy
import net.posprinter.IDeviceConnection
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ConfirmedPosPrinterTest {
    @Test fun sdkEncodingUsesCheckedWritesForSingleAndListCommands() {
        val writes = mutableListOf<ByteArray>()
        val connection = Proxy.newProxyInstance(
            IDeviceConnection::class.java.classLoader,
            arrayOf(IDeviceConnection::class.java),
        ) { _, method, args ->
            when (method.name) {
                "sendSync" -> (args!![0] as ByteArray).let { writes.add(it); it.size }
                "sendData" -> error("SDK asynchronous queue must not be used")
                else -> error("Unexpected transport call: ${method.name}")
            }
        } as IDeviceConnection
        ConfirmedPosPrinter(connection)
            .initializePrinter()
            .printText("TOP COFFEE\n", 1, 8, 17)
            .feedLine(3)
            .cutHalfAndFeed(1)
        assertTrue(writes.isNotEmpty())
        assertTrue(writes.first().contentEquals(byteArrayOf(27, 64)))
        assertTrue(writes.last().contentEquals(byteArrayOf(29, 86, 66, 1)))
    }

    @Test fun failedSdkWritePreventsCutAndAnotherSend() {
        var writes = 0
        var closes = 0
        val connection = Proxy.newProxyInstance(
            IDeviceConnection::class.java.classLoader,
            arrayOf(IDeviceConnection::class.java),
        ) { _, method, _ ->
            when (method.name) {
                "sendSync" -> { writes++; -1 }
                "closeSync" -> { closes++; null }
                else -> error("Unexpected transport call: ${method.name}")
            }
        } as IDeviceConnection
        val printer = ConfirmedPosPrinter(connection)
        for (attempt in 1..2) {
            try {
                printer.initializePrinter().cutHalfAndFeed(1)
                error("Failed write must not report success")
            } catch (_: IllegalStateException) { }
        }
        assertEquals(1, writes)
        assertEquals(1, closes)
    }
}
