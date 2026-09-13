import 'extracted_page_content.dart';

String _slugify(String value) {
  final clean = value.trim().toLowerCase();
  if (clean == 'os' || clean == 'operating systems') return 'operating_systems';
  if (clean == 'cn' || clean == 'computer networks') return 'computer_networks';
  if (clean == 'ml' || clean == 'machine learning') return 'machine_learning';
  final unitMatch = RegExp(r'(?:unit|u)\s*[-_:]?\s*(\d+)').firstMatch(clean);
  if (unitMatch != null) return 'unit_${unitMatch.group(1)}';
  return clean
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
}

class TextChunk {
  final String id;
  final String subjectId;
  final String subjectName;
  final String unitId;
  final String unitName;
  final String documentId;
  final String documentName;
  final int pageNumber;
  final String text;
  final int wordCount;
  final ExtractionType extractionType;
  final double confidence;
  final String? timestamp; // e.g. "03:42" for audio chunks
  final String?
      sourceType; // 'lectureTranscript', 'scheduledLecture', 'document', 'pdf', 'ocr'

  TextChunk({
    required this.id,
    String? subjectId,
    String? subjectName,
    String? subject,
    String? unitId,
    String? unitName,
    String? unit,
    String? documentId,
    required this.documentName,
    required this.pageNumber,
    required this.text,
    required this.wordCount,
    this.extractionType = ExtractionType.nativePdf,
    this.confidence = 1.0,
    this.timestamp,
    this.sourceType,
  })  : subjectName = subjectName ?? subject ?? 'subjectUnknown',
        subjectId = subjectId ??
            (subjectName != null
                ? _slugify(subjectName)
                : (subject != null ? _slugify(subject) : 'subject_unknown')),
        unitName = unitName ?? unit ?? 'unitUnknown',
        unitId = unitId ??
            (unitName != null
                ? _slugify(unitName)
                : (unit != null ? _slugify(unit) : 'unit_unknown')),
        documentId = documentId ??
            (id.contains('_p') ? id.substring(0, id.indexOf('_p')) : id);

  /// Backward-compatible accessors
  String get subject => subjectName;
  String get unit => unitName;

  bool get isOcr => extractionType.isOcr;
  bool get isAudio => extractionType.isAudio || timestamp != null;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'subjectId': subjectId,
      'subjectName': subjectName,
      'subject': subjectName,
      'unitId': unitId,
      'unitName': unitName,
      'unit': unitName,
      'documentId': documentId,
      'documentName': documentName,
      'pageNumber': pageNumber,
      'text': text,
      'wordCount': wordCount,
      'extractionType': extractionType.name,
      'confidence': confidence,
      if (timestamp != null) 'timestamp': timestamp,
      if (sourceType != null) 'sourceType': sourceType,
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

    final subName = (map['subjectName'] as String?) ??
        (map['subject'] as String?) ??
        'subjectUnknown';
    final uName = (map['unitName'] as String?) ??
        (map['unit'] as String?) ??
        'unitUnknown';

