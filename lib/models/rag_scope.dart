import 'vault_item.dart';

/// Supported types of academic RAG retrieval scopes.
enum RagScopeType {
  allNotes,
  subject,
  subjectUnit,
  document,
  lecture,
  off,
}

/// Helper for normalizing subject, unit, and document slugs/IDs.
class RagIdHelper {
  static String toSubjectId(String nameOrId) {
    final clean = nameOrId.trim().toLowerCase();
    if (clean == 'os' || clean == 'operating systems') {
      return 'operating_systems';
    }
    if (clean == 'cn' || clean == 'computer networks') {
      return 'computer_networks';
    }
    if (clean == 'ml' || clean == 'machine learning') {
      return 'machine_learning';
    }
    if (clean == 'dbms' ||
        clean == 'database management' ||
        clean == 'database management systems') {
      return 'database_management';
    }
    if (clean == 'dm' ||
        clean == 'discrete math' ||
        clean == 'discrete mathematics' ||
        clean == 'discrete_mathematics') {
      return 'discrete_mathematics';
    }
    if (clean == 'physics' || clean == 'engineering physics') {
      return 'engineering_physics';
    }
    return clean
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }

  static String toUnitId(String nameOrId) {
    final clean = nameOrId.trim().toLowerCase();
    // Match "unit 1", "unit 2", "unit-1", "u1", etc.
    final unitNumMatch =
        RegExp(r'(?:unit|u)\s*[-_:]?\s*(\d+)').firstMatch(clean);
    if (unitNumMatch != null) {
      return 'unit_${unitNumMatch.group(1)}';
    }
    return clean
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }
}

/// Represents an unambiguous academic scope for on-device RAG retrieval.
/// Enforces the strict hierarchy: SUBJECT -> UNIT -> DOCUMENT -> CHUNK.
///
/// Under this model, a Unit is NEVER global. A unit-level scope MUST be a
/// SubjectUnitScope containing both [subjectId] and [unitId].
class RagScope {
  final RagScopeType type;
  final String? subjectId;
  final String? subjectName;
  final String? unitId;
  final String? unitName;
  final String? documentId;
  final String? documentName;
  final String? lectureId;
  final String? lectureTitle;

  const RagScope._({
    required this.type,
    this.subjectId,
    this.subjectName,
    this.unitId,
    this.unitName,
    this.documentId,
    this.documentName,
    this.lectureId,
    this.lectureTitle,
  });

  /// Scope across all indexed study notes and subjects.
  const RagScope.allNotes() : this._(type: RagScopeType.allNotes);

  /// General knowledge scope (no vault retrieval).
  const RagScope.off() : this._(type: RagScopeType.off);

  /// Scope restricted to an entire academic subject (all units eligible).
  factory RagScope.subject({
    required String subjectName,
    String? subjectId,
  }) {
    final id = subjectId ?? RagIdHelper.toSubjectId(subjectName);
    return RagScope._(
      type: RagScopeType.subject,
      subjectId: id,
      subjectName: subjectName,
    );
  }

  /// Scope restricted strictly to a specific Subject + Unit pair.
  /// Neither [subjectId] nor [unitId] can be empty.
  factory RagScope.subjectUnit({
    required String subjectName,
    required String unitName,
    String? subjectId,
    String? unitId,
  }) {
    final sId = subjectId ?? RagIdHelper.toSubjectId(subjectName);
    final uId = unitId ?? RagIdHelper.toUnitId(unitName);
    return RagScope._(
      type: RagScopeType.subjectUnit,
      subjectId: sId,
      subjectName: subjectName,
      unitId: uId,
      unitName: unitName,
    );
  }

  /// Scope restricted strictly to a specific document.
  factory RagScope.document({
    required String documentId,
    required String documentName,
    String? subjectId,
    String? subjectName,
    String? unitId,
    String? unitName,
  }) {
    return RagScope._(
      type: RagScopeType.document,
      documentId: documentId,
      documentName: documentName,
      subjectId: subjectId,
      subjectName: subjectName,
      unitId: unitId,
      unitName: unitName,
    );
  }

  /// Scope restricted strictly to a specific lecture transcript.
  factory RagScope.lecture({
    required String lectureId,
    required String lectureTitle,
    String? subjectId,
    String? subjectName,
    String? unitId,
    String? unitName,
  }) {
    return RagScope._(
      type: RagScopeType.lecture,
      lectureId: lectureId,
      lectureTitle: lectureTitle,
      subjectId: subjectId,
      subjectName: subjectName,
      unitId: unitId,
      unitName: unitName,
    );
  }

