package com.example.top_coffee_pos

import android.graphics.BitmapFactory
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

                        val logoBytes =
                            call.argument<ByteArray>("logoBytes")
                        val logoPosition =
                            call.argument<String>("logoPosition")
                                ?: "Center"
                        val logoSize =
                            call.argument<String>("logoSize")
                                ?: "Medium"
                        val bodyFontSize =
                            call.argument<String>("bodyFontSize")
                                ?: "Medium"
                        val businessFontSize =
                            call.argument<String>("businessFontSize")
                                ?: "Large"
                        val footerFontSize =
                            call.argument<String>("footerFontSize")
                                ?: "Medium"
                        val boldBusinessName =
                            call.argument<Boolean>("boldBusinessName")
                                ?: true
                        val boldTotal =
                            call.argument<Boolean>("boldTotal")
                                ?: true
                        val boldFooter =
                            call.argument<Boolean>("boldFooter")
                                ?: true

                        val bodyWidth = when (bodyFontSize) {
                            "Small" -> POSConst.TXT_1WIDTH
                            "Large" -> POSConst.TXT_2WIDTH
                            else -> POSConst.TXT_1WIDTH
                        }

                        val separator = if (bodyFontSize == "Large") {
                            "------------------------\n"
                        } else {
                            "------------------------------------------------\n"
                        }

                        val businessName =
                            call.argument<String>("businessName")
                                ?: "TOP COFFEE"
                        val branchName =
                            call.argument<String>("branchName") ?: ""
                        val orderNumber =
                            call.argument<String>("orderNumber") ?: ""
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
                        val footer =
                            call.argument<String>("footer")
                                ?: "Thank you for visiting Top Coffee!"
                        val showSplitPayments =
                            call.argument<Boolean>("showSplitPayments")
                                ?: true

                        val items =
                            call.argument<List<*>>("items")
                                ?: emptyList<Any?>()

                        val payments =
                            call.argument<List<*>>("payments")
                                ?: emptyList<Any?>()

                        currentPrinter.initializePrinter()

                        if (logoBytes != null && logoBytes.isNotEmpty()) {
                            val logoBitmap =
                                BitmapFactory.decodeByteArray(
                                    logoBytes,
                                    0,
                                    logoBytes.size,
                                )

                            if (logoBitmap != null) {
                                val alignment =
                                    when (logoPosition) {
                                        "Left" ->
                                            POSConst.ALIGNMENT_LEFT
                                        "Right" ->
                                            POSConst.ALIGNMENT_RIGHT
                                        else ->
                                            POSConst.ALIGNMENT_CENTER
                                    }

                                val logoWidth =
                                    when (logoSize) {
                                        "Small" -> 160
                                        "Large" -> 320
                                        else -> 240
                                    }

                                currentPrinter.printBitmap(
                                    logoBitmap,
                                    alignment,
                                    logoWidth,
                                )
                            }
                        }

                        if (businessName.isNotBlank()) {
                            val businessFont = if (boldBusinessName) {
                                POSConst.FNT_BOLD
                            } else {
                                POSConst.FNT_DEFAULT
                            }

                            val businessWidth = when (businessFontSize) {
                                "Small" -> POSConst.TXT_1WIDTH
                                "Large" -> POSConst.TXT_3WIDTH
                                else -> POSConst.TXT_2WIDTH
                            }

                            currentPrinter.printText(
                                "$businessName\n",
                                POSConst.ALIGNMENT_CENTER,
                                businessFont,
                                businessWidth,
                            )
                        }

                        if (branchName.isNotBlank()) {
                            currentPrinter.printText(
                                "$branchName\n",
                                POSConst.ALIGNMENT_CENTER,
                                POSConst.FNT_BOLD,
                                POSConst.TXT_1WIDTH,
                            )
                        }

                        if (orderNumber.isNotBlank()) {
                            currentPrinter.printText(
                                "Order #$orderNumber\n",
                                POSConst.ALIGNMENT_LEFT,
                                POSConst.FNT_DEFAULT,
                                bodyWidth,
                            )
                        }

                        if (orderType.isNotBlank()) {
                            currentPrinter.printText(
                                "Type: $orderType\n",
                                POSConst.ALIGNMENT_LEFT,
                                POSConst.FNT_DEFAULT,
                                bodyWidth,
                            )
                        }

                        if (tableName.isNotBlank()) {
                            currentPrinter.printText(
                                "Table: $tableName\n",
                                POSConst.ALIGNMENT_LEFT,
                                POSConst.FNT_DEFAULT,
                                bodyWidth,
                            )
                        }

                        if (cashierName.isNotBlank()) {
                            currentPrinter.printText(
                                "Cashier: $cashierName\n",
                                POSConst.ALIGNMENT_LEFT,
                                POSConst.FNT_DEFAULT,
                                bodyWidth,
                            )
                        }

                        currentPrinter.printString(
                            separator +
                                "ITEM                  QTY    PRICE    AMOUNT\n" +
                                separator,
                        )

                        for (rawItem in items) {
                            val item = rawItem as? Map<*, *> ?: continue

                            val name =
                                item["name"]?.toString() ?: ""
                            val quantity =
                                item["quantity"]?.toString() ?: ""
                            val unitPrice =
                                item["unitPrice"]?.toString() ?: ""
                            val lineTotal =
                                item["lineTotal"]?.toString() ?: ""

                            val shortName = if (name.length > 20) {
                                name.take(20)
                            } else {
                                name
                            }

                            val itemColumn =
                                shortName.padEnd(20)
                            val quantityColumn =
                                quantity.padStart(3).padEnd(7)
                            val priceColumn =
                                if (unitPrice.isNotBlank()) {
                                    "\$$unitPrice".padStart(7)
                                } else {
                                    "".padStart(7)
                                }
                            val amountColumn =
                                if (lineTotal.isNotBlank()) {
                                    "\$$lineTotal".padStart(8)
                                } else {
                                    "".padStart(8)
                                }

                            currentPrinter.printText(
                                "$itemColumn$quantityColumn" +
                                    "$priceColumn$amountColumn\n",
                                POSConst.ALIGNMENT_LEFT,
                                POSConst.FNT_DEFAULT,
                                bodyWidth,
                            )

                        }

                        currentPrinter.printString(
                            separator,
                        )

                        currentPrinter.printText(
                            "Subtotal:        $subtotal\n",
                            POSConst.ALIGNMENT_LEFT,
                            POSConst.FNT_DEFAULT,
                            bodyWidth,
                        )

                        if (discount != "0.00") {
                            currentPrinter.printText(
                                "Discount:        $discount\n",
                                POSConst.ALIGNMENT_LEFT,
                                POSConst.FNT_DEFAULT,
                                bodyWidth,
                            )
                        }

                        val totalFont = if (boldTotal) {
                            POSConst.FNT_BOLD
                        } else {
                            POSConst.FNT_DEFAULT
                        }

                        currentPrinter.printText(
                            "TOTAL:           $total\n",
                            POSConst.ALIGNMENT_LEFT,
                            totalFont,
                            bodyWidth,
                        )

                        currentPrinter.printString(
                            separator,
                        )

                        if (paymentMethod.isNotBlank()) {
                            currentPrinter.printText(
                                "Payment:         $paymentMethod\n",
                                POSConst.ALIGNMENT_LEFT,
                                POSConst.FNT_DEFAULT,
                                bodyWidth,
                            )
                        }

                        if (
                            showSplitPayments &&
                            payments.size > 1
                        ) {
                            currentPrinter.printText(
                                "PAYMENT\n",
                                POSConst.ALIGNMENT_LEFT,
                                POSConst.FNT_BOLD,
                                bodyWidth,
                            )

                            for (rawPayment in payments) {
                                val payment =
                                    rawPayment as? Map<*, *>
                                        ?: continue

                                val method =
                                    payment["method"]?.toString()
                                        ?: ""
                                val amount =
                                    payment["amount"]?.toString()
                                        ?: "0.00"

                                currentPrinter.printText(
                                    "${method.padEnd(20)}" +
                                        "\$$amount\n",
                                    POSConst.ALIGNMENT_LEFT,
                                    POSConst.FNT_DEFAULT,
                                    bodyWidth,
                                )
                            }
                        }

                        if (tendered != null) {
                            currentPrinter.printText(
                                "Tendered:        $tendered\n",
                                POSConst.ALIGNMENT_LEFT,
                                POSConst.FNT_DEFAULT,
                                bodyWidth,
                            )
                        }

                        if (changeDue != null) {
                            currentPrinter.printText(
                                "Change:          $changeDue\n",
                                POSConst.ALIGNMENT_LEFT,
                                POSConst.FNT_DEFAULT,
                                bodyWidth,
                            )
                        }

                        currentPrinter.printString(
                            separator,
                        )

                        if (footer.isNotBlank()) {
                            val footerFont = if (boldFooter) {
                                POSConst.FNT_BOLD
                            } else {
                                POSConst.FNT_DEFAULT
                            }

                            val footerWidth = when (footerFontSize) {
                                "Small" -> POSConst.TXT_1WIDTH
                                "Large" -> POSConst.TXT_2WIDTH
                                else -> POSConst.TXT_1WIDTH
                            }

                            currentPrinter.printText(
                                "$footer\n",
                                POSConst.ALIGNMENT_CENTER,
                                footerFont,
                                footerWidth,
                            )
                        }

                        currentPrinter
                            .printString(
                                "\n",
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