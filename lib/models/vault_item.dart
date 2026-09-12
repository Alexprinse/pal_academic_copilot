import 'extracted_page_content.dart';

class TextChunk {
  final String id;
  final String subject;
  final String unit;
  final String documentName;
  final int pageNumber;
  final String text;
  final int wordCount;
  final ExtractionType extractionType;
  final double confidence;

  TextChunk({
    required this.id,
    required this.subject,
    required this.unit,
    required this.documentName,
    required this.pageNumber,
    required this.text,
    required this.wordCount,
    this.extractionType = ExtractionType.nativePdf,
    this.confidence = 1.0,
  });

  bool get isOcr => extractionType.isOcr;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'subject': subject,
      'unit': unit,
      'documentName': documentName,
      'pageNumber': pageNumber,
      'text': text,
      'wordCount': wordCount,
      'extractionType': extractionType.name,
      'confidence': confidence,
    };
  }

  factory TextChunk.fromMap(Map<String, dynamic> map) {
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

    return TextChunk(
      id: map['id'] as String,
      subject: map['subject'] as String,
      unit: map['unit'] as String,
      documentName: map['documentName'] as String,
      pageNumber: map['pageNumber'] as int,
      text: map['text'] as String,
      wordCount: map['wordCount'] as int,
      extractionType: type,
      confidence: (map['confidence'] as num?)?.toDouble() ?? 1.0,
    );
  }
}

class ChunkMatch {
  final TextChunk chunk;
  final double score;

  ChunkMatch({required this.chunk, required this.score});

  Map<String, dynamic> toMap() => {
        'chunk': chunk.toMap(),
        'score': score,
      };

  factory ChunkMatch.fromMap(Map<String, dynamic> map) {
    return ChunkMatch(
      chunk: TextChunk.fromMap(map['chunk'] as Map<String, dynamic>),
      score: (map['score'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class VaultDocument {
  final String id;
  final String name;
  final String path;
  final String subject;
  final String unit;
  final int chunkCount;
  final int pageCount;
  final DateTime addedAt;
  final int ocrPageCount;
  final int nativePageCount;

  VaultDocument({
    required this.id,
    required this.name,
    required this.path,
    required this.subject,
    required this.unit,
    required this.chunkCount,
    required this.pageCount,
    required this.addedAt,
    this.ocrPageCount = 0,
    this.nativePageCount = 0,
  });

  bool get hasOcr => ocrPageCount > 0;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'path': path,
      'subject': subject,
      'unit': unit,
      'chunkCount': chunkCount,
      'pageCount': pageCount,
      'addedAt': addedAt.toIso8601String(),
      'ocrPageCount': ocrPageCount,
      'nativePageCount': nativePageCount,
    };
  }

  factory VaultDocument.fromMap(Map<String, dynamic> map) {
    return VaultDocument(
      id: map['id'] as String,
      name: map['name'] as String,
      path: map['path'] as String,
      subject: map['subject'] as String,
      unit: map['unit'] as String,
      chunkCount: map['chunkCount'] as int,
      pageCount: map['pageCount'] as int,
      addedAt: DateTime.parse(map['addedAt'] as String),
      ocrPageCount: map['ocrPageCount'] as int? ?? 0,
      nativePageCount: map['nativePageCount'] as int? ?? 0,
    );
  }
}

class VaultUnit {
  final String id;
  final String name;
  final String subjectName;
  final List<VaultDocument> documents;

  VaultUnit({
    required this.id,
    required this.name,
    required this.subjectName,
    List<VaultDocument>? documents,
  }) : documents = documents ?? [];

  int get totalChunks => documents.fold(0, (sum, doc) => sum + doc.chunkCount);
}

class VaultSubject {
  final String name;
  final String iconCode;
  final List<VaultUnit> units;

  VaultSubject({
    required this.name,
    required this.iconCode,
    List<VaultUnit>? units,
  }) : units = units ?? [];

  int get totalDocuments =>
      units.fold(0, (sum, unit) => sum + unit.documents.length);
  int get totalChunks => units.fold(0, (sum, unit) => sum + unit.totalChunks);
}
