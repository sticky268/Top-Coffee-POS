package com.example.top_coffee_pos

import net.posprinter.IDeviceConnection
import net.posprinter.POSPrinter

/** Keep the SDK's ESC/POS encoder, but never discard a failed or queued write. */
class ConfirmedPosPrinter(connection: IDeviceConnection) : POSPrinter(connection) {
    private val writer = CheckedPrinterWriter(
        { data -> connection.sendSync(data) },
        { connection.closeSync() },
    )

    override fun sendData(data: ByteArray): POSPrinter {
        writer.write(data)
        return this
    }

    override fun sendData(data: MutableList<ByteArray>): POSPrinter {
        for (part in data) writer.write(part)
        return this
    }
}
