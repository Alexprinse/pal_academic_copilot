import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../models/timetable_ocr_item.dart';

class TimetableOcrException implements Exception {
  final String message;
  const TimetableOcrException(this.message);

  @override
  String toString() => 'TimetableOcrException: $message';
}

class TimetableOcrResult {
  final List<TimetableOcrItem> items;
  final String imagePath;
  final int processingTimeMs;

  const TimetableOcrResult({
    required this.items,
    required this.imagePath,
    required this.processingTimeMs,
  });
}

class TimetableOcrService {
  static final TimetableOcrService instance = TimetableOcrService._();
  TimetableOcrService._();

  TextRecognizer? _textRecognizer;

  void init() {
    _textRecognizer ??= TextRecognizer(script: TextRecognitionScript.latin);
  }

  /// Extracts spatial OCR tokens and lines from a local timetable image.
  /// Strictly on-device. Zero cloud or network requests.
  Future<TimetableOcrResult> processImage(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw TimetableOcrException('Image file does not exist: $filePath');
    }

    final stopwatch = Stopwatch()..start();
    _textRecognizer ??= TextRecognizer(script: TextRecognitionScript.latin);

    final inputImage = InputImage.fromFilePath(filePath);
    final RecognizedText recognizedText =
        await _textRecognizer!.processImage(inputImage);
    stopwatch.stop();

    final List<TimetableOcrItem> items = [];

    for (final block in recognizedText.blocks) {
      for (final line in block.lines) {
        final lineText = line.text.trim();
        if (lineText.isEmpty) continue;

        // Check if line contains wide inter-element gaps that suggest separate table cells
        if (_shouldSplitLine(line)) {
          for (final element in line.elements) {
            final elText = element.text.trim();
            if (elText.isNotEmpty) {
              items.add(
                TimetableOcrItem(
                  text: elText,
                  boundingBox: element.boundingBox,
                  confidence: element.confidence,
                ),
              );
            }
          }
        } else {
          items.add(
            TimetableOcrItem(
              text: lineText,
              boundingBox: line.boundingBox,
              confidence: line.confidence,
            ),
          );
        }
      }
    }

    if (items.isEmpty) {
      throw const TimetableOcrException(
        'Could not detect any text in the image. Please make sure the timetable is well lit and in focus.',
      );
    }

    debugPrint(
      '[TIMETABLE OCR] Detected ${items.length} OCR items in ${stopwatch.elapsedMilliseconds}ms from $filePath',
    );

    return TimetableOcrResult(
      items: items,
      imagePath: filePath,
      processingTimeMs: stopwatch.elapsedMilliseconds,
    );
  }

  /// Determines if a recognized line should be split into individual elements
  /// (e.g. when ML Kit grouped multiple distinct table columns into one line).
  bool _shouldSplitLine(TextLine line) {
    if (line.elements.length < 2) return false;

    for (int i = 0; i < line.elements.length - 1; i++) {
      final current = line.elements[i];
      final next = line.elements[i + 1];
      final gap = next.boundingBox.left - current.boundingBox.right;

      // If horizontal gap between elements is greater than 1.5x element height,
      // it is very likely two separate table column cells rather than normal sentence spacing.
      if (gap > current.boundingBox.height * 1.5) {
        return true;
      }
    }
    return false;
  }

  void dispose() {
    _textRecognizer?.close();
    _textRecognizer = null;
  }
}