    return TextChunk(
      id: map['id'] as String,
      subjectId: map['subjectId'] as String? ?? _slugify(subName),
      subjectName: subName,
      unitId: map['unitId'] as String? ?? _slugify(uName),
      unitName: uName,
      documentId: map['documentId'] as String?,
      documentName: (map['documentName'] as String?) ?? '',
      pageNumber: (map['pageNumber'] as int?) ?? 1,
      text: (map['text'] as String?) ?? '',
      wordCount: (map['wordCount'] as int?) ?? 0,
      extractionType: type,
      confidence: (map['confidence'] as num?)?.toDouble() ?? 1.0,
      timestamp: map['timestamp'] as String?,
      sourceType: map['sourceType'] as String?,
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
  final String subjectId;
  final String subjectName;
  final String unitId;
  final String unitName;
  final int chunkCount;
  final int pageCount;
  final DateTime addedAt;
  final int ocrPageCount;
  final int nativePageCount;
  final String? sourceType;
  final int? durationSeconds;
  final String? audioPath;

  VaultDocument({
    required this.id,
    required this.name,
    required this.path,
    String? subjectId,
    String? subjectName,
    String? subject,
    String? unitId,
    String? unitName,
    String? unit,
    required this.chunkCount,
    required this.pageCount,
    required this.addedAt,
    this.ocrPageCount = 0,
    this.nativePageCount = 0,
    this.sourceType = 'document',
    this.durationSeconds,
    this.audioPath,
  })  : subjectName = subjectName ?? subject ?? 'subjectUnknown',
        subjectId = subjectId ??
            (subjectName != null
                ? _slugify(subjectName)
                : (subject != null ? _slugify(subject) : 'subject_unknown')),
        unitName = unitName ?? unit ?? 'unitUnknown',
        unitId = unitId ??
            (unitName != null
                ? _slugify(unitName)
                : (unit != null ? _slugify(unit) : 'unit_unknown'));

  /// Backward-compatible getters
  String get subject => subjectName;
  String get unit => unitName;

  bool get hasOcr => ocrPageCount > 0;
  bool get isAudio =>
      sourceType == 'lectureTranscript' ||
      sourceType == 'scheduledLecture' ||
      sourceType == 'liveCapture' ||
      sourceType == 'lecture' ||
      durationSeconds != null;

  bool get isHandwritten =>
      sourceType == 'handwritten' || name.toLowerCase().contains('handwritten');

  bool get isUnorganized =>
      subjectId == 'unassigned' ||
      subjectId == 'subject_unknown' ||
      unitId == 'unassigned' ||
      unitId == 'unit_unknown' ||
      subjectName.toLowerCase() == 'unorganized';

  String get formattedDuration {
    if (durationSeconds == null || durationSeconds == 0) return '';
    final mins = (durationSeconds! / 60).round();
    if (mins < 1) return '< 1 min';
    if (mins >= 60) {
      final hrs = mins ~/ 60;
      final rem = mins % 60;
      return rem > 0 ? '${hrs}h ${rem}m' : '${hrs}h';
    }
    return '$mins min';
  }

  String get typeLabel {
    if (isAudio) return 'Lecture';
    if (isHandwritten) return 'Handwritten';
    if (hasOcr || sourceType == 'ocr') return 'OCR Notes';
    return 'PDF';
  }

  VaultDocument copyWith({
    String? id,
    String? name,
    String? path,
    String? subjectId,
    String? subjectName,
    String? unitId,
    String? unitName,
    int? chunkCount,
    int? pageCount,
    DateTime? addedAt,
    int? ocrPageCount,
    int? nativePageCount,
    String? sourceType,
    int? durationSeconds,
    String? audioPath,
  }) {
    return VaultDocument(
      id: id ?? this.id,
      name: name ?? this.name,
      path: path ?? this.path,
      subjectId: subjectId ?? this.subjectId,
      subjectName: subjectName ?? this.subjectName,
      unitId: unitId ?? this.unitId,
      unitName: unitName ?? this.unitName,
      chunkCount: chunkCount ?? this.chunkCount,
      pageCount: pageCount ?? this.pageCount,
      addedAt: addedAt ?? this.addedAt,
      ocrPageCount: ocrPageCount ?? this.ocrPageCount,
      nativePageCount: nativePageCount ?? this.nativePageCount,
      sourceType: sourceType ?? this.sourceType,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      audioPath: audioPath ?? this.audioPath,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'path': path,
      'subjectId': subjectId,
      'subjectName': subjectName,
      'subject': subjectName,
      'unitId': unitId,
      'unitName': unitName,
      'unit': unitName,
      'chunkCount': chunkCount,
      'pageCount': pageCount,
      'addedAt': addedAt.toIso8601String(),
      'ocrPageCount': ocrPageCount,
      'nativePageCount': nativePageCount,
      if (sourceType != null) 'sourceType': sourceType,
      if (durationSeconds != null) 'durationSeconds': durationSeconds,
      if (audioPath != null) 'audioPath': audioPath,
    };
  }

  factory VaultDocument.fromMap(Map<String, dynamic> map) {
    final sName = (map['subjectName'] as String?) ??
        (map['subject'] as String?) ??
        'subjectUnknown';
    final uName = (map['unitName'] as String?) ??
        (map['unit'] as String?) ??
        'unitUnknown';

    return VaultDocument(
      id: map['id'] as String,
      name: map['name'] as String,
      path: (map['path'] as String?) ?? '',
      subjectId: map['subjectId'] as String? ?? _slugify(sName),
      subjectName: sName,
      unitId: map['unitId'] as String? ?? _slugify(uName),
      unitName: uName,
      chunkCount: (map['chunkCount'] as int?) ?? 1,
      pageCount: (map['pageCount'] as int?) ?? 1,
      addedAt: map['addedAt'] != null
          ? DateTime.parse(map['addedAt'] as String)
          : DateTime.now(),
      ocrPageCount: (map['ocrPageCount'] as int?) ?? 0,
      nativePageCount: (map['nativePageCount'] as int?) ?? 0,
      sourceType: map['sourceType'] as String?,
      durationSeconds: map['durationSeconds'] as int?,
      audioPath: map['audioPath'] as String?,
    );
  }
}

typedef KnowledgeSource = VaultDocument;

class VaultUnit {
  final String id;
  final String name;
  final String subjectId;
  final String subjectName;
  final List<VaultDocument> documents;

