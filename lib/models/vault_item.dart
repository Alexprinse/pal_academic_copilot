class TextChunk {
  final String id;
  final String subject;
  final String unit;
  final String documentName;
  final int pageNumber;
  final String text;
  final int wordCount;

  TextChunk({
    required this.id,
    required this.subject,
    required this.unit,
    required this.documentName,
    required this.pageNumber,
    required this.text,
    required this.wordCount,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'subject': subject,
      'unit': unit,
      'documentName': documentName,
      'pageNumber': pageNumber,
      'text': text,
      'wordCount': wordCount,
    };
  }

  factory TextChunk.fromMap(Map<String, dynamic> map) {
    return TextChunk(
      id: map['id'] as String,
      subject: map['subject'] as String,
      unit: map['unit'] as String,
      documentName: map['documentName'] as String,
      pageNumber: map['pageNumber'] as int,
      text: map['text'] as String,
      wordCount: map['wordCount'] as int,
    );
  }
}

class ChunkMatch {
  final TextChunk chunk;
  final double score;

  ChunkMatch({required this.chunk, required this.score});
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

  VaultDocument({
    required this.id,
    required this.name,
    required this.path,
    required this.subject,
    required this.unit,
    required this.chunkCount,
    required this.pageCount,
    required this.addedAt,
  });

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
