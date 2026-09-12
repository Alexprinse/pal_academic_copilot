import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class PdfPageRendererService {
  static const MethodChannel _channel =
      MethodChannel('com.iqoo.pal/pdf_renderer');

  /// Gets the total page count of a PDF file using the native PdfRenderer.
  Future<int> getPdfPageCount(String pdfPath) async {
    try {
      final file = File(pdfPath);
      if (!file.existsSync()) {
        debugPrint(
            '[PdfPageRendererService] PDF file does not exist: $pdfPath');
        return 0;
      }
      final int? count = await _channel.invokeMethod<int>('getPdfPageCount', {
        'pdfPath': pdfPath,
      });
      return count ?? 0;
    } catch (e) {
      debugPrint('[PdfPageRendererService] Failed to get page count: $e');
      return 0;
    }
  }

  /// Renders a specific page (0-indexed) to an image file (PNG) and returns the absolute file path.
  Future<String?> renderPdfPage(
    String pdfPath,
    int pageIndex, {
    double scale = 2.0,
  }) async {
    try {
      final file = File(pdfPath);
      if (!file.existsSync()) {
        debugPrint(
            '[PdfPageRendererService] PDF file does not exist: $pdfPath');
        return null;
      }
      final String? imagePath =
          await _channel.invokeMethod<String>('renderPdfPage', {
        'pdfPath': pdfPath,
        'pageIndex': pageIndex,
        'scale': scale,
      });
      return imagePath;
    } catch (e) {
      debugPrint(
          '[PdfPageRendererService] Failed to render page $pageIndex: $e');
      return null;
    }
  }

  /// Cleans up any cached rendered page images.
  Future<void> cleanupPdfCache() async {
    try {
      await _channel.invokeMethod('cleanupPdfCache');
    } catch (e) {
      debugPrint('[PdfPageRendererService] Failed to clean up cache: $e');
    }
  }
}