  VaultUnit({
    required this.id,
    required this.name,
    String? subjectId,
    required this.subjectName,
    List<VaultDocument>? documents,
  })  : subjectId = subjectId ?? _slugify(subjectName),
        documents = documents ?? [];

  int get totalSources => documents.length;
  int get totalChunks => documents.fold(0, (sum, doc) => sum + doc.chunkCount);

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'subjectId': subjectId,
      'subjectName': subjectName,
      'documents': documents.map((d) => d.toMap()).toList(),
    };
  }

  factory VaultUnit.fromMap(Map<String, dynamic> map) {
    return VaultUnit(
      id: map['id'] as String,
      name: map['name'] as String,
      subjectId: map['subjectId'] as String?,
      subjectName: (map['subjectName'] as String?) ?? 'subjectUnknown',
      documents: (map['documents'] as List<dynamic>?)
          ?.map((d) => VaultDocument.fromMap(d as Map<String, dynamic>))
          .toList(),
    );
  }
}

class VaultSubject {
  final String id;
  final String name;
  final String iconCode;
  final String? code;
  final String? colorHex;
  final List<VaultUnit> units;

  VaultSubject({
    String? id,
    required this.name,
    required this.iconCode,
    this.code,
    this.colorHex,
    List<VaultUnit>? units,
  })  : id = id ?? _slugify(name),
        units = units ?? [];

  int get totalUnits => units.length;
  int get totalSources => units.fold(0, (sum, unit) => sum + unit.totalSources);
  int get totalDocuments => totalSources;
  int get totalChunks => units.fold(0, (sum, unit) => sum + unit.totalChunks);

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'iconCode': iconCode,
      if (code != null) 'code': code,
      if (colorHex != null) 'colorHex': colorHex,
      'units': units.map((u) => u.toMap()).toList(),
    };
  }

  factory VaultSubject.fromMap(Map<String, dynamic> map) {
    return VaultSubject(
      id: map['id'] as String?,
      name: map['name'] as String,
      iconCode: (map['iconCode'] as String?) ?? 'school',
      code: map['code'] as String?,
      colorHex: map['colorHex'] as String?,
      units: (map['units'] as List<dynamic>?)
          ?.map((u) => VaultUnit.fromMap(u as Map<String, dynamic>))
          .toList(),
    );
  }
}
