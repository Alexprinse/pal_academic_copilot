enum ExtractionType {
  nativePdf,
  printedOcr,
  handwrittenOcr,
  userCorrected,
  audioTranscript;

  String get label {
    switch (this) {
      case ExtractionType.nativePdf:
        return 'Digital PDF';
      case ExtractionType.printedOcr:
        return 'Printed OCR';
      case ExtractionType.handwrittenOcr:
        return 'Handwritten OCR';
      case ExtractionType.userCorrected:
        return 'User Corrected';
      case ExtractionType.audioTranscript:
        return 'Audio Transcript';
    }
  }

  bool get isOcr =>
      this == ExtractionType.printedOcr ||
      this == ExtractionType.handwrittenOcr ||
      this == ExtractionType.userCorrected;

  bool get isAudio => this == ExtractionType.audioTranscript;
}

class ExtractedPageContent {
  final String documentName;
  final int pageNumber;
  final String text;
  final ExtractionType extractionType;
  final double confidence;
  final bool isLowQuality;
  final String? warningMessage;
  final String? imagePath;
  final DateTime extractedAt;

  ExtractedPageContent({
    required this.documentName,
    required this.pageNumber,
    required this.text,
    required this.extractionType,
    this.confidence = 1.0,
    this.isLowQuality = false,
    this.warningMessage,
    this.imagePath,
    DateTime? extractedAt,
  }) : extractedAt = extractedAt ?? DateTime.now();

  static const Object _sentinel = Object();

  ExtractedPageContent copyWith({
    String? documentName,
    int? pageNumber,
    String? text,
    ExtractionType? extractionType,
    double? confidence,
    bool? isLowQuality,
    Object? warningMessage = _sentinel,
    String? imagePath,
    DateTime? extractedAt,
  }) {
    return ExtractedPageContent(
      documentName: documentName ?? this.documentName,
      pageNumber: pageNumber ?? this.pageNumber,
      text: text ?? this.text,
      extractionType: extractionType ?? this.extractionType,
      confidence: confidence ?? this.confidence,
      isLowQuality: isLowQuality ?? this.isLowQuality,
      warningMessage: identical(warningMessage, _sentinel)
          ? this.warningMessage
          : warningMessage as String?,
      imagePath: imagePath ?? this.imagePath,
      extractedAt: extractedAt ?? this.extractedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'documentName': documentName,
      'pageNumber': pageNumber,
      'text': text,
      'extractionType': extractionType.name,
      'confidence': confidence,
      'isLowQuality': isLowQuality,
      'warningMessage': warningMessage,
      'imagePath': imagePath,
      'extractedAt': extractedAt.toIso8601String(),
    };
  }

  factory ExtractedPageContent.fromMap(Map<String, dynamic> map) {
    ExtractionType type = ExtractionType.nativePdf;
    final typeStr = map['extractionType'] as String?;
    if (typeStr != null) {
      for (final val in ExtractionType.values) {
        if (val.name == typeStr) {
          type = val;
          break;
        }
      }
    }

    return ExtractedPageContent(
      documentName: map['documentName'] as String,
      pageNumber: map['pageNumber'] as int,
      text: map['text'] as String,
      extractionType: type,
      confidence: (map['confidence'] as num?)?.toDouble() ?? 1.0,
      isLowQuality: map['isLowQuality'] as bool? ?? false,
      warningMessage: map['warningMessage'] as String?,
      imagePath: map['imagePath'] as String?,
      extractedAt: map['extractedAt'] != null
          ? DateTime.tryParse(map['extractedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
