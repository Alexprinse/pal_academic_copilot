import 'package:flutter/material.dart';

/// Represents a single detected OCR text token or line with its spatial geometry.
class TimetableOcrItem {
  final String text;
  final Rect boundingBox;
  final double? confidence;

  const TimetableOcrItem({
    required this.text,
    required this.boundingBox,
    this.confidence,
  });

  double get left => boundingBox.left;
  double get top => boundingBox.top;
  double get right => boundingBox.right;
  double get bottom => boundingBox.bottom;
  double get width => boundingBox.width;
  double get height => boundingBox.height;

  Offset get center => boundingBox.center;

  TimetableOcrItem copyWith({
    String? text,
    Rect? boundingBox,
    double? confidence,
  }) {
    return TimetableOcrItem(
      text: text ?? this.text,
      boundingBox: boundingBox ?? this.boundingBox,
      confidence: confidence ?? this.confidence,
    );
  }

  @override
  String toString() => 'TimetableOcrItem("$text", rect: $boundingBox)';
}