  /// Evaluates whether a candidate [TextChunk] belongs to this academic scope.
  bool matchesChunk(TextChunk chunk) {
    switch (type) {
      case RagScopeType.off:
        return false;

      case RagScopeType.allNotes:
        return true;

      case RagScopeType.subject:
        return _matchesSubject(chunk.subjectId, chunk.subjectName);

      case RagScopeType.subjectUnit:
        // HARD RULE: BOTH subject AND unit must match. Never unit alone!
        return _matchesSubject(chunk.subjectId, chunk.subjectName) &&
            _matchesUnit(chunk.unitId, chunk.unitName);

      case RagScopeType.document:
        if (documentId != null &&
            (chunk.documentId == documentId ||
                chunk.id.startsWith('${documentId}_') ||
                chunk.id == documentId)) {
          return true;
        }
        if (documentName != null &&
            chunk.documentName.toLowerCase() ==
                documentName!.trim().toLowerCase()) {
          return true;
        }
        return false;

      case RagScopeType.lecture:
        if (lectureId != null &&
            (chunk.id.startsWith('${lectureId}_') ||
                chunk.id == lectureId ||
                chunk.documentId == lectureId)) {
          return true;
        }
        if (lectureTitle != null &&
            chunk.documentName
                .toLowerCase()
                .contains(lectureTitle!.toLowerCase())) {
          return true;
        }
        return false;
    }
  }

  bool _matchesSubject(String chunkSubId, String chunkSubName) {
    if (subjectId != null) {
      if (chunkSubId.toLowerCase() == subjectId!.toLowerCase()) {
        return true;
      }
      if (RagIdHelper.toSubjectId(chunkSubId) ==
          RagIdHelper.toSubjectId(subjectId!)) {
        return true;
      }
      if (RagIdHelper.toSubjectId(chunkSubName) ==
          RagIdHelper.toSubjectId(subjectId!)) {
        return true;
      }
    }
    if (subjectName != null &&
        chunkSubName.toLowerCase().trim() ==
            subjectName!.toLowerCase().trim()) {
      return true;
    }
    return false;
  }

  bool _matchesUnit(String chunkUnitId, String chunkUnitName) {
    if (unitId != null) {
      if (chunkUnitId.toLowerCase() == unitId!.toLowerCase()) {
        return true;
      }
      if (RagIdHelper.toUnitId(chunkUnitId) == RagIdHelper.toUnitId(unitId!)) {
        return true;
      }
      if (RagIdHelper.toUnitId(chunkUnitName) ==
          RagIdHelper.toUnitId(unitId!)) {
        return true;
      }
    }
    if (unitName != null &&
        chunkUnitName.toLowerCase().trim() == unitName!.toLowerCase().trim()) {
      return true;
    }
    return false;
  }

  /// Compact, human-readable display label for UI pills and headers.
  String get displayLabel {
    switch (type) {
      case RagScopeType.off:
        return 'General Knowledge (No Vault)';
      case RagScopeType.allNotes:
        return 'All Notes';
      case RagScopeType.subject:
        return subjectName ?? 'Subject';
      case RagScopeType.subjectUnit:
        return '${_formatSubjectName(subjectName)} · ${unitName ?? "Unit"}';
      case RagScopeType.document:
        return documentName ?? 'Document';
      case RagScopeType.lecture:
        return lectureTitle ?? 'Lecture';
    }
  }

  static String _formatSubjectName(String? name) {
    if (name == null || name.isEmpty) return 'Subject';
    return name;
  }

  Map<String, dynamic> toMap() {
    return {
      'type': type.name,
      if (subjectId != null) 'subjectId': subjectId,
      if (subjectName != null) 'subjectName': subjectName,
      if (unitId != null) 'unitId': unitId,
      if (unitName != null) 'unitName': unitName,
      if (documentId != null) 'documentId': documentId,
      if (documentName != null) 'documentName': documentName,
      if (lectureId != null) 'lectureId': lectureId,
      if (lectureTitle != null) 'lectureTitle': lectureTitle,
    };
  }

  factory RagScope.fromMap(Map<String, dynamic> map) {
    final typeStr = map['type'] as String? ?? 'allNotes';
    final type = RagScopeType.values.firstWhere(
      (e) => e.name == typeStr,
      orElse: () => RagScopeType.allNotes,
    );

    return RagScope._(
      type: type,
      subjectId: map['subjectId'] as String?,
      subjectName: map['subjectName'] as String?,
      unitId: map['unitId'] as String?,
      unitName: map['unitName'] as String?,
      documentId: map['documentId'] as String?,
      documentName: map['documentName'] as String?,
      lectureId: map['lectureId'] as String?,
      lectureTitle: map['lectureTitle'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RagScope &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          subjectId == other.subjectId &&
          unitId == other.unitId &&
          documentId == other.documentId &&
          lectureId == other.lectureId;

  @override
  int get hashCode =>
      type.hashCode ^
      (subjectId?.hashCode ?? 0) ^
      (unitId?.hashCode ?? 0) ^
      (documentId?.hashCode ?? 0) ^
      (lectureId?.hashCode ?? 0);

  @override
  String toString() => 'RagScope($displayLabel, type: ${type.name})';
}
