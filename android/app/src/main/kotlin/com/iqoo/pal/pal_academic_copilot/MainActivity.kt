package com.iqoo.pal.pal_academic_copilot

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.iqoo.pal/pdf_renderer"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getPdfPageCount" -> {
                    val pdfPath = call.argument<String>("pdfPath")
                    if (pdfPath == null) {
                        result.error("INVALID_ARGS", "pdfPath is required", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val file = File(pdfPath)
                        if (!file.exists()) {
                            result.error("FILE_NOT_FOUND", "PDF file not found at $pdfPath", null)
                            return@setMethodCallHandler
                        }
                        val fileDescriptor = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
                        val renderer = PdfRenderer(fileDescriptor)
                        val count = renderer.pageCount
                        renderer.close()
                        fileDescriptor.close()
                        result.success(count)
                    } catch (e: Exception) {
                        result.error("RENDER_ERROR", e.localizedMessage, null)
                    }
                }
                "renderPdfPage" -> {
                    val pdfPath = call.argument<String>("pdfPath")
                    val pageIndex = call.argument<Int>("pageIndex") ?: 0
                    val scale = (call.argument<Double>("scale") ?: 2.0).toFloat()

                    if (pdfPath == null) {
                        result.error("INVALID_ARGS", "pdfPath is required", null)
                        return@setMethodCallHandler
                    }

                    try {
                        val file = File(pdfPath)
                        if (!file.exists()) {
                            result.error("FILE_NOT_FOUND", "PDF file not found at $pdfPath", null)
                            return@setMethodCallHandler
                        }

                        val fileDescriptor = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
                        val renderer = PdfRenderer(fileDescriptor)

                        if (pageIndex < 0 || pageIndex >= renderer.pageCount) {
                            renderer.close()
                            fileDescriptor.close()
                            result.error("INVALID_INDEX", "Page index $pageIndex out of range (0..${renderer.pageCount - 1})", null)
                            return@setMethodCallHandler
                        }

                        val page = renderer.openPage(pageIndex)
                        val width = (page.width * scale).toInt()
                        val height = (page.height * scale).toInt()

                        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                        val canvas = Canvas(bitmap)
                        canvas.drawColor(Color.WHITE)
                        page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                        page.close()
                        renderer.close()
                        fileDescriptor.close()

                        val outputDir = File(context.cacheDir, "pal_pdf_cache")
                        if (!outputDir.exists()) {
                            outputDir.mkdirs()
                        }
                        val outputFile = File(outputDir, "${file.nameWithoutExtension}_p${pageIndex}.png")
                        val outStream = FileOutputStream(outputFile)
                        bitmap.compress(Bitmap.CompressFormat.PNG, 100, outStream)
                        outStream.flush()
                        outStream.close()
                        bitmap.recycle()

                        result.success(outputFile.absolutePath)
                    } catch (e: Exception) {
                        result.error("RENDER_ERROR", e.localizedMessage, null)
                    }
                }
                "cleanupPdfCache" -> {
                    try {
                        val outputDir = File(context.cacheDir, "pal_pdf_cache")
                        if (outputDir.exists()) {
                            outputDir.deleteRecursively()
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("CLEANUP_ERROR", e.localizedMessage, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
