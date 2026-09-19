package com.example.top_coffee_pos

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import net.posprinter.IDeviceConnection
import net.posprinter.POSConnect
import net.posprinter.POSConst
import net.posprinter.POSPrinter

class MainActivity : FlutterActivity() {

    companion object {
        private const val PRINTER_CHANNEL = "top_coffee_pos/printer"
    }

    private var printerConnection: IDeviceConnection? = null
    private var printer: POSPrinter? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        POSConnect.init(applicationContext)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            PRINTER_CHANNEL,
        ).setMethodCallHandler { call, result ->

            when (call.method) {
                "connect" -> {
    val ipAddress = call.argument<String>("ip")

    if (ipAddress.isNullOrBlank()) {
        result.error(
            "INVALID_IP",
            "Printer IP address is required.",
            null,
        )
        return@setMethodCallHandler
    }

    try {
        printerConnection?.close()
        printer = null

        val connection = POSConnect.createDevice(
            POSConnect.DEVICE_TYPE_ETHERNET,
        )

        connection.connect(
            ipAddress,
            object : net.posprinter.IConnectListener {
                override fun onStatus(
                    code: Int,
                    connectInfo: String,
                    message: String,
                ) {
                    if (code == POSConnect.CONNECT_SUCCESS) {
                        printerConnection = connection
                        printer = POSPrinter(connection)

                        result.success(true)
                    } else {
                        connection.close()

                        result.error(
                            "CONNECT_ERROR",
                            "Could not connect to printer at $ipAddress.",
                            "$code: $message",
                        )
                    }
                }
            },
        )
    } catch (e: Exception) {
        result.error(
            "CONNECT_ERROR",
            e.message,
            null,
        )
    }
}

"printTest" -> {
                    try {
                        val currentPrinter = printer

                        if (currentPrinter == null) {
                            result.error(
                                "NOT_CONNECTED",
                                "Printer is not connected.",
                                null,
                            )
                            return@setMethodCallHandler
                        }

                        currentPrinter
                            .initializePrinter()
                            .printText(
                                "TOP COFFEE POS\n",
                                POSConst.ALIGNMENT_CENTER,
                                POSConst.FNT_BOLD,
                                POSConst.TXT_2WIDTH or POSConst.TXT_2HEIGHT,
                            )
                            .printString(
                                "Printer test successful\n" +
                                    "XP-N160II\n" +
                                    "Ethernet\n\n",
                            )
                            .feedLine(3)
                            .cutHalfAndFeed(1)

                        result.success(true)
                    } catch (e: Exception) {
                        result.error(
                            "PRINT_ERROR",
                            e.message,
                            null,
                        )
                    }
                }

                "printReceipt" -> {
                    try {
                        val currentPrinter = printer

                        if (currentPrinter == null) {
                            result.error(
                                "NOT_CONNECTED",
                                "Printer is not connected.",
                                null,
                            )
                            return@setMethodCallHandler
                        }

                        val orderNumber =
                            call.argument<String>("orderNumber") ?: "N/A"
                        val branchName =
                            call.argument<String>("branchName") ?: "TOP COFFEE"
                        val cashierName =
                            call.argument<String>("cashierName") ?: ""
                        val tableName =
                            call.argument<String>("tableName") ?: ""
                        val orderType =
                            call.argument<String>("orderType") ?: ""
                        val subtotal =
                            call.argument<String>("subtotal") ?: "0.00"
                        val discount =
                            call.argument<String>("discount") ?: "0.00"
                        val total =
                            call.argument<String>("total") ?: "0.00"
                        val paymentMethod =
                            call.argument<String>("paymentMethod") ?: ""
                        val tendered =
                            call.argument<String>("tendered")
                        val changeDue =
                            call.argument<String>("changeDue")

                        val items =
                            call.argument<List<*>>("items") ?: emptyList<Any?>()

                        currentPrinter.initializePrinter()

                        currentPrinter
                            .printText(
                                "$branchName\n",
                                POSConst.ALIGNMENT_CENTER,
                                POSConst.FNT_BOLD,
                                POSConst.TXT_2WIDTH,
                            )
                            .printString(
                                "Order #$orderNumber\n",
                            )

                        if (orderType.isNotBlank()) {
                            currentPrinter.printString(
                                "$orderType\n",
                            )
                        }

                        if (tableName.isNotBlank()) {
                            currentPrinter.printString(
                                "Table: $tableName\n",
                            )
                        }

                        if (cashierName.isNotBlank()) {
                            currentPrinter.printString(
                                "Cashier: $cashierName\n",
                            )
                        }

                        currentPrinter.printString(
                            "--------------------------------\n",
                        )

                        for (rawItem in items) {
                            val item = rawItem as? Map<*, *> ?: continue

                            val name =
                                item["name"]?.toString() ?: "Item"
                            val quantity =
                                item["quantity"]?.toString() ?: "1"
                            val lineTotal =
                                item["lineTotal"]?.toString() ?: "0.00"

                            currentPrinter.printString(
                                "$quantity x $name    $lineTotal\n",
                            )
                        }

                        currentPrinter.printString(
                            "--------------------------------\n" +
                                "Subtotal:        $subtotal\n" +
                                "Discount:        $discount\n" +
                                "TOTAL:           $total\n" +
                                "\n" +
                                "Payment:         $paymentMethod\n",
                        )

                        if (tendered != null) {
                            currentPrinter.printString(
                                "Tendered:        $tendered\n",
                            )
                        }

                        if (changeDue != null) {
                            currentPrinter.printString(
                                "Change:          $changeDue\n",
                            )
                        }

                        currentPrinter
                            .printString(
                                "\nThank you for visiting Top Coffee!\n",
                            )
                            .feedLine(3)
                            .cutHalfAndFeed(1)

                        result.success(true)
                    } catch (e: Exception) {
                        result.error(
                            "PRINT_ERROR",
                            e.message,
                            null,
                        )
                    }
                }
                "disconnect" -> {
                    printer = null
                    printerConnection?.close()
                    printerConnection = null
                    result.success(true)
                }

                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onDestroy() {
        printer = null
        printerConnection?.close()
        printerConnection = null
        POSConnect.exit()

        super.onDestroy()
    }
}