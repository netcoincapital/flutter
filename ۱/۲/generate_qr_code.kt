package com.laxce.adl.utility

import android.content.Context
import android.graphics.*
import com.google.zxing.BarcodeFormat
import com.google.zxing.qrcode.QRCodeWriter

fun generateCircleQRCode(
    context: Context,
    text: String,
    size: Int = 512,
    logoResId: Int,
    logoWidth: Float,
    logoHeight: Float
): Bitmap? {
    return try {
        val qrCodeWriter = QRCodeWriter()
        val bitMatrix = qrCodeWriter.encode(text, BarcodeFormat.QR_CODE, size, size)

        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val paint = Paint().apply {
            color = Color.BLACK
            isAntiAlias = true
        }
        val backgroundPaint = Paint().apply {
            color = Color.WHITE
            isAntiAlias = true
        }

        // اندازه هر سلول
        val cellSize = size / bitMatrix.width.toFloat()

        // رسم پس‌زمینه سفید
        canvas.drawRect(0f, 0f, size.toFloat(), size.toFloat(), backgroundPaint)

        // رسم QR Code
        for (x in 0 until bitMatrix.width) {
            for (y in 0 until bitMatrix.height) {
                if (bitMatrix[x, y]) {
                    val left = x * cellSize
                    val top = y * cellSize
                    canvas.drawRect(left, top, left + cellSize, top + cellSize, paint)
                }
            }
        }

        // بارگذاری لوگو از منابع
        val originalLogo = BitmapFactory.decodeResource(context.resources, logoResId)
        val logo = originalLogo?.let { makeLogoBlack(it) } // تغییر رنگ لوگو به سیاه

        if (logo != null) {
            // رسم مربع سفید پشت لوگو
            val centerX = size / 2f
            val centerY = size / 2f

            // افزایش اندازه مربع پشت لوگو
            val backgroundWidth = logoWidth + 30f // 20 پیکسل بزرگ‌تر از عرض لوگو
            val backgroundHeight = logoHeight + 70f // 20 پیکسل بزرگ‌تر از ارتفاع لوگو

            // رسم پس‌زمینه سفید پشت لوگو
            canvas.drawRect(
                centerX - backgroundWidth / 2,
                centerY - backgroundHeight / 2,
                centerX + backgroundWidth / 2,
                centerY + backgroundHeight / 2,
                backgroundPaint
            )

            // رسم لوگو در مرکز QR Code
            val left = centerX - logoWidth / 2
            val top = centerY - logoHeight / 2
            val logoRect = RectF(left, top, left + logoWidth, top + logoHeight)
            canvas.drawBitmap(logo, null, logoRect, null)
        }


        bitmap
    } catch (e: Exception) {
        e.printStackTrace()
        null
    }
}


// تابع تغییر رنگ لوگو به سیاه
fun makeLogoBlack(originalLogo: Bitmap): Bitmap {
    val width = originalLogo.width
    val height = originalLogo.height
    val blackLogo = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(blackLogo)
    val paint = Paint().apply {
        colorFilter = PorterDuffColorFilter(Color.BLACK, PorterDuff.Mode.SRC_IN)
    }
    canvas.drawBitmap(originalLogo, 0f, 0f, paint)
    return blackLogo
}
