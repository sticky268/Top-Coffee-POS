package com.example.top_coffee_pos

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.util.Log
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

    var replySubmitted = false

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
                    if (replySubmitted) {
                        return
                    }

                    replySubmitted = true

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
        if (!replySubmitted) {
            replySubmitted = true

            result.error(
                "CONNECT_ERROR",
                e.message,
                null,
            )
        }
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

                "printKhmerTest" -> {
                    try {
                        val currentPrinter = printer
                            ?: throw IllegalStateException("Printer is not connected.")

                        val bitmapWidth = 576
                        val bitmapHeight = 260

                        val bitmap = Bitmap.createBitmap(
                            bitmapWidth,
                            bitmapHeight,
                            Bitmap.Config.ARGB_8888,
                        )

                        val canvas = Canvas(bitmap)
                        canvas.drawColor(Color.WHITE)

                        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                            color = Color.BLACK
                            typeface = Typeface.create(
                                "sans-serif",
                                Typeface.NORMAL,
                            )
                        }

                        paint.textSize = 32f
                        canvas.drawText(
                            "TOP COFFEE",
                            20f,
                            45f,
                            paint,
                        )

                        paint.textSize = 30f
                        canvas.drawText(
                            "\u179f\u17bd\u179f\u17d2\u178f\u17b8 \u1780\u17b6\u17a0\u17d2\u179c\u17c1",
                            20f,
                            95f,
                            paint,
                        )

                        canvas.drawText(
                            "\u1780\u17b6\u17a0\u17d2\u179c\u17c1 Coffee 123",
                            20f,
                            145f,
                            paint,
                        )

                        canvas.drawText(
                            "\u179f\u17bc\u1798\u17a2\u179a\u1782\u17bb\u178e",
                            20f,
                            195f,
                            paint,
                        )

                        currentPrinter
                            .initializePrinter()
                            .printBitmap(
                                bitmap,
                                POSConst.ALIGNMENT_LEFT,
                                576,
                                POSConst.BMP_NORMAL,
                            )
                            .feedLine(3)
                            .cutHalfAndFeed(1)

                        bitmap.recycle()

                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(
                            "TopCoffeePrinter",
                            "printKhmerTest failed",
                            e,
                        )

                        result.error(
                            "PRINT_KHMER_TEST_FAILED",
                            e.message,
                            null,
                        )
                    }
                }
                "printBitmapStressTest" -> {
                    try {
                        val currentPrinter = printer
                            ?: throw IllegalStateException("Printer is not connected.")

                        val heights = listOf(260, 600, 1000, 1600)

                        currentPrinter.initializePrinter()

                        for (height in heights) {
                            val bitmap = Bitmap.createBitmap(
                                576,
                                height,
                                Bitmap.Config.ARGB_8888,
                            )

                            val canvas = Canvas(bitmap)
                            canvas.drawColor(Color.WHITE)

                            val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                                color = Color.BLACK
                                typeface = Typeface.create(
                                    "sans-serif",
                                    Typeface.NORMAL,
                                )
                            }

                            paint.textSize = 30f

                            canvas.drawText(
                                "BITMAP HEIGHT TEST: ${height}px",
                                20f,
                                45f,
                                paint,
                            )

                            canvas.drawText(
                                "TOP COFFEE",
                                20f,
                                95f,
                                paint,
                            )

                            canvas.drawText(
                                "\u179f\u17bd\u179f\u17d2\u178f\u17b8 \u1780\u1780\u17d2\u1780\u17c1",
                                20f,
                                145f,
                                paint,
                            )

                            canvas.drawText(
                                "\u1780\u1780\u17d2\u1780\u17c1 Coffee 123",
                                20f,
                                195f,
                                paint,
                            )

                            canvas.drawText(
                                "\u179f\u17bc\u1798\u17a2\u179a\u1782\u17bb\u178e",
                                20f,
                                245f,
                                paint,
                            )

                            var y = 300f
                            while (y < height - 20f) {
                                canvas.drawText(
                                    "ABCDEFGHIJKLMNOPQRSTUVWXYZ 1234567890",
                                    20f,
                                    y,
                                    paint,
                                )
                                y += 45f
                            }

                            currentPrinter
                                .printBitmap(
                                    bitmap,
                                    POSConst.ALIGNMENT_LEFT,
                                    576,
                                    POSConst.BMP_NORMAL,
                                )
                                .feedLine(2)

                            bitmap.recycle()
                        }

                        currentPrinter
                            .feedLine(3)
                            .cutHalfAndFeed(1)

                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(
                            "TopCoffeePrinter",
                            "printBitmapStressTest failed",
                            e,
                        )

                        result.error(
                            "PRINT_BITMAP_STRESS_TEST_FAILED",
                            e.message,
                            null,
                        )
                    }
                }
                "printReceiptBitmapTest" -> {
    try {
        val currentPrinter = printer
            ?: throw IllegalStateException("Printer is not connected.")

        val bitmap = Bitmap.createBitmap(
            576,
            700,
            Bitmap.Config.ARGB_8888,
        )

        val canvas = Canvas(bitmap)
        canvas.drawColor(Color.WHITE)

        val khmerTypeface = Typeface.createFromAsset(
            assets,
            "fonts/NotoSansKhmerUI-Regular.ttf",
        )

        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.BLACK
            typeface = khmerTypeface
        }

        var y = 50f
        paint.textSize = 34f
        paint.typeface = Typeface.create(khmerTypeface, Typeface.BOLD)
        canvas.drawText(
            "TOP COFFEE",
            20f,
            y,
            paint,
        )

        y += 60f

        paint.textSize = 30f
        paint.typeface = Typeface.create(
            "sans-serif",
            Typeface.NORMAL,
        )

        canvas.drawText(
            "TEST SHOP NAME",
            20f,
            y,
            paint,
        )

        y += 55f

        canvas.drawText(
            "Order #12345",
            20f,
            y,
            paint,
        )

        y += 55f

        canvas.drawText(
            "TOTAL: 12.50",
            20f,
            y,
            paint,
        )

        y += 55f

        canvas.drawText(
            "\u179f\u17bd\u179f\u17d2\u178f\u17b8 \u1780\u1780\u17d2\u1780\u17c1",
            20f,
            y,
            paint,
        )

        y += 55f

        canvas.drawText(
            "\u179f\u17bc\u1798\u17a2\u179a\u1782\u17bb\u178e",
            20f,
            y,
            paint,
        )

        currentPrinter.initializePrinter()

        // Send the bitmap first and give the async printer queue time to drain.
        currentPrinter.printBitmap(
            bitmap,
            POSConst.ALIGNMENT_LEFT,
            576,
            POSConst.BMP_NORMAL,
        )

        Thread.sleep(1000)

        // Send feed and cut only after the bitmap has had time to finish.
        currentPrinter
            .feedLine(3)
            .cutHalfAndFeed(1)

        bitmap.recycle()
        result.success(true)
    } catch (e: Exception) {
        Log.e(
            "TopCoffeePrinter",
            "printReceiptBitmapTest failed",
            e,
        )

        result.error(
            "PRINT_RECEIPT_BITMAP_TEST_FAILED",
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

        printReceiptBitmap(
            currentPrinter = currentPrinter,
            logoBytes = logoBytes,
            logoPosition = logoPosition,
            logoSize = logoSize,
            bodyFontSize = bodyFontSize,
            businessFontSize = businessFontSize,
            footerFontSize = footerFontSize,
            boldBusinessName = boldBusinessName,
            boldTotal = boldTotal,
            boldFooter = boldFooter,
            businessName = businessName,
            branchName = branchName,
            orderNumber = orderNumber,
            cashierName = cashierName,
            tableName = tableName,
            orderType = orderType,
            subtotal = subtotal,
            discount = discount,
            total = total,
            paymentMethod = paymentMethod,
            tendered = tendered,
            changeDue = changeDue,
            footer = footer,
            showSplitPayments = showSplitPayments,
            items = items,
            payments = payments,
        )

        result.success(true)
    } catch (e: Exception) {
        Log.e(
            "TopCoffeePrinter",
            "printReceipt failed",
            e,
        )

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

    private fun printReceiptBitmap(
        currentPrinter: POSPrinter,
        logoBytes: ByteArray?,
        logoPosition: String,
        logoSize: String,
        bodyFontSize: String,
        businessFontSize: String,
        footerFontSize: String,
        boldBusinessName: Boolean,
        boldTotal: Boolean,
        boldFooter: Boolean,
        businessName: String,
        branchName: String,
        orderNumber: String,
        cashierName: String,
        tableName: String,
        orderType: String,
        subtotal: String,
        discount: String,
        total: String,
        paymentMethod: String,
        tendered: String?,
        changeDue: String?,
        footer: String,
        showSplitPayments: Boolean,
        items: List<*>,
        payments: List<*>,
    ) {
        val receiptWidth = 576
        val left = 24f
        val right = 552f
        val contentWidth = right - left

        val khmerTypeface = Typeface.createFromAsset(
            assets,
            "fonts/NotoSansKhmerUI-Regular.ttf",
        )

        fun typeface(bold: Boolean): Typeface {
            return Typeface.create(khmerTypeface, if (bold) Typeface.BOLD else Typeface.NORMAL)
        }

        fun textSize(setting: String): Float {
            return when (setting) {
                "Small" -> 24f
                "Large" -> 34f
                else -> 28f
            }
        }

        fun wrapText(
            text: String,
            paint: Paint,
            maxWidth: Float,
        ): List<String> {
            if (text.isBlank()) {
                return listOf("")
            }

            val result = mutableListOf<String>()

            for (paragraph in text.replace("\r\n", "\n").split("\n")) {
                if (paragraph.isEmpty()) {
                    result.add("")
                    continue
                }

                var remaining = paragraph

                while (remaining.isNotEmpty()) {
                    val count = paint.breakText(
                        remaining,
                        true,
                        maxWidth,
                        null,
                    )

                    if (count <= 0) {
                        break
                    }

                    var end = count

                    if (count < remaining.length) {
                        val space = remaining.substring(0, count).lastIndexOf(' ')
                        if (space > 0) {
                            end = space
                        }
                    }

                    result.add(remaining.substring(0, end).trimEnd())
                    remaining = remaining.substring(end).trimStart()
                }
            }

            return result
        }

        val bodySize = textSize(bodyFontSize)
        val businessSize = textSize(businessFontSize)
        val footerSize = textSize(footerFontSize)

        val measurePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.BLACK
            typeface = typeface(false)
        }

        var estimatedHeight = 60

        fun estimateText(text: String, size: Float, bold: Boolean = false) {
            measurePaint.textSize = size
            measurePaint.typeface = typeface(bold)

            val lines = wrapText(
                text,
                measurePaint,
                contentWidth,
            )

            estimatedHeight += lines.size * (size + 14f).toInt()
        }

        if (logoBytes != null && logoBytes.isNotEmpty()) {
            val logo = BitmapFactory.decodeByteArray(
                logoBytes,
                0,
                logoBytes.size,
            )

            if (logo != null) {
                val logoWidth = when (logoSize) {
                    "Small" -> 160
                    "Large" -> 320
                    else -> 240
                }

                val scale = logoWidth.toFloat() / logo.width.toFloat()
                estimatedHeight += (logo.height * scale).toInt() + 24
                logo.recycle()
            }
        }

        if (businessName.isNotBlank()) {
            estimateText(businessName, businessSize, boldBusinessName)
        }

        if (branchName.isNotBlank()) {
            estimateText(branchName, bodySize, true)
        }

        if (orderNumber.isNotBlank()) {
            estimateText("Order #$orderNumber", bodySize)
        }

        if (orderType.isNotBlank()) {
            estimateText("Type: $orderType", bodySize)
        }

        if (tableName.isNotBlank()) {
            estimateText("Table: $tableName", bodySize)
        }

        if (cashierName.isNotBlank()) {
            estimateText("Cashier: $cashierName", bodySize)
        }

        val separator = "-".repeat(
            if (bodyFontSize == "Large") 24 else 48
        )

        estimatedHeight += 50

        for (rawItem in items) {
            val item = rawItem as? Map<*, *> ?: continue

            val name = item["name"]?.toString() ?: ""
            val quantity = item["quantity"]?.toString() ?: ""
            val unitPrice = item["unitPrice"]?.toString() ?: ""
            val lineTotal = item["lineTotal"]?.toString() ?: ""

            estimateText(
                name,
                bodySize,
            )

            estimatedHeight += (bodySize + 18f).toInt()
        }

        estimatedHeight += 60

        estimateText("Subtotal:        $subtotal", bodySize)

        if (discount != "0.00") {
            estimateText("Discount: $discount", bodySize)
        }

        estimateText(
            "TOTAL:           $total",
            bodySize,
            boldTotal,
        )

        if (paymentMethod.isNotBlank()) {
            estimateText("Payment:         $paymentMethod", bodySize)
        }

        if (showSplitPayments && payments.size > 1) {
            estimateText("PAYMENT", bodySize, true)

            for (rawPayment in payments) {
                val payment = rawPayment as? Map<*, *> ?: continue
                val method = payment["method"]?.toString() ?: ""
                val amount = payment["amount"]?.toString() ?: "0.00"

                estimateText(
                    "${method.padEnd(20)}\$$amount",
                    bodySize,
                )
            }
        }

        if (tendered != null) {
            estimateText("Tendered:        $tendered", bodySize)
        }

        if (changeDue != null) {
            estimateText("Change:          $changeDue", bodySize)
        }

        if (footer.isNotBlank()) {
            estimateText(
                footer,
                footerSize,
                boldFooter,
            )
        }

        estimatedHeight += 100

        val bitmap = Bitmap.createBitmap(
            receiptWidth,
            estimatedHeight.coerceAtLeast(700),
            Bitmap.Config.ARGB_8888,
        )

        try {
            val canvas = Canvas(bitmap)
            canvas.drawColor(Color.WHITE)

            val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.BLACK
                typeface = typeface(false)
                textSize = bodySize
            }

            var y = 40f

            fun drawWrapped(
                text: String,
                size: Float,
                bold: Boolean = false,
                alignment: Paint.Align = Paint.Align.LEFT,
            ) {
                if (text.isBlank()) {
                    return
                }

                paint.textSize = size
                paint.typeface = typeface(bold)
                paint.textAlign = alignment

                val x = when (alignment) {
                    Paint.Align.CENTER -> receiptWidth / 2f
                    Paint.Align.RIGHT -> right
                    else -> left
                }

                val lines = wrapText(
                    text,
                    paint,
                    contentWidth,
                )

                val lineHeight = size + 14f

                for (line in lines) {
                    canvas.drawText(
                        line,
                        x,
                        y,
                        paint,
                    )
                    y += lineHeight
                }

                y += 4f
            }

            fun drawSeparator() {
                paint.color = Color.BLACK
                paint.strokeWidth = 2f
                canvas.drawLine(
                    left,
                    y,
                    right,
                    y,
                    paint,
                )
                y += bodySize + 10f
            }

            if (logoBytes != null && logoBytes.isNotEmpty()) {
                val logoBitmap = BitmapFactory.decodeByteArray(
                    logoBytes,
                    0,
                    logoBytes.size,
                )

                if (logoBitmap != null) {
                    val logoWidth = when (logoSize) {
                        "Small" -> 160
                        "Large" -> 320
                        else -> 240
                    }

                    val scale =
                        logoWidth.toFloat() / logoBitmap.width.toFloat()

                    val logoHeight =
                        (logoBitmap.height * scale).toInt()

                    val scaledLogo = Bitmap.createScaledBitmap(
                        logoBitmap,
                        logoWidth,
                        logoHeight,
                        true,
                    )

                    val x = when (logoPosition) {
                        "Left" -> left
                        "Right" -> right - logoWidth
                        else -> (receiptWidth - logoWidth) / 2f
                    }

                    canvas.drawBitmap(
                        scaledLogo,
                        x,
                        y,
                        paint,
                    )

                    y += logoHeight + 24f

                    if (scaledLogo !== logoBitmap) {
                        scaledLogo.recycle()
                    }

                    logoBitmap.recycle()
                }
            }

            drawWrapped(
                businessName,
                businessSize,
                boldBusinessName,
                Paint.Align.CENTER,
            )

            if (branchName.isNotBlank()) {
                drawWrapped(
                    branchName,
                    bodySize,
                    true,
                    Paint.Align.CENTER,
                )
            }

            if (orderNumber.isNotBlank()) {
                drawWrapped(
                    "Order #$orderNumber",
                    bodySize,
                )
            }

            if (orderType.isNotBlank()) {
                drawWrapped(
                    "Type: $orderType",
                    bodySize,
                )
            }

            if (tableName.isNotBlank()) {
                drawWrapped(
                    "Table: $tableName",
                    bodySize,
                )
            }

            if (cashierName.isNotBlank()) {
                drawWrapped(
                    "Cashier: $cashierName",
                    bodySize,
                )
            }

            drawSeparator()

            paint.textSize = bodySize
            paint.typeface = typeface(false)
            paint.textAlign = Paint.Align.LEFT

            canvas.drawText(
                "ITEM",
                left,
                y,
                paint,
            )

            canvas.drawText(
                "QTY",
                270f,
                y,
                paint,
            )

            canvas.drawText(
                "PRICE",
                350f,
                y,
                paint,
            )

            canvas.drawText(
                "AMOUNT",
                455f,
                y,
                paint,
            )

            y += bodySize + 10f

            drawSeparator()

            for (rawItem in items) {
                val item = rawItem as? Map<*, *> ?: continue

                val name = item["name"]?.toString() ?: ""
                val quantity = item["quantity"]?.toString() ?: ""
                val unitPrice = item["unitPrice"]?.toString() ?: ""
                val lineTotal = item["lineTotal"]?.toString() ?: ""

                paint.textSize = bodySize
                paint.typeface = typeface(false)
                paint.textAlign = Paint.Align.LEFT

                val itemLines = wrapText(
                    name,
                    paint,
                    330f,
                )

                val safeItemLines = if (itemLines.isEmpty()) {
                    listOf("")
                } else {
                    itemLines
                }

                val lineHeight = bodySize + 10f

                for ((index, itemLine) in safeItemLines.withIndex()) {
                    canvas.drawText(
                        itemLine,
                        left,
                        y,
                        paint,
                    )

                    if (index == 0) {
                        canvas.drawText(
                            quantity,
                            270f,
                            y,
                            paint,
                        )

                        canvas.drawText(
                            if (unitPrice.isNotBlank()) "\$$unitPrice" else "",
                            350f,
                            y,
                            paint,
                        )

                        canvas.drawText(
                            if (lineTotal.isNotBlank()) "\$$lineTotal" else "",
                            455f,
                            y,
                            paint,
                        )
                    }

                    y += lineHeight
                }

                y += 4f
            }

            drawSeparator()

            drawWrapped(
                "Subtotal:        $subtotal",
                bodySize,
            )

            if (discount != "0.00") {
                drawWrapped(
                    "Discount: $discount",
                    bodySize,
                )
            }

            drawWrapped(
                "TOTAL:           $total",
                bodySize,
                boldTotal,
            )

            drawSeparator()

            if (paymentMethod.isNotBlank()) {
                drawWrapped(
                    "Payment:         $paymentMethod",
                    bodySize,
                )
            }

            if (showSplitPayments && payments.size > 1) {
                drawWrapped(
                    "PAYMENT",
                    bodySize,
                    true,
                )

                for (rawPayment in payments) {
                    val payment = rawPayment as? Map<*, *> ?: continue
                    val method = payment["method"]?.toString() ?: ""
                    val amount = payment["amount"]?.toString() ?: "0.00"

                    drawWrapped(
                        "${method.padEnd(20)}\$$amount",
                        bodySize,
                    )
                }
            }

            if (tendered != null) {
                drawWrapped(
                    "Tendered:        $tendered",
                    bodySize,
                )
            }

            if (changeDue != null) {
                drawWrapped(
                    "Change:          $changeDue",
                    bodySize,
                )
            }

            drawSeparator()

            if (footer.isNotBlank()) {
                drawWrapped(
                    footer,
                    footerSize,
                    boldFooter,
                    Paint.Align.CENTER,
                )
            }

            currentPrinter.initializePrinter()

            currentPrinter.printBitmap(
                bitmap,
                POSConst.ALIGNMENT_LEFT,
                576,
                POSConst.BMP_NORMAL,
            )

            Thread.sleep(1000)

            currentPrinter
                .feedLine(0)
                .cutHalfAndFeed(1)
        } finally {
            if (!bitmap.isRecycled) {
                bitmap.recycle()
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
