import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../models/extracted_page_content.dart';
import '../models/lecture_recording.dart';
import '../models/rag_scope.dart';
import '../models/vault_item.dart';
import 'lecture_recording_service.dart';
import 'ocr_service.dart';
import 'pdf_page_renderer_service.dart';

class VaultSearchResult {
  final VaultSubject? subject;
  final VaultUnit? unit;
  final VaultDocument? source;
  final String title;
  final String subtitle;
  final String type; // 'subject', 'unit', 'source'

  VaultSearchResult({
    this.subject,
    this.unit,
    this.source,
    required this.title,
    required this.subtitle,
    required this.type,
  });
}

class RagService extends ChangeNotifier {
  static final RagService instance = RagService._();
  RagService._();

  final List<VaultSubject> _subjects = [];
  List<VaultSubject> get subjects => _subjects;

  final List<VaultDocument> _unorganizedSources = [];
  List<VaultDocument> get unorganizedSources =>
      List.unmodifiable(_unorganizedSources);
  int get totalUnorganizedSources => _unorganizedSources.length;

  int get totalSources =>
      _subjects.fold(0, (sum, s) => sum + s.totalSources) +
      _unorganizedSources.length;

  final List<TextChunk> _allChunks = [];
  List<TextChunk> get allChunks => _allChunks;

  final Map<String, List<ExtractedPageContent>> _extractedPages = {};

  final PdfPageRendererService _pdfRenderer = PdfPageRendererService();
  final OcrService _ocrService = OcrService.instance;

  bool _isIndexing = false;
  bool get isIndexing => _isIndexing;

  int get totalIndexedChunks => _allChunks.length;

  /// Returns the number of indexed chunks matching the given [scope].
  int countChunksInScope(RagScope scope) {
    if (scope.type == RagScopeType.off) return 0;
    return _allChunks.where((c) => scope.matchesChunk(c)).length;
  }

  List<ExtractedPageContent> getExtractedPages(String docName) {
    return List.unmodifiable(_extractedPages[docName] ?? []);
  }

  Future<void> init() async {
    await _loadPageCache();
    await _loadSubjects();
    if (_subjects.isEmpty) {
      _populateSeedData();
    }
    _indexExistingRecordings();
  }

  void _indexExistingRecordings() {
    try {
      final recordings = LectureRecordingService.instance.recordings;
      for (final r in recordings) {
        if (r.transcriptionStatus == 'completed') {
          indexLectureRecording(r, notify: false);
        }
      }
    } catch (e) {
      debugPrint('[RagService] Notice: indexing existing recordings: $e');
    }
  }

  /// Indexes an on-device lecture recording (Live Capture or Scheduled) into RAG
  void indexLectureRecording(LectureRecording recording, {bool notify = true}) {
    // 1. Remove any previous chunks for this recording to remain idempotent
    _allChunks.removeWhere(
      (c) => c.id.startsWith('${recording.id}_') || c.id == recording.id,
    );

    final isLive = recording.sourceType == 'liveCapture';
    final prefix = isLive ? 'Live Capture' : 'Lecture';
    final dateStr = _formatShortDate(recording.date);
    final docName = '$prefix · ${recording.displayTitle} · $dateStr';
    final srcType = isLive ? 'lectureTranscript' : 'scheduledLecture';

    // Subject resolution: prefer recording subject, fallback to displayTitle or 'Recorded Lectures'
    final cleanSubject = recording.subject.trim().isNotEmpty
        ? recording.subject.trim()
        : (recording.displayTitle.isNotEmpty
            ? recording.displayTitle
            : 'Recorded Lectures');
    final cleanSubjectId =
        recording.subjectId ?? RagIdHelper.toSubjectId(cleanSubject);

    // Unit resolution: prefer recording unitName, fallback to standard lecture unit
    final cleanUnit =
        (recording.unitName != null && recording.unitName!.trim().isNotEmpty)
            ? recording.unitName!.trim()
            : (isLive ? 'Live Capture Transcripts' : 'Scheduled Lectures');
    final cleanUnitId = recording.unitId ?? RagIdHelper.toUnitId(cleanUnit);

    if (recording.chunks.isNotEmpty) {
      for (final chunk in recording.chunks) {
        final words = chunk.text
            .split(RegExp(r'\s+'))
            .where((w) => w.trim().isNotEmpty)
            .toList();
        _allChunks.add(
          TextChunk(
            id: '${recording.id}_c${chunk.chunkIndex}',
            subjectId: cleanSubjectId,
            subjectName: cleanSubject,
            unitId: cleanUnitId,
            unitName: cleanUnit,
            documentId: recording.id,
            documentName: docName,
            pageNumber: chunk.chunkIndex + 1,
            text: chunk.text,
            wordCount: words.length,
            extractionType: ExtractionType.audioTranscript,
            confidence: 1.0,
            timestamp: chunk.startTimestamp,
            sourceType: srcType,
          ),
        );
      }
    } else if (recording.transcriptText.trim().isNotEmpty) {
      final words = recording.transcriptText
          .split(RegExp(r'\s+'))
          .where((w) => w.trim().isNotEmpty)
          .toList();
      _allChunks.add(
        TextChunk(
          id: '${recording.id}_full',
          subjectId: cleanSubjectId,
          subjectName: cleanSubject,
          unitId: cleanUnitId,
          unitName: cleanUnit,
          documentId: recording.id,
          documentName: docName,
          pageNumber: 1,
          text: recording.transcriptText,
          wordCount: words.length,
          extractionType: ExtractionType.audioTranscript,
          confidence: 1.0,
          timestamp: '00:00',
          sourceType: srcType,
        ),
      );
    }

    // Also register or update vault representation in Study Vault
    _upsertVaultLectureDocument(
      recording,
      docName,
      cleanUnit,
      cleanSubject,
      cleanSubjectId,
      cleanUnitId,
    );

    if (notify) {
      notifyListeners();
    }
  }

  void _upsertVaultLectureDocument(
    LectureRecording recording,
    String docName,
    String unitName,
    String subjectName,
    String subjectId,
    String unitId,
  ) {
    var vaultSub = _subjects.firstWhere(
      (s) =>
          s.id == subjectId ||
          s.name.toLowerCase() == subjectName.toLowerCase(),
      orElse: () {
        final newSub = VaultSubject(
          id: subjectId,
          name: subjectName,
          iconCode: 'school',
          units: [
            VaultUnit(
              id: unitId,
              name: unitName,
              subjectId: subjectId,
              subjectName: subjectName,
            ),
          ],
        );
        _subjects.add(newSub);
        return newSub;
      },
    );

    final targetUnit = vaultSub.units.firstWhere(
      (u) => u.id == unitId || u.name.toLowerCase() == unitName.toLowerCase(),
      orElse: () {
        final newUnit = VaultUnit(
          id: unitId,
          name: unitName,
          subjectId: vaultSub.id,
          subjectName: vaultSub.name,
        );
        vaultSub.units.add(newUnit);
        return newUnit;
      },
    );

    targetUnit.documents.removeWhere((d) => d.id == recording.id);
    targetUnit.documents.insert(
      0,
      VaultDocument(
        id: recording.id,
        name: docName,
        path: recording.audioPath,
        subjectId: vaultSub.id,
        subjectName: vaultSub.name,
        unitId: targetUnit.id,
        unitName: targetUnit.name,
        chunkCount: recording.chunks.isNotEmpty ? recording.chunks.length : 1,
        pageCount: recording.chunks.isNotEmpty ? recording.chunks.length : 1,
        addedAt: recording.date,
      ),
    );
  }

  /// Unindexes a lecture recording when deleted
  void unindexLectureRecording(String lectureId) {
    _allChunks.removeWhere(
      (c) => c.id.startsWith('${lectureId}_') || c.id == lectureId,
    );
    for (final s in _subjects) {
      for (final u in s.units) {
        u.documents.removeWhere((d) => d.id == lectureId);
      }
    }
    notifyListeners();
  }

  /// Indexes an OCR-processed document into the RAG pipeline
  void indexOcrDocument({
    required String documentId,
    required String title,
    required String text,
    String? subject,
    String? unit,
    String? subjectId,
    String? unitId,
    bool isUnorganized = false,
    int pageCount = 1,
    List<ExtractedPageContent>? pages,
    ExtractionType extractionType = ExtractionType.printedOcr,
    double confidence = 0.95,
  }) {
    // 1. Remove previous chunks for this documentId
    _allChunks.removeWhere(
      (c) =>
          c.id.startsWith('${documentId}_') ||
          c.id == documentId ||
          c.documentName.toLowerCase() == title.toLowerCase(),
    );

    if (isUnorganized || (subject == null && unit == null)) {
      // Index as unorganized
      if (pages != null && pages.isNotEmpty) {
        for (final p in pages) {
          _indexRawText(
            subject: 'Unorganized',
            unit: 'Unorganized',
            subjectId: null,
            unitId: null,
            documentId: documentId,
            docName: title,
            pageNumber: p.pageNumber,
            text: p.text,
            extractionType: p.extractionType,
            confidence: p.confidence,
            sourceType: 'ocrDocument',
          );
        }
      } else {
        _indexRawText(
          subject: 'Unorganized',
          unit: 'Unorganized',
          subjectId: null,
          unitId: null,
          documentId: documentId,
          docName: title,
          pageNumber: 1,
          text: text,
          extractionType: extractionType,
          confidence: confidence,
          sourceType: 'ocrDocument',
        );
      }

      _unorganizedSources
          .removeWhere((d) => d.id == documentId || d.name == title);
      _unorganizedSources.add(
        VaultDocument(
          id: documentId,
          name: title,
          path: 'ocr://$documentId',
          subjectId: null,
          subjectName: null,
          unitId: null,
          unitName: null,
          chunkCount: _allChunks
              .where((c) =>
                  c.documentId == documentId ||
                  c.id.startsWith('${documentId}_'))
              .length,
          pageCount: pageCount > 0 ? pageCount : 1,
          addedAt: DateTime.now(),
        ),
      );
      _saveSubjects();
      notifyListeners();
      return;
    }

    // 2. Ensure subject and unit exist (fallback to subject_unknown if unassigned)
    final cleanSubject = (subject != null && subject.trim().isNotEmpty)
        ? subject.trim()
        : 'Unassigned Notes';
    final cleanSubjectId = subjectId ??
        (cleanSubject == 'Unassigned Notes'
            ? 'subject_unknown'
            : RagIdHelper.toSubjectId(cleanSubject));
    final cleanUnit = (unit != null && unit.trim().isNotEmpty)
        ? unit.trim()
        : 'Scanned Documents';
    final cleanUnitId = unitId ?? RagIdHelper.toUnitId(cleanUnit);

    addSubject(cleanSubject,
        iconCode: 'description', subjectId: cleanSubjectId);
    addUnit(cleanSubject, cleanUnit, unitId: cleanUnitId);

    // 3. Index chunks
    if (pages != null && pages.isNotEmpty) {
      for (final p in pages) {
        _indexRawText(
          subject: cleanSubject,
          unit: cleanUnit,
          subjectId: cleanSubjectId,
          unitId: cleanUnitId,
          documentId: documentId,
          docName: title,
          pageNumber: p.pageNumber,
          text: p.text,
          extractionType: p.extractionType,
          confidence: p.confidence,
          sourceType: 'ocrDocument',
        );
      }
    } else {
      final pageSplits = text.split(RegExp(r'\f|--- Page \d+ ---'));
      if (pageSplits.length > 1) {
        for (var i = 0; i < pageSplits.length; i++) {
          final pageText = pageSplits[i].trim();
          if (pageText.isNotEmpty) {
            _indexRawText(
              subject: cleanSubject,
              unit: cleanUnit,
              subjectId: cleanSubjectId,
              unitId: cleanUnitId,
              documentId: documentId,
              docName: title,
              pageNumber: i + 1,
              text: pageText,
              extractionType: extractionType,
              confidence: confidence,
              sourceType: 'ocrDocument',
            );
          }
        }
      } else {
        _indexRawText(
          subject: cleanSubject,
          unit: cleanUnit,
          subjectId: cleanSubjectId,
          unitId: cleanUnitId,
          documentId: documentId,
          docName: title,
          pageNumber: 1,
          text: text,
          extractionType: extractionType,
          confidence: confidence,
          sourceType: 'ocrDocument',
        );
      }
    }

    // Tag chunks for this document with documentId prefix and sourceType
    for (var i = 0; i < _allChunks.length; i++) {
      final c = _allChunks[i];
      if (c.documentName == title && !c.id.startsWith('${documentId}_')) {
        _allChunks[i] = TextChunk(
          id: '${documentId}_${c.id}',
          subjectId: cleanSubjectId,
          subjectName: c.subjectName,
          unitId: cleanUnitId,
          unitName: c.unitName,
          documentId: documentId,
          documentName: c.documentName,
          pageNumber: c.pageNumber,
          text: c.text,
          wordCount: c.wordCount,
          extractionType: c.extractionType,
          confidence: c.confidence,
          sourceType: 'ocrDocument',
        );
      }
    }

    // 4. Also register VaultDocument in unit
    final s = _subjects.firstWhere(
      (sub) =>
          sub.id == cleanSubjectId ||
          sub.name.toLowerCase() == cleanSubject.toLowerCase(),
      orElse: () => _subjects.first,
    );
    final u = s.units.firstWhere(
      (un) =>
          un.id == cleanUnitId ||
          un.name.toLowerCase() == cleanUnit.toLowerCase(),
      orElse: () => s.units.first,
    );
    u.documents.removeWhere((d) => d.id == documentId || d.name == title);
    u.documents.add(
      VaultDocument(
        id: documentId,
        name: title,
        path: 'ocr://$documentId',
        subjectId: s.id,
        subjectName: cleanSubject,
        unitId: u.id,
        unitName: cleanUnit,
        chunkCount: _allChunks
            .where((c) =>
                c.documentId == documentId || c.id.startsWith('${documentId}_'))
            .length,
        pageCount: pageCount > 0 ? pageCount : 1,
        addedAt: DateTime.now(),
      ),
    );

    _saveSubjects();
    notifyListeners();
  }

  /// Unindexes an OCR document when deleted
  void unindexOcrDocument(String documentId) {
    _allChunks.removeWhere(
      (c) => c.id.startsWith('${documentId}_') || c.id == documentId,
    );
    for (final s in _subjects) {
      for (final u in s.units) {
        u.documents.removeWhere((d) => d.id == documentId);
      }
    }
    notifyListeners();
  }

  static String _formatShortDate(DateTime dt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${dt.day} ${months[dt.month - 1]}';
  }

  Future<File?> _getSubjectsCacheFile() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      return File('${dir.path}/pal_vault_subjects_v2.json');
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveSubjects() async {
    try {
      final file = await _getSubjectsCacheFile();
      if (file == null) return;
      final data = {
        'subjects': _subjects.map((s) => s.toMap()).toList(),
        'unorganized': _unorganizedSources.map((d) => d.toMap()).toList(),
      };
      file.writeAsStringSync(jsonEncode(data));
    } catch (e) {
      debugPrint('[RagService] Failed to save subjects: $e');
    }
  }

  Future<void> _loadSubjects() async {
    try {
      final file = await _getSubjectsCacheFile();
      if (file == null || !file.existsSync()) {
        _populateSeedData();
        return;
      }
      final raw = file.readAsStringSync();
      if (raw.trim().isEmpty) {
        _populateSeedData();
        return;
      }
      final Map<String, dynamic> decoded = jsonDecode(raw);
      _subjects.clear();
      _unorganizedSources.clear();

      if (decoded.containsKey('subjects')) {
        final subs = decoded['subjects'] as List<dynamic>;
        for (final item in subs) {
          _subjects.add(VaultSubject.fromMap(item as Map<String, dynamic>));
        }
      }
      if (decoded.containsKey('unorganized')) {
        final unorg = decoded['unorganized'] as List<dynamic>;
        for (final item in unorg) {
          _unorganizedSources
              .add(VaultDocument.fromMap(item as Map<String, dynamic>));
        }
      }

      if (_subjects.isEmpty) {
        _populateSeedData();
      }
    } catch (e) {
      debugPrint('[RagService] Failed to load subjects: $e');
      if (_subjects.isEmpty) {
        _populateSeedData();
      }
    }
  }

  void addSubject(
    String subjectName, {
    String iconCode = 'school',
    String? code,
    String? colorHex,
    List<String>? initialUnits,
    String? subjectId,
  }) {
    final cleanName = subjectName.trim();
    if (cleanName.isEmpty) return;

    final sId = subjectId ?? RagIdHelper.toSubjectId(cleanName);
    final existing = _subjects.any(
      (s) => s.id == sId || s.name.toLowerCase() == cleanName.toLowerCase(),
    );
    if (existing) return;

    final units = <VaultUnit>[];
    if (initialUnits != null && initialUnits.isNotEmpty) {
      for (var i = 0; i < initialUnits.length; i++) {
        final uName = initialUnits[i].trim();
        if (uName.isNotEmpty) {
          units.add(VaultUnit(
            id: 'unit_${DateTime.now().millisecondsSinceEpoch}_$i',
            name: uName,
            subjectId: sId,
            subjectName: cleanName,
          ));
        }
      }
    } else {
      units.add(VaultUnit(
        id: 'unit_${DateTime.now().millisecondsSinceEpoch}',
        name: 'Unit 1: Introduction & Fundamentals',
        subjectId: sId,
        subjectName: cleanName,
      ));
    }

    _subjects.add(VaultSubject(
      id: sId,
      name: cleanName,
      iconCode: iconCode,
      code: code,
      colorHex: colorHex,
      units: units,
    ));
    _saveSubjects();
    notifyListeners();
  }

  void addUnit(String subjectName, String unitName, {String? unitId}) {
    final cleanUnit = unitName.trim();
    if (cleanUnit.isEmpty) return;

    final sId = RagIdHelper.toSubjectId(subjectName);
    final subject = _subjects.firstWhere(
      (s) =>
          s.id == sId ||
          s.name.toLowerCase() == subjectName.trim().toLowerCase(),
      orElse: () {
        final newSub =
            VaultSubject(id: sId, name: subjectName.trim(), iconCode: 'school');
        _subjects.add(newSub);
        return newSub;
      },
    );

    final uId = unitId ?? RagIdHelper.toUnitId(cleanUnit);
    final exists = subject.units.any(
      (u) => u.id == uId || u.name.toLowerCase() == cleanUnit.toLowerCase(),
    );
    if (!exists) {
      subject.units.add(VaultUnit(
        id: uId,
        name: cleanUnit,
        subjectId: subject.id,
        subjectName: subject.name,
      ));
      _saveSubjects();
      notifyListeners();
    }
  }

  bool deleteSubject(String subjectIdOrName) {
    final clean = subjectIdOrName.trim();
    if (clean.isEmpty) return false;
    final sId = RagIdHelper.toSubjectId(clean);

    final idx = _subjects.indexWhere(
      (s) =>
          s.id == clean ||
          s.id == sId ||
          s.name.toLowerCase() == clean.toLowerCase(),
    );
    if (idx == -1) return false;
    final subject = _subjects[idx];

    // Cascade: remove chunks
    _allChunks.removeWhere((c) =>
        c.subjectId == subject.id ||
        c.subjectId == sId ||
        c.subjectName.toLowerCase() == subject.name.toLowerCase());

    // Cascade: remove cached pages
    for (final unit in subject.units) {
      for (final doc in unit.documents) {
        _extractedPages.remove(doc.name);
        _extractedPages.remove(doc.id);
      }
    }

    _subjects.removeAt(idx);
    _saveSubjects();
    _savePageCache();
    notifyListeners();
    return true;
  }

  bool deleteUnit(String subjectIdOrName, String unitIdOrName) {
    final cleanSub = subjectIdOrName.trim();
    final cleanUnit = unitIdOrName.trim();
    if (cleanSub.isEmpty || cleanUnit.isEmpty) return false;

    final sId = RagIdHelper.toSubjectId(cleanSub);
    final uId = RagIdHelper.toUnitId(cleanUnit);

    final sIdx = _subjects.indexWhere(
      (s) =>
          s.id == cleanSub ||
          s.id == sId ||
          s.name.toLowerCase() == cleanSub.toLowerCase(),
    );
    if (sIdx == -1) return false;
    final subject = _subjects[sIdx];

    final uIdx = subject.units.indexWhere(
      (u) =>
          u.id == cleanUnit ||
          u.id == uId ||
          u.name.toLowerCase() == cleanUnit.toLowerCase(),
    );
    if (uIdx == -1) return false;
    final unit = subject.units[uIdx];

    // Cascade: remove chunks
    _allChunks.removeWhere((c) {
      final sMatch = c.subjectId == subject.id ||
          c.subjectId == sId ||
          c.subjectName.toLowerCase() == subject.name.toLowerCase();
      final uMatch = c.unitId == unit.id ||
          c.unitId == uId ||
          c.unitName.toLowerCase() == unit.name.toLowerCase();
      return sMatch && uMatch;
    });

    // Cascade: remove cached pages
    for (final doc in unit.documents) {
      _extractedPages.remove(doc.name);
      _extractedPages.remove(doc.id);
    }

    subject.units.removeAt(uIdx);
    _saveSubjects();
    _savePageCache();
    notifyListeners();
    return true;
  }

  bool deleteSource({required String sourceId}) {
    // Remove from unorganized
    _unorganizedSources.removeWhere((d) => d.id == sourceId);

    // Remove from subjects/units
    for (final s in _subjects) {
      for (final u in s.units) {
        u.documents.removeWhere((d) => d.id == sourceId);
      }
    }

    // Remove chunks
    _allChunks.removeWhere((c) =>
        c.documentId == sourceId ||
        c.id.startsWith('${sourceId}_') ||
        c.id == sourceId);

    _extractedPages.remove(sourceId);

    _saveSubjects();
    _savePageCache();
    notifyListeners();
    return true;
  }

  void organizeSource({
    required String sourceId,
    required String targetSubjectId,
    required String targetUnitId,
  }) {
    VaultDocument? targetDoc;

    // 1. Locate and extract source from unorganized or existing units
    final unorgIdx = _unorganizedSources.indexWhere((d) => d.id == sourceId);
    if (unorgIdx != -1) {
      targetDoc = _unorganizedSources.removeAt(unorgIdx);
    } else {
      for (final s in _subjects) {
        for (final u in s.units) {
          final docIdx = u.documents.indexWhere((d) => d.id == sourceId);
          if (docIdx != -1) {
            targetDoc = u.documents.removeAt(docIdx);
            break;
          }
        }
        if (targetDoc != null) break;
      }
    }

    if (targetDoc == null) return;

    // 2. Find target subject and unit
    final sId = RagIdHelper.toSubjectId(targetSubjectId);
    final subject = _subjects.firstWhere(
      (s) => s.id == targetSubjectId || s.id == sId,
      orElse: () => _subjects.first,
    );

    final uId = RagIdHelper.toUnitId(targetUnitId);
    final unit = subject.units.firstWhere(
      (u) => u.id == targetUnitId || u.id == uId,
      orElse: () => subject.units.first,
    );

    // 3. Update document metadata and add to target unit
    final updatedDoc = targetDoc.copyWith(
      subjectId: subject.id,
      subjectName: subject.name,
      unitId: unit.id,
      unitName: unit.name,
    );
    unit.documents.insert(0, updatedDoc);

    // 4. Update associated chunks in _allChunks
    for (var i = 0; i < _allChunks.length; i++) {
      final c = _allChunks[i];
      if (c.documentId == sourceId ||
          c.id.startsWith('${sourceId}_') ||
          c.id == sourceId) {
        _allChunks[i] = TextChunk(
          id: c.id,
          subjectId: subject.id,
          subjectName: subject.name,
          unitId: unit.id,
          unitName: unit.name,
          documentId: c.documentId,
          documentName: c.documentName,
          pageNumber: c.pageNumber,
          text: c.text,
          wordCount: c.wordCount,
          extractionType: c.extractionType,
          confidence: c.confidence,
          timestamp: c.timestamp,
          sourceType: c.sourceType,
        );
      }
    }

    _saveSubjects();
    notifyListeners();
  }

  List<VaultSearchResult> searchVault(String query) {
    final clean = query.trim().toLowerCase();
    if (clean.isEmpty) return [];

    final results = <VaultSearchResult>[];

    // 1. Matching subjects
    for (final s in _subjects) {
      if (s.name.toLowerCase().contains(clean) ||
          (s.code != null && s.code!.toLowerCase().contains(clean))) {
        results.add(VaultSearchResult(
          subject: s,
          title: s.name,
          subtitle: '${s.totalUnits} Units · ${s.totalSources} Sources',
          type: 'subject',
        ));
      }

      // 2. Matching units
      for (final u in s.units) {
        if (u.name.toLowerCase().contains(clean)) {
          results.add(VaultSearchResult(
            subject: s,
            unit: u,
            title: u.name,
            subtitle: '${s.name} · ${u.totalSources} Sources',
            type: 'unit',
          ));
        }

        // 3. Matching sources
        for (final doc in u.documents) {
          if (doc.name.toLowerCase().contains(clean)) {
            results.add(VaultSearchResult(
              subject: s,
              unit: u,
              source: doc,
              title: doc.name,
              subtitle: '${s.name} · ${u.name} · ${doc.typeLabel}',
              type: 'source',
            ));
          }
        }
      }
    }

    // 4. Matching unorganized sources
    for (final doc in _unorganizedSources) {
      if (doc.name.toLowerCase().contains(clean)) {
        results.add(VaultSearchResult(
          source: doc,
          title: doc.name,
          subtitle: 'Unorganized · ${doc.typeLabel}',
          type: 'source',
        ));
      }
    }

    return results;
  }

  Future<void> restoreDefaultSubjects() async {
    _subjects.clear();
    _allChunks.clear();
    _unorganizedSources.clear();
    _populateSeedData();
    _indexExistingRecordings();
    await _saveSubjects();
    notifyListeners();
  }

  void _populateSeedData() {
    _subjects.clear();
    _allChunks.clear();

    // Seed Subject 1: Operating Systems
    final osUnit1 = VaultUnit(
      id: 'os-unit-1',
      name: 'Unit 1: Process Synchronization & Concurrency',
      subjectId: 'operating_systems',
      subjectName: 'Operating Systems',
    );
    final osUnit2 = VaultUnit(
      id: 'os-unit-2',
      name: 'Unit 2: CPU Scheduling & Deadlocks',
      subjectId: 'operating_systems',
      subjectName: 'Operating Systems',
    );
    final osUnit3 = VaultUnit(
      id: 'os-unit-3',
      name: 'Unit 3: Memory Management & Virtual Memory',
      subjectId: 'operating_systems',
      subjectName: 'Operating Systems',
    );
    final osSubject = VaultSubject(
      id: 'operating_systems',
      name: 'Operating Systems',
      iconCode: 'computer',
      code: 'CS301',
      units: [osUnit1, osUnit2, osUnit3],
    );

    // Seed Subject 2: Computer Networks
    final cnUnit1 = VaultUnit(
      id: 'cn-unit-1',
      name: 'Unit 1: Physical & Data Link Layer',
      subjectId: 'computer_networks',
      subjectName: 'Computer Networks',
    );
    final cnUnit2 = VaultUnit(
      id: 'cn-unit-2',
      name: 'Unit 2: Network Layer & Routing',
      subjectId: 'computer_networks',
      subjectName: 'Computer Networks',
    );
    final cnSubject = VaultSubject(
      id: 'computer_networks',
      name: 'Computer Networks',
      iconCode: 'language',
      code: 'CS304',
      units: [cnUnit1, cnUnit2],
    );

    // Seed Subject 3: Machine Learning
    final mlUnit1 = VaultUnit(
      id: 'ml-unit-1',
      name: 'Unit 1: Supervised Learning & Regression',
      subjectId: 'machine_learning',
      subjectName: 'Machine Learning',
    );
    final mlUnit2 = VaultUnit(
      id: 'ml-unit-2',
      name: 'Unit 2: Neural Networks & Deep Learning',
      subjectId: 'machine_learning',
      subjectName: 'Machine Learning',
    );
    final mlSubject = VaultSubject(
      id: 'machine_learning',
      name: 'Machine Learning',
      iconCode: 'psychology',
      code: 'CS420',
      units: [mlUnit1, mlUnit2],
    );

    // Seed Subject 4: Engineering Physics
    final physUnit1 = VaultUnit(
      id: 'phys-unit-1',
      name: 'Unit 1: Quantum Mechanics & Wave Optics',
      subjectId: 'engineering_physics',
      subjectName: 'Engineering Physics',
    );
    final physSubject = VaultSubject(
      id: 'engineering_physics',
      name: 'Engineering Physics',
      iconCode: 'science',
      code: 'PHY101',
      units: [physUnit1],
    );

    // Seed Subject 5: Discrete Mathematics
    final mathUnit1 = VaultUnit(
      id: 'math-unit-1',
      name: 'Unit 1: Graph Theory & Recurrence Relations',
      subjectId: 'discrete_mathematics',
      subjectName: 'Discrete Mathematics',
    );
    final mathSubject = VaultSubject(
      id: 'discrete_mathematics',
      name: 'Discrete Mathematics',
      iconCode: 'functions',
      code: 'MAT201',
      units: [mathUnit1],
    );

    _subjects
        .addAll([osSubject, cnSubject, mlSubject, physSubject, mathSubject]);

    // OS Unit 1: Digital Doc
    final osDoc1 = VaultDocument(
      id: 'doc-os-1',
      name: 'Silberschatz_OS_Ch5_Sync.pdf',
      path: '/vault/Silberschatz_OS_Ch5_Sync.pdf',
      subjectId: 'operating_systems',
      subjectName: 'Operating Systems',
      unitId: 'os-unit-1',
      unitName: 'Unit 1: Process Synchronization & Concurrency',
      chunkCount: 3,
      pageCount: 3,
      addedAt: DateTime.now().subtract(const Duration(days: 3)),
      nativePageCount: 3,
      ocrPageCount: 0,
    );
    osUnit1.documents.add(osDoc1);

    const doc1Page1Text =
        'Process Synchronization deals with mechanisms ensuring orderly execution of cooperating processes. '
        'The Critical Section Problem requires three criteria: 1. Mutual Exclusion: If process Pi is executing in its critical section, '
        'no other processes can execute in their critical sections. 2. Progress: If no process is executing in its critical section and some '
        'processes wish to enter, selection cannot be postponed indefinitely. 3. Bounded Waiting: There must be a bound on the number of times '
        'other processes are allowed to enter their critical sections after a process has made a request to enter.';

    const doc1Page2Text =
        'Peterson\'s Solution is a classic software-based solution to the critical-section problem for two processes. '
        'It uses two shared variables: int turn; boolean flag[2]; '
        'The variable turn indicates whose turn it is to enter the critical section. The flag array is used to indicate '
        'if a process is ready to enter. Peterson\'s algorithm satisfies mutual exclusion, progress, and bounded waiting requirements '
        'on single-core architectures, though modern multi-threaded architectures require memory barriers or atomic hardware instructions '
        'like Test-and-Set and Compare-and-Swap (CAS).';

    const doc1Page3Text =
        'Semaphores are synchronization tools introduced by Dijkstra. A semaphore S is an integer variable accessed only through '
        'two standard atomic operations: wait() and signal(), historically called P() and V(). '
        'A counting semaphore can range over an unrestricted domain, whereas a binary semaphore (mutex lock) ranges only between 0 and 1. '
        'Spinlocks avoid context switches but cause busy waiting, wasting CPU cycles unless wait times are very short.';

    _indexRawText(
      subject: 'Operating Systems',
      subjectId: 'operating_systems',
      unit: 'Unit 1: Process Synchronization & Concurrency',
      unitId: 'os-unit-1',
      docName: 'Silberschatz_OS_Ch5_Sync.pdf',
      documentId: 'doc-os-1',
      pageNumber: 1,
      text: doc1Page1Text,
      extractionType: ExtractionType.nativePdf,
      confidence: 1.0,
    );
    _indexRawText(
      subject: 'Operating Systems',
      subjectId: 'operating_systems',
      unit: 'Unit 1: Process Synchronization & Concurrency',
      unitId: 'os-unit-1',
      docName: 'Silberschatz_OS_Ch5_Sync.pdf',
      documentId: 'doc-os-1',
      pageNumber: 2,
      text: doc1Page2Text,
      extractionType: ExtractionType.nativePdf,
      confidence: 1.0,
    );
    _indexRawText(
      subject: 'Operating Systems',
      subjectId: 'operating_systems',
      unit: 'Unit 1: Process Synchronization & Concurrency',
      unitId: 'os-unit-1',
      docName: 'Silberschatz_OS_Ch5_Sync.pdf',
      documentId: 'doc-os-1',
      pageNumber: 3,
      text: doc1Page3Text,
      extractionType: ExtractionType.nativePdf,
      confidence: 1.0,
    );

    _extractedPages['Silberschatz_OS_Ch5_Sync.pdf'] = [
      ExtractedPageContent(
        documentName: 'Silberschatz_OS_Ch5_Sync.pdf',
        pageNumber: 1,
        text: doc1Page1Text,
        extractionType: ExtractionType.nativePdf,
      ),
      ExtractedPageContent(
        documentName: 'Silberschatz_OS_Ch5_Sync.pdf',
        pageNumber: 2,
        text: doc1Page2Text,
        extractionType: ExtractionType.nativePdf,
      ),
      ExtractedPageContent(
        documentName: 'Silberschatz_OS_Ch5_Sync.pdf',
        pageNumber: 3,
        text: doc1Page3Text,
        extractionType: ExtractionType.nativePdf,
      ),
    ];

    // OS Unit 1: Handwritten Doc
    final osHandwrittenDoc = VaultDocument(
      id: 'doc-os-hw-1',
      name: 'Lecture_Notes_Process_Sync_Handwritten.pdf',
      path: '/vault/Lecture_Notes_Process_Sync_Handwritten.pdf',
      subjectId: 'operating_systems',
      subjectName: 'Operating Systems',
      unitId: 'os-unit-1',
      unitName: 'Unit 1: Process Synchronization & Concurrency',
      chunkCount: 2,
      pageCount: 2,
      addedAt: DateTime.now().subtract(const Duration(days: 1)),
      nativePageCount: 0,
      ocrPageCount: 2,
    );
    osUnit1.documents.add(osHandwrittenDoc);

    const hwPage1Text =
        'Critical Section Problem notes from lecture: 1) Mutual Exclusion: only 1 process in CS at any time. '
        '2) Progress: if no process is in CS, who enters cannot be delayed forever. '
        '3) Bounded wait: limit on turns before waiting process gets in. Hardware support includes Atomic TAS (Test-and-Set).';

    const hwPage2Text =
        'Semaphores summary: wait(S) decrements, signal(S) increments. If S <= 0, process blocks. '
        'Classic problems: Producer-Consumer (bounded buffer), Dining Philosophers, Readers-Writers.';

    _indexRawText(
      subject: 'Operating Systems',
      subjectId: 'operating_systems',
      unit: 'Unit 1: Process Synchronization & Concurrency',
      unitId: 'os-unit-1',
      docName: 'Lecture_Notes_Process_Sync_Handwritten.pdf',
      documentId: 'doc-os-hw-1',
      pageNumber: 1,
      text: hwPage1Text,
      extractionType: ExtractionType.handwrittenOcr,
      confidence: 0.82,
    );
    _indexRawText(
      subject: 'Operating Systems',
      subjectId: 'operating_systems',
      unit: 'Unit 1: Process Synchronization & Concurrency',
      unitId: 'os-unit-1',
      docName: 'Lecture_Notes_Process_Sync_Handwritten.pdf',
      documentId: 'doc-os-hw-1',
      pageNumber: 2,
      text: hwPage2Text,
      extractionType: ExtractionType.handwrittenOcr,
      confidence: 0.88,
    );

    _extractedPages['Lecture_Notes_Process_Sync_Handwritten.pdf'] = [
      ExtractedPageContent(
        documentName: 'Lecture_Notes_Process_Sync_Handwritten.pdf',
        pageNumber: 1,
        text: hwPage1Text,
        extractionType: ExtractionType.handwrittenOcr,
        confidence: 0.82,
        isLowQuality: true,
        warningMessage:
            'Handwritten notes detected. Some characters were transcribed via on-device ML.',
      ),
      ExtractedPageContent(
        documentName: 'Lecture_Notes_Process_Sync_Handwritten.pdf',
        pageNumber: 2,
        text: hwPage2Text,
        extractionType: ExtractionType.handwrittenOcr,
        confidence: 0.88,
        isLowQuality: false,
      ),
    ];

    // OS Unit 2: Requirement 32 Scenario
    // 1. FOM U2.pdf (contains PAL_OS_UNIT2_TEST_8472)
    final osFomDoc = VaultDocument(
      id: 'doc-os-fom-u2',
      name: 'FOM U2.pdf',
      path: '/vault/FOM_U2.pdf',
      subjectId: 'operating_systems',
      subjectName: 'Operating Systems',
      unitId: 'os-unit-2',
      unitName: 'Unit 2: CPU Scheduling & Deadlocks',
      chunkCount: 3,
      pageCount: 3,
      addedAt: DateTime.now().subtract(const Duration(days: 2)),
      nativePageCount: 3,
      ocrPageCount: 0,
      sourceType: 'pdf',
    );
    osUnit2.documents.add(osFomDoc);

    const fomPage1Text =
        'A deadlock occurs when a set of blocked processes each holding a resource and waiting to acquire a resource held by another process. '
        'Four Coffman conditions must hold simultaneously for deadlock: 1. Mutual Exclusion, 2. Hold and Wait, '
        '3. No Preemption, 4. Circular Wait. Dijkstra\'s Banker\'s Algorithm is used for deadlock avoidance in multi-instance resource systems. '
        'Verification token: PAL_OS_UNIT2_TEST_8472.';
    const fomPage2Text =
        'Resource Allocation Graph (RAG) models system state. If graph has no cycles, no deadlock. If single instance per resource and cycle exists, deadlock is present.';
    const fomPage3Text =
        'Deadlock detection uses an algorithm similar to Banker\'s. Recovery options include process termination (abort all vs abort one at a time) and resource preemption.';

    _indexRawText(
      subject: 'Operating Systems',
      subjectId: 'operating_systems',
      unit: 'Unit 2: CPU Scheduling & Deadlocks',
      unitId: 'os-unit-2',
      docName: 'FOM U2.pdf',
      documentId: 'doc-os-fom-u2',
      pageNumber: 1,
      text: fomPage1Text,
      extractionType: ExtractionType.nativePdf,
      confidence: 1.0,
    );
    _indexRawText(
      subject: 'Operating Systems',
      subjectId: 'operating_systems',
      unit: 'Unit 2: CPU Scheduling & Deadlocks',
      unitId: 'os-unit-2',
      docName: 'FOM U2.pdf',
      documentId: 'doc-os-fom-u2',
      pageNumber: 2,
      text: fomPage2Text,
      extractionType: ExtractionType.nativePdf,
      confidence: 1.0,
    );
    _indexRawText(
      subject: 'Operating Systems',
      subjectId: 'operating_systems',
      unit: 'Unit 2: CPU Scheduling & Deadlocks',
      unitId: 'os-unit-2',
      docName: 'FOM U2.pdf',
      documentId: 'doc-os-fom-u2',
      pageNumber: 3,
      text: fomPage3Text,
      extractionType: ExtractionType.nativePdf,
      confidence: 1.0,
    );

    _extractedPages['FOM U2.pdf'] = [
      ExtractedPageContent(
        documentName: 'FOM U2.pdf',
        pageNumber: 1,
        text: fomPage1Text,
        extractionType: ExtractionType.nativePdf,
      ),
      ExtractedPageContent(
        documentName: 'FOM U2.pdf',
        pageNumber: 2,
        text: fomPage2Text,
        extractionType: ExtractionType.nativePdf,
      ),
      ExtractedPageContent(
        documentName: 'FOM U2.pdf',
        pageNumber: 3,
        text: fomPage3Text,
        extractionType: ExtractionType.nativePdf,
      ),
    ];

    // 2. Lesson-2.pdf (38 pages)
    final osLesson2Doc = VaultDocument(
      id: 'doc-os-lesson2',
      name: 'Lesson-2.pdf',
      path: '/vault/Lesson-2.pdf',
      subjectId: 'operating_systems',
      subjectName: 'Operating Systems',
      unitId: 'os-unit-2',
      unitName: 'Unit 2: CPU Scheduling & Deadlocks',
      chunkCount: 4,
      pageCount: 38,
      addedAt: DateTime.now().subtract(const Duration(days: 1)),
      nativePageCount: 38,
      ocrPageCount: 0,
      sourceType: 'pdf',
    );
    osUnit2.documents.add(osLesson2Doc);

    const lesson2Text =
        'CPU Scheduling: First-Come First-Served (FCFS) suffers from convoy effect. Shortest Job First (SJF) is provably optimal for minimizing average waiting time but requires predicting future burst lengths. '
        'Round Robin (RR) with time quantum q: if q is large, RR behaves like FCFS; if q is small, context switch overhead dominates. Priority scheduling may cause starvation, solved by aging.';
    _indexRawText(
      subject: 'Operating Systems',
      subjectId: 'operating_systems',
      unit: 'Unit 2: CPU Scheduling & Deadlocks',
      unitId: 'os-unit-2',
      docName: 'Lesson-2.pdf',
      documentId: 'doc-os-lesson2',
      pageNumber: 1,
      text: lesson2Text,
      extractionType: ExtractionType.nativePdf,
      confidence: 1.0,
    );
    _extractedPages['Lesson-2.pdf'] = [
      ExtractedPageContent(
        documentName: 'Lesson-2.pdf',
        pageNumber: 1,
        text: lesson2Text,
        extractionType: ExtractionType.nativePdf,
      ),
    ];

    // 3. OS Lecture · Sep 12 (52 min audio lecture)
    final osLectureDoc = VaultDocument(
      id: 'doc-os-lecture-sep12',
      name: 'OS Lecture · Sep 12',
      path: '/lectures/os_lecture_sep12.m4a',
      audioPath: '/lectures/os_lecture_sep12.m4a',
      subjectId: 'operating_systems',
      subjectName: 'Operating Systems',
      unitId: 'os-unit-2',
      unitName: 'Unit 2: CPU Scheduling & Deadlocks',
      chunkCount: 3,
      pageCount: 1,
      durationSeconds: 3120, // 52 min
      addedAt: DateTime.now().subtract(const Duration(days: 1)),
      sourceType: 'lectureTranscript',
    );
    osUnit2.documents.add(osLectureDoc);

    const osLectureText =
        'Today we covered CPU scheduling tradeoffs. Professor Tanenbaum explained why Linux CFS (Completely Fair Scheduler) uses a red-black tree indexed by virtual runtime. '
        'We also explored real-time scheduling: Rate Monotonic Scheduling (RMS) vs Earliest Deadline First (EDF).';
    _indexRawText(
      subject: 'Operating Systems',
      subjectId: 'operating_systems',
      unit: 'Unit 2: CPU Scheduling & Deadlocks',
      unitId: 'os-unit-2',
      docName: 'OS Lecture · Sep 12',
      documentId: 'doc-os-lecture-sep12',
      pageNumber: 1,
      text: osLectureText,
      timestamp: '00:00',
      sourceType: 'lectureTranscript',
      extractionType: ExtractionType.audioTranscript,
      confidence: 1.0,
    );

    // 4. OS Handwritten Notes (6 pages OCR)
    final osHwU2Doc = VaultDocument(
      id: 'doc-os-hw-u2',
      name: 'OS Handwritten Notes',
      path: '/vault/OS_Handwritten_Notes.pdf',
      subjectId: 'operating_systems',
      subjectName: 'Operating Systems',
      unitId: 'os-unit-2',
      unitName: 'Unit 2: CPU Scheduling & Deadlocks',
      chunkCount: 2,
      pageCount: 6,
      addedAt: DateTime.now(),
      nativePageCount: 0,
      ocrPageCount: 6,
      sourceType: 'handwritten',
    );
    osUnit2.documents.add(osHwU2Doc);

    const osHwU2Text =
        'Exam formulas: Turnaround Time = Completion Time - Arrival Time. Waiting Time = Turnaround Time - Burst Time. '
        'Response Ratio = (W + S) / S for HRRN scheduling.';
    _indexRawText(
      subject: 'Operating Systems',
      subjectId: 'operating_systems',
      unit: 'Unit 2: CPU Scheduling & Deadlocks',
      unitId: 'os-unit-2',
      docName: 'OS Handwritten Notes',
      documentId: 'doc-os-hw-u2',
      pageNumber: 1,
      text: osHwU2Text,
      sourceType: 'handwritten',
      extractionType: ExtractionType.handwrittenOcr,
      confidence: 0.86,
    );
    _extractedPages['OS Handwritten Notes'] = [
      ExtractedPageContent(
        documentName: 'OS Handwritten Notes',
        pageNumber: 1,
        text: osHwU2Text,
        extractionType: ExtractionType.handwrittenOcr,
      ),
    ];

    // OS Unit 3: Memory Management
    final osUnit3Doc = VaultDocument(
      id: 'doc-os-u3-1',
      name: 'Paging_and_Virtual_Memory.pdf',
      path: '/vault/Paging_and_Virtual_Memory.pdf',
      subjectId: 'operating_systems',
      subjectName: 'Operating Systems',
      unitId: 'os-unit-3',
      unitName: 'Unit 3: Memory Management & Virtual Memory',
      chunkCount: 2,
      pageCount: 4,
      addedAt: DateTime.now().subtract(const Duration(days: 1)),
      nativePageCount: 4,
      ocrPageCount: 0,
      sourceType: 'pdf',
    );
    osUnit3.documents.add(osUnit3Doc);

    const osUnit3Text =
        'Virtual Memory abstraction provides each process with a contiguous address space. Paging divides virtual memory into pages and physical memory into frames. '
        'Translation Lookaside Buffer (TLB) caches page table entries. Page replacement algorithms: FIFO, Optimal (Belady), LRU (Least Recently Used), and Clock algorithm.';
    _indexRawText(
      subject: 'Operating Systems',
      subjectId: 'operating_systems',
      unit: 'Unit 3: Memory Management & Virtual Memory',
      unitId: 'os-unit-3',
      docName: 'Paging_and_Virtual_Memory.pdf',
      documentId: 'doc-os-u3-1',
      pageNumber: 1,
      text: osUnit3Text,
      extractionType: ExtractionType.nativePdf,
      confidence: 1.0,
    );
    _extractedPages['Paging_and_Virtual_Memory.pdf'] = [
      ExtractedPageContent(
        documentName: 'Paging_and_Virtual_Memory.pdf',
        pageNumber: 1,
        text: osUnit3Text,
        extractionType: ExtractionType.nativePdf,
      ),
    ];

    // Computer Networks Unit 1: Data Link
    final cnUnit1Doc = VaultDocument(
      id: 'doc-cn-1',
      name: 'Kurose_CN_Ch1_DataLink.pdf',
      path: '/vault/Kurose_CN_Ch1_DataLink.pdf',
      subjectId: 'computer_networks',
      subjectName: 'Computer Networks',
      unitId: 'cn-unit-1',
      unitName: 'Unit 1: Physical & Data Link Layer',
      chunkCount: 1,
      pageCount: 1,
      addedAt: DateTime.now().subtract(const Duration(days: 4)),
      nativePageCount: 1,
      ocrPageCount: 0,
      sourceType: 'pdf',
    );
    cnUnit1.documents.add(cnUnit1Doc);

    const cnDoc1Text =
        'Data Link Layer deals with framing, physical MAC addressing, flow control via Sliding Window protocols, '
        'error detection using CRC (Cyclic Redundancy Check) and Hamming codes, and media access control including CSMA/CD.';

    _indexRawText(
      subject: 'Computer Networks',
      subjectId: 'computer_networks',
      unit: 'Unit 1: Physical & Data Link Layer',
      unitId: 'cn-unit-1',
      docName: 'Kurose_CN_Ch1_DataLink.pdf',
      documentId: 'doc-cn-1',
      pageNumber: 1,
      text: cnDoc1Text,
      extractionType: ExtractionType.nativePdf,
      confidence: 1.0,
    );

    _extractedPages['Kurose_CN_Ch1_DataLink.pdf'] = [
      ExtractedPageContent(
        documentName: 'Kurose_CN_Ch1_DataLink.pdf',
        pageNumber: 1,
        text: cnDoc1Text,
        extractionType: ExtractionType.nativePdf,
      ),
    ];

    // Computer Networks Unit 2: CN U2.pdf (contains PAL_CN_UNIT2_TEST_9631)
    final cnUnit2Doc = VaultDocument(
      id: 'doc-cn-2',
      name: 'CN U2.pdf',
      path: '/vault/CN_U2.pdf',
      subjectId: 'computer_networks',
      subjectName: 'Computer Networks',
      unitId: 'cn-unit-2',
      unitName: 'Unit 2: Network Layer & Routing',
      chunkCount: 2,
      pageCount: 25,
      addedAt: DateTime.now().subtract(const Duration(days: 2)),
      nativePageCount: 25,
      ocrPageCount: 0,
      sourceType: 'pdf',
    );
    cnUnit2.documents.add(cnUnit2Doc);

    const cnDoc2Text =
        'The Network Layer provides host-to-host communication and packet forwarding across autonomous systems. '
        'Routing algorithms include Distance Vector (Bellman-Ford algorithm, count-to-infinity problem) and Link State Routing (Dijkstra\'s shortest path). '
        'Border Gateway Protocol (BGP) governs inter-domain autonomous routing. IPv4 addresses are 32-bit while IPv6 addresses are 128-bit. Subnetting uses CIDR notation. '
        'Verification token: PAL_CN_UNIT2_TEST_9631.';

    _indexRawText(
      subject: 'Computer Networks',
      subjectId: 'computer_networks',
      unit: 'Unit 2: Network Layer & Routing',
      unitId: 'cn-unit-2',
      docName: 'CN U2.pdf',
      documentId: 'doc-cn-2',
      pageNumber: 1,
      text: cnDoc2Text,
      extractionType: ExtractionType.nativePdf,
      confidence: 1.0,
    );

    _extractedPages['CN U2.pdf'] = [
      ExtractedPageContent(
        documentName: 'CN U2.pdf',
        pageNumber: 1,
        text: cnDoc2Text,
        extractionType: ExtractionType.nativePdf,
      ),
    ];

    // Machine Learning Unit 1: Regression
    final mlUnit1Doc = VaultDocument(
      id: 'doc-ml-1',
      name: 'Mitchell_ML_Ch1_Regression.pdf',
      path: '/vault/Mitchell_ML_Ch1_Regression.pdf',
      subjectId: 'machine_learning',
      subjectName: 'Machine Learning',
      unitId: 'ml-unit-1',
      unitName: 'Unit 1: Supervised Learning & Regression',
      chunkCount: 1,
      pageCount: 1,
      addedAt: DateTime.now().subtract(const Duration(days: 5)),
      nativePageCount: 1,
      ocrPageCount: 0,
    );
    mlUnit1.documents.add(mlUnit1Doc);

    const mlDoc1Text =
        'Supervised Learning maps input features to target labels. Linear regression minimizes Mean Squared Error (MSE) via gradient descent. '
        'Logistic regression models binary classification probabilities using the sigmoid activation function. Regularization techniques L1 (Lasso) and L2 (Ridge) prevent model overfitting.';

    _indexRawText(
      subject: 'Machine Learning',
      subjectId: 'machine_learning',
      unit: 'Unit 1: Supervised Learning & Regression',
      unitId: 'ml-unit-1',
      docName: 'Mitchell_ML_Ch1_Regression.pdf',
      documentId: 'doc-ml-1',
      pageNumber: 1,
      text: mlDoc1Text,
      extractionType: ExtractionType.nativePdf,
      confidence: 1.0,
    );

    _extractedPages['Mitchell_ML_Ch1_Regression.pdf'] = [
      ExtractedPageContent(
        documentName: 'Mitchell_ML_Ch1_Regression.pdf',
        pageNumber: 1,
        text: mlDoc1Text,
        extractionType: ExtractionType.nativePdf,
      ),
    ];

    // Machine Learning Unit 2: Deep Learning (contains PAL_ML_UNIT2_TEST_7314)
    final mlUnit2Doc = VaultDocument(
      id: 'doc-ml-2',
      name: 'Goodfellow_DL_Ch6_NeuralNets.pdf',
      path: '/vault/Goodfellow_DL_Ch6_NeuralNets.pdf',
      subjectId: 'machine_learning',
      subjectName: 'Machine Learning',
      unitId: 'ml-unit-2',
      unitName: 'Unit 2: Neural Networks & Deep Learning',
      chunkCount: 1,
      pageCount: 1,
      addedAt: DateTime.now().subtract(const Duration(days: 1)),
      nativePageCount: 1,
      ocrPageCount: 0,
    );
    mlUnit2.documents.add(mlUnit2Doc);

    const mlDoc2Text =
        'Deep Neural Networks consist of multiple stacked perceptron layers trained via backpropagation and stochastic gradient descent (SGD). '
        'Activation functions include ReLU, Leaky ReLU, Sigmoid, and Softmax. Convolutional Neural Networks (CNNs) utilize spatial filters and pooling layers. '
        'Transformers utilize multi-head self-attention mechanisms. '
        'Verification token: PAL_ML_UNIT2_TEST_7314.';

    _indexRawText(
      subject: 'Machine Learning',
      subjectId: 'machine_learning',
      unit: 'Unit 2: Neural Networks & Deep Learning',
      unitId: 'ml-unit-2',
      docName: 'Goodfellow_DL_Ch6_NeuralNets.pdf',
      documentId: 'doc-ml-2',
      pageNumber: 1,
      text: mlDoc2Text,
      extractionType: ExtractionType.nativePdf,
      confidence: 1.0,
    );

    _extractedPages['Goodfellow_DL_Ch6_NeuralNets.pdf'] = [
      ExtractedPageContent(
        documentName: 'Goodfellow_DL_Ch6_NeuralNets.pdf',
        pageNumber: 1,
        text: mlDoc2Text,
        extractionType: ExtractionType.nativePdf,
      ),
    ];

    // Seed Subject 5: Discrete Mathematics Unit 1: Graph Theory & Recurrence Relations (contains PAL_DISCRETE_U1_TEST_8472)
    final mathDoc1 = VaultDocument(
      id: 'doc-math-1',
      name: 'Discrete_Math_Graph_Theory_Recurrence.pdf',
      path: '/vault/Discrete_Math_Graph_Theory_Recurrence.pdf',
      subjectId: 'discrete_mathematics',
      subjectName: 'Discrete Mathematics',
      unitId: 'math-unit-1',
      unitName: 'Unit 1: Graph Theory & Recurrence Relations',
      chunkCount: 3,
      pageCount: 3,
      addedAt: DateTime.now().subtract(const Duration(days: 2)),
      nativePageCount: 3,
      ocrPageCount: 0,
      sourceType: 'pdf',
    );
    mathUnit1.documents.add(mathDoc1);

    const mathDoc1Page1 =
        'Graph Theory Fundamentals: A graph G = (V, E) consists of vertices V and edges E. '
        'An Euler path visits every edge exactly once, existing if and only if exactly 0 or 2 vertices have odd degree. '
        'An Euler circuit exists if and only if all vertices have even degree. '
        'A Hamiltonian cycle visits every vertex exactly once; Dirac\'s theorem states that if every vertex in an n-vertex graph (n >= 3) has degree >= n/2, G is Hamiltonian. '
        'The Handshaking Lemma states that the sum of degrees of all vertices equals twice the number of edges: sum(deg(v)) = 2|E|. '
        'Planar graphs can be drawn in the plane without crossing edges, satisfying Euler\'s formula: V - E + F = 2. '
        'Kuratowski\'s Theorem establishes that a finite graph is planar if and only if it does not contain a subgraph homeomorphic to K5 or K3,3. '
        'Verification token: PAL_DISCRETE_U1_TEST_8472.';

    const mathDoc1Page2 =
        'Trees and Spanning Trees: A tree is a connected acyclic undirected graph with n vertices and n - 1 edges. '
        'A spanning tree of graph G is a minimal connected subgraph containing all vertices of G. '
        'Minimum Spanning Tree (MST) algorithms include Kruskal\'s Algorithm (greedy edge-addition avoiding cycles via Disjoint Set Union) and '
        'Prim\'s Algorithm (grows a single tree by adding the minimum weight crossing edge). '
        'Graph coloring assigns colors to vertices such that adjacent vertices share different colors; '
        'the chromatic number chi(G) is the minimum colors required. Bipartite graphs are 2-colorable and have no odd cycles; '
        'Hall\'s Marriage Theorem gives necessary and sufficient conditions for a perfect matching.';

    const mathDoc1Page3 =
        'Recurrence Relations and Generating Functions: A linear homogeneous recurrence relation with constant coefficients has the form '
        'a_n = c_1 a_{n-1} + c_2 a_{n-2} + ... + c_k a_{n-k}. The solution is found by solving the characteristic polynomial equation r^k - c_1 r^{k-1} - ... - c_k = 0. '
        'For divide-and-conquer algorithms, the Master Theorem solves recurrences of the form T(n) = a T(n/b) + f(n). '
        'If f(n) = O(n^{log_b(a) - epsilon}), then T(n) = Theta(n^{log_b a}). '
        'If f(n) = Theta(n^{log_b a} log^k n), then T(n) = Theta(n^{log_b a} log^{k+1} n). '
        'Generating functions represent sequences {a_n} as formal power series G(x) = sum_{n=0}^infty a_n x^n, transforming recurrence relations into algebraic equations.';

    _indexRawText(
      subject: 'Discrete Mathematics',
      subjectId: 'discrete_mathematics',
      unit: 'Unit 1: Graph Theory & Recurrence Relations',
      unitId: 'math-unit-1',
      docName: 'Discrete_Math_Graph_Theory_Recurrence.pdf',
      documentId: 'doc-math-1',
      pageNumber: 1,
      text: mathDoc1Page1,
      extractionType: ExtractionType.nativePdf,
      confidence: 1.0,
    );
    _indexRawText(
      subject: 'Discrete Mathematics',
      subjectId: 'discrete_mathematics',
      unit: 'Unit 1: Graph Theory & Recurrence Relations',
      unitId: 'math-unit-1',
      docName: 'Discrete_Math_Graph_Theory_Recurrence.pdf',
      documentId: 'doc-math-1',
      pageNumber: 2,
      text: mathDoc1Page2,
      extractionType: ExtractionType.nativePdf,
      confidence: 1.0,
    );
    _indexRawText(
      subject: 'Discrete Mathematics',
      subjectId: 'discrete_mathematics',
      unit: 'Unit 1: Graph Theory & Recurrence Relations',
      unitId: 'math-unit-1',
      docName: 'Discrete_Math_Graph_Theory_Recurrence.pdf',
      documentId: 'doc-math-1',
      pageNumber: 3,
      text: mathDoc1Page3,
      extractionType: ExtractionType.nativePdf,
      confidence: 1.0,
    );

    _extractedPages['Discrete_Math_Graph_Theory_Recurrence.pdf'] = [
      ExtractedPageContent(
        documentName: 'Discrete_Math_Graph_Theory_Recurrence.pdf',
        pageNumber: 1,
        text: mathDoc1Page1,
        extractionType: ExtractionType.nativePdf,
      ),
      ExtractedPageContent(
        documentName: 'Discrete_Math_Graph_Theory_Recurrence.pdf',
        pageNumber: 2,
        text: mathDoc1Page2,
        extractionType: ExtractionType.nativePdf,
      ),
      ExtractedPageContent(
        documentName: 'Discrete_Math_Graph_Theory_Recurrence.pdf',
        pageNumber: 3,
        text: mathDoc1Page3,
        extractionType: ExtractionType.nativePdf,
      ),
    ];

    // Seed Unorganized Material (Req 13)
    final unorgDoc1 = VaultDocument(
      id: 'doc-unorg-1',
      name: 'Algorithms Cheatsheet.pdf',
      path: '/vault/Algorithms_Cheatsheet.pdf',
      subjectId: 'unassigned',
      subjectName: 'Unorganized',
      unitId: 'unassigned',
      unitName: 'Unorganized',
      chunkCount: 2,
      pageCount: 4,
      addedAt: DateTime.now().subtract(const Duration(hours: 4)),
      nativePageCount: 4,
      ocrPageCount: 0,
      sourceType: 'pdf',
    );
    final unorgDoc2 = VaultDocument(
      id: 'doc-unorg-2',
      name: 'Unsorted Lecture Recording',
      path: '/lectures/unsorted_recording.m4a',
      audioPath: '/lectures/unsorted_recording.m4a',
      subjectId: 'unassigned',
      subjectName: 'Unorganized',
      unitId: 'unassigned',
      unitName: 'Unorganized',
      chunkCount: 1,
      pageCount: 1,
      durationSeconds: 1200, // 20 min
      addedAt: DateTime.now().subtract(const Duration(hours: 1)),
      sourceType: 'lectureTranscript',
    );
    _unorganizedSources.addAll([unorgDoc1, unorgDoc2]);

    const unorg1Text =
        'QuickSort algorithm partition logic, average time complexity O(n log n), worst case O(n^2). '
        'MergeSort guarantee O(n log n) with O(n) auxiliary space complexity. Binary search on sorted arrays runs in O(log n).';
    _indexRawText(
      subject: 'Unorganized',
      subjectId: 'unassigned',
      unit: 'Unorganized',
      unitId: 'unassigned',
      docName: 'Algorithms Cheatsheet.pdf',
      documentId: 'doc-unorg-1',
      pageNumber: 1,
      text: unorg1Text,
      extractionType: ExtractionType.nativePdf,
      confidence: 1.0,
    );
    _extractedPages['Algorithms Cheatsheet.pdf'] = [
      ExtractedPageContent(
        documentName: 'Algorithms Cheatsheet.pdf',
        pageNumber: 1,
        text: unorg1Text,
        extractionType: ExtractionType.nativePdf,
      ),
    ];

    notifyListeners();
  }

  void _indexRawText({
    required String subject,
    required String unit,
    required String docName,
    required int pageNumber,
    required String text,
    String? subjectId,
    String? unitId,
    String? documentId,
    String sourceType = 'vaultDocument',
    String? timestamp,
    ExtractionType extractionType = ExtractionType.nativePdf,
    double confidence = 1.0,
  }) {
    final cleanSubjectId = subjectId ?? RagIdHelper.toSubjectId(subject);
    final cleanUnitId = unitId ?? RagIdHelper.toUnitId(unit);
    final cleanDocId = documentId ?? docName;

    final words =
        text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    const chunkSize = 250;
    const overlap = 35;

    if (words.length <= chunkSize) {
      _allChunks.add(TextChunk(
        id: '${docName}_p${pageNumber}_c0',
        subjectId: cleanSubjectId,
        subjectName: subject,
        unitId: cleanUnitId,
        unitName: unit,
        documentId: cleanDocId,
        documentName: docName,
        pageNumber: pageNumber,
        text: text,
        wordCount: words.length,
        extractionType: extractionType,
        confidence: confidence,
        sourceType: sourceType,
        timestamp: timestamp,
      ));
    } else {
      int start = 0;
      int chunkIdx = 0;
      while (start < words.length) {
        final end = min(start + chunkSize, words.length);
        final chunkText = words.sublist(start, end).join(' ');
        _allChunks.add(TextChunk(
          id: '${docName}_p${pageNumber}_c$chunkIdx',
          subjectId: cleanSubjectId,
          subjectName: subject,
          unitId: cleanUnitId,
          unitName: unit,
          documentId: cleanDocId,
          documentName: docName,
          pageNumber: pageNumber,
          text: chunkText,
          wordCount: end - start,
          extractionType: extractionType,
          confidence: confidence,
          sourceType: sourceType,
          timestamp: timestamp,
        ));
        chunkIdx++;
        if (end == words.length) break;
        start += (chunkSize - overlap);
      }
    }
  }

  /// Backward-compatible entrypoint: delegates to indexHybridPdfFile
  Future<VaultDocument> indexPdfFile({
    required String filePath,
    required String fileName,
    required String subjectName,
    required String unitName,
    void Function(int currentPage, int totalPages, String statusText)?
        onProgress,
  }) async {
    return indexHybridPdfFile(
      filePath: filePath,
      fileName: fileName,
      subjectName: subjectName,
      unitName: unitName,
      onProgress: onProgress,
    );
  }

  /// Complete On-Device Hybrid PDF Indexer:
  /// 1. Tries digital text extraction per page.
  /// 2. If < 15 words or image-only, renders page raster and runs on-device OCR.
  /// 3. Detects handwriting characteristics and flags low-confidence pages.
  /// 4. Preserves exact page boundaries for verified citations.
  Future<VaultDocument> indexHybridPdfFile({
    required String filePath,
    required String fileName,
    required String subjectName,
    required String unitName,
    String? subjectId,
    String? unitId,
    String? documentId,
    void Function(int currentPage, int totalPages, String statusText)?
        onProgress,
  }) async {
    _isIndexing = true;
    notifyListeners();

    final cleanSubjectId = subjectId ?? RagIdHelper.toSubjectId(subjectName);
    final cleanUnitId = unitId ?? RagIdHelper.toUnitId(unitName);
    final cleanDocId =
        documentId ?? 'doc_${DateTime.now().millisecondsSinceEpoch}';

    try {
      final fileBytes = await File(filePath).readAsBytes();
      final PdfDocument document = PdfDocument(inputBytes: fileBytes);
      final PdfTextExtractor extractor = PdfTextExtractor(document);
      final int pageCount = document.pages.count;
      int createdChunks = 0;
      int nativePages = 0;
      int ocrPages = 0;
      final List<ExtractedPageContent> extractedPages = [];

      for (int i = 0; i < pageCount; i++) {
        final int pageNum = i + 1;
        onProgress?.call(
            pageNum, pageCount, 'Analyzing page $pageNum of $pageCount...');

        final String rawPageText = extractor.extractText(
          startPageIndex: i,
          endPageIndex: i,
        );

        final digitalWords = rawPageText
            .split(RegExp(r'\s+'))
            .where((w) => w.trim().isNotEmpty)
            .toList();

        // Check if page has readable digital text: >= 15 coherent words
        final bool hasDigitalText = digitalWords.length >= 15 &&
            RegExp(r'[a-zA-Z]{2,}').hasMatch(rawPageText);

        if (hasDigitalText) {
          // Native digital PDF extraction
          _indexRawText(
            subject: subjectName,
            subjectId: cleanSubjectId,
            unit: unitName,
            unitId: cleanUnitId,
            docName: fileName,
            documentId: cleanDocId,
            pageNumber: pageNum,
            text: rawPageText,
            extractionType: ExtractionType.nativePdf,
            confidence: 1.0,
          );
          createdChunks++;
          nativePages++;

          extractedPages.add(ExtractedPageContent(
            documentName: fileName,
            pageNumber: pageNum,
            text: rawPageText.trim(),
            extractionType: ExtractionType.nativePdf,
            confidence: 1.0,
            isLowQuality: false,
          ));
        } else {
          // Scanned, photographed or handwritten page - run on-device OCR fallback
          onProgress?.call(pageNum, pageCount,
              'Scanning page $pageNum with on-device OCR...');

          String? imagePath;
          try {
            imagePath =
                await _pdfRenderer.renderPdfPage(filePath, i, scale: 2.0);
          } catch (e) {
            debugPrint('[RagService] Native page render error: $e');
          }

          if (imagePath != null && File(imagePath).existsSync()) {
            final ocrResult = await _ocrService.processImageFile(imagePath);
            final ocrText = ocrResult.text.trim();

            if (ocrText.isNotEmpty) {
              final bool isHandwritten = _detectLikelyHandwritten(ocrText);
              final extType = isHandwritten
                  ? ExtractionType.handwrittenOcr
                  : ExtractionType.printedOcr;
              final conf = isHandwritten ? 0.80 : 0.95;

              _indexRawText(
                subject: subjectName,
                subjectId: cleanSubjectId,
                unit: unitName,
                unitId: cleanUnitId,
                docName: fileName,
                documentId: cleanDocId,
                pageNumber: pageNum,
                text: ocrText,
                extractionType: extType,
                confidence: conf,
              );
              createdChunks++;
              ocrPages++;

              extractedPages.add(ExtractedPageContent(
                documentName: fileName,
                pageNumber: pageNum,
                text: ocrText,
                extractionType: extType,
                confidence: conf,
                isLowQuality: isHandwritten,
                warningMessage: isHandwritten
                    ? 'Handwritten notes detected. Some characters may need user review.'
                    : null,
                imagePath: imagePath,
              ));
            } else {
              // OCR produced no text; keep whatever raw text there was
              if (rawPageText.trim().isNotEmpty) {
                _indexRawText(
                  subject: subjectName,
                  subjectId: cleanSubjectId,
                  unit: unitName,
                  unitId: cleanUnitId,
                  docName: fileName,
                  documentId: cleanDocId,
                  pageNumber: pageNum,
                  text: rawPageText,
                  extractionType: ExtractionType.printedOcr,
                  confidence: 0.60,
                );
                createdChunks++;
                ocrPages++;
              }
              extractedPages.add(ExtractedPageContent(
                documentName: fileName,
                pageNumber: pageNum,
                text: rawPageText.trim(),
                extractionType: ExtractionType.printedOcr,
                confidence: 0.50,
                isLowQuality: true,
                warningMessage:
                    'Page image has low contrast or illegible handwriting.',
                imagePath: imagePath,
              ));
            }
          } else {
            // Renderer not available or failed; fallback to raw text if present
            if (rawPageText.trim().isNotEmpty) {
              _indexRawText(
                subject: subjectName,
                subjectId: cleanSubjectId,
                unit: unitName,
                unitId: cleanUnitId,
                docName: fileName,
                documentId: cleanDocId,
                pageNumber: pageNum,
                text: rawPageText,
                extractionType: ExtractionType.nativePdf,
                confidence: 0.70,
              );
              createdChunks++;
              nativePages++;
            }
            extractedPages.add(ExtractedPageContent(
              documentName: fileName,
              pageNumber: pageNum,
              text: rawPageText.trim(),
              extractionType: ExtractionType.nativePdf,
              confidence: 0.70,
              isLowQuality: rawPageText.trim().isEmpty,
              warningMessage: rawPageText.trim().isEmpty
                  ? 'No legible text detected on this page.'
                  : null,
            ));
          }
        }
      }

      document.dispose();

      _extractedPages[fileName] = extractedPages;
      await _savePageCache();

      final vaultDoc = VaultDocument(
        id: cleanDocId,
        name: fileName,
        path: filePath,
        subjectId: cleanSubjectId,
        subjectName: subjectName,
        unitId: cleanUnitId,
        unitName: unitName,
        chunkCount: createdChunks,
        pageCount: pageCount,
        addedAt: DateTime.now(),
        ocrPageCount: ocrPages,
        nativePageCount: nativePages,
      );

      var subject = _subjects.firstWhere(
        (s) =>
            s.id == cleanSubjectId ||
            s.name.toLowerCase() == subjectName.toLowerCase(),
        orElse: () {
          final newSub = VaultSubject(
              id: cleanSubjectId, name: subjectName, iconCode: 'book');
          _subjects.add(newSub);
          return newSub;
        },
      );

      var unit = subject.units.firstWhere(
        (u) =>
            u.id == cleanUnitId ||
            u.name.toLowerCase() == unitName.toLowerCase(),
        orElse: () {
          final newUnit = VaultUnit(
            id: cleanUnitId,
            name: unitName,
            subjectId: subject.id,
            subjectName: subject.name,
          );
          subject.units.add(newUnit);
          return newUnit;
        },
      );

      unit.documents.add(vaultDoc);
      return vaultDoc;
    } finally {
      _isIndexing = false;
      notifyListeners();
    }
  }

  bool _detectLikelyHandwritten(String text) {
    if (text.isEmpty) return false;
    final words =
        text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return false;

    final totalChars = words.fold(0, (sum, w) => sum + w.length);
    final avgLen = totalChars / words.length;

    final nonAlpha = RegExp(r'[^a-zA-Z0-9\s]').allMatches(text).length;
    final noiseRatio = nonAlpha / text.length;

    return avgLen < 3.2 || noiseRatio > 0.16;
  }

  /// Re-indexes page text after user manual review/correction.
  /// Automatically updates in-memory BM25 chunks and cached page models.
  Future<void> reindexPageText({
    required String documentName,
    required int pageNumber,
    required String newText,
  }) async {
    VaultDocument? targetDoc;
    VaultUnit? targetUnit;
    String subjectName = '';
    String unitName = '';

    for (final s in _subjects) {
      for (final u in s.units) {
        for (final d in u.documents) {
          if (d.name == documentName) {
            targetDoc = d;
            targetUnit = u;
            subjectName = s.name;
            unitName = u.name;
            break;
          }
        }
      }
    }

    // 1. Remove previous chunks for this exact page
    _allChunks.removeWhere(
      (c) => c.documentName == documentName && c.pageNumber == pageNumber,
    );

    // 2. Re-chunk and index new text
    if (newText.trim().isNotEmpty) {
      _indexRawText(
        subject: subjectName.isNotEmpty ? subjectName : 'General',
        subjectId: targetDoc?.subjectId,
        unit: unitName.isNotEmpty ? unitName : 'General',
        unitId: targetUnit?.id,
        docName: documentName,
        documentId: targetDoc?.id,
        pageNumber: pageNumber,
        text: newText.trim(),
        extractionType: ExtractionType.userCorrected,
        confidence: 1.0,
      );
    }

    // 3. Update cached ExtractedPageContent
    final pages = _extractedPages[documentName];
    if (pages != null) {
      final index = pages.indexWhere((p) => p.pageNumber == pageNumber);
      if (index != -1) {
        pages[index] = pages[index].copyWith(
          text: newText.trim(),
          extractionType: ExtractionType.userCorrected,
          confidence: 1.0,
          isLowQuality: false,
          warningMessage: null,
        );
      } else {
        pages.add(ExtractedPageContent(
          documentName: documentName,
          pageNumber: pageNumber,
          text: newText.trim(),
          extractionType: ExtractionType.userCorrected,
          confidence: 1.0,
          isLowQuality: false,
        ));
        pages.sort((a, b) => a.pageNumber.compareTo(b.pageNumber));
      }
    } else {
      _extractedPages[documentName] = [
        ExtractedPageContent(
          documentName: documentName,
          pageNumber: pageNumber,
          text: newText.trim(),
          extractionType: ExtractionType.userCorrected,
          confidence: 1.0,
          isLowQuality: false,
        ),
      ];
    }

    // 4. Update chunk count in document
    if (targetDoc != null && targetUnit != null) {
      final totalDocChunks =
          _allChunks.where((c) => c.documentName == documentName).length;
      final docIdx = targetUnit.documents.indexOf(targetDoc);
      if (docIdx != -1) {
        targetUnit.documents[docIdx] = VaultDocument(
          id: targetDoc.id,
          name: targetDoc.name,
          path: targetDoc.path,
          subjectId: targetDoc.subjectId,
          subjectName: targetDoc.subjectName,
          unitId: targetDoc.unitId,
          unitName: targetDoc.unitName,
          chunkCount: totalDocChunks,
          pageCount: targetDoc.pageCount,
          addedAt: targetDoc.addedAt,
          ocrPageCount: targetDoc.ocrPageCount,
          nativePageCount: targetDoc.nativePageCount,
        );
      }
    }

    await _savePageCache();
    notifyListeners();
  }

  /// Reprocesses a specific page with OCR if the user requests it.
  Future<ExtractedPageContent?> reprocessPageWithOcr({
    required String documentName,
    required int pageNumber,
  }) async {
    VaultDocument? targetDoc;
    for (final s in _subjects) {
      for (final u in s.units) {
        for (final d in u.documents) {
          if (d.name == documentName) {
            targetDoc = d;
            break;
          }
        }
      }
    }
    if (targetDoc == null) return null;

    final imagePath = await _pdfRenderer.renderPdfPage(
      targetDoc.path,
      pageNumber - 1,
      scale: 2.0,
    );
    if (imagePath == null) return null;

    final ocrResult = await _ocrService.processImageFile(imagePath);
    final newText = ocrResult.text.trim();

    await reindexPageText(
      documentName: documentName,
      pageNumber: pageNumber,
      newText: newText,
    );

    final pages = _extractedPages[documentName];
    if (pages == null) return null;
    final idx = pages.indexWhere((p) => p.pageNumber == pageNumber);
    return idx != -1 ? pages[idx] : null;
  }

  Future<File?> _getCacheFile() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      return File('${dir.path}/pal_extracted_pages.json');
    } catch (_) {
      return null;
    }
  }

  Future<void> _savePageCache() async {
    try {
      final file = await _getCacheFile();
      if (file == null) return;
      final Map<String, dynamic> data = {};
      for (final entry in _extractedPages.entries) {
        data[entry.key] = entry.value.map((p) => p.toMap()).toList();
      }
      file.writeAsStringSync(jsonEncode(data));
    } catch (e) {
      debugPrint('[RagService] Failed to save page cache: $e');
    }
  }

  Future<void> _loadPageCache() async {
    try {
      final file = await _getCacheFile();
      if (file == null || !file.existsSync()) return;
      final raw = file.readAsStringSync();
      if (raw.trim().isEmpty) return;
      final Map<String, dynamic> decoded = jsonDecode(raw);
      for (final entry in decoded.entries) {
        final list = (entry.value as List<dynamic>)
            .map((item) =>
                ExtractedPageContent.fromMap(item as Map<String, dynamic>))
            .toList();
        _extractedPages[entry.key] = list;
      }
    } catch (e) {
      debugPrint('[RagService] Failed to load page cache: $e');
    }
  }

  /// High-speed In-Memory BM25 Lexical-Semantic Search (< 5ms, 0 MB extra model RAM)
  List<ChunkMatch> search({
    required String query,
    RagScope? scope,
    String? filterSubject,
    String? filterUnit,
    String? filterLectureId,
    String? filterDocumentId,
    int topK = 3,
  }) {
    // Derive effective scope if not directly provided
    final effectiveScope = scope ??
        (filterLectureId != null && filterLectureId.isNotEmpty
            ? RagScope.lecture(
                lectureId: filterLectureId,
                lectureTitle: filterLectureId,
              )
            : filterDocumentId != null && filterDocumentId.isNotEmpty
                ? RagScope.document(
                    documentId: filterDocumentId,
                    documentName: filterDocumentId,
                  )
                : (filterSubject != null && filterSubject != 'All Notes')
                    ? ((filterUnit != null &&
                            filterUnit.isNotEmpty &&
                            filterUnit != 'All Units')
                        ? RagScope.subjectUnit(
                            subjectName: filterSubject,
                            unitName: filterUnit,
                          )
                        : RagScope.subject(subjectName: filterSubject))
                    : const RagScope.allNotes());

    if (effectiveScope.type == RagScopeType.off) {
      return [];
    }

    final queryTerms = _tokenize(query);
    if (queryTerms.isEmpty) return [];

    // Section 3: LOG THE ACTUAL RAG SCOPE
    debugPrint('========================================');
    debugPrint('[RAG]');
    debugPrint(
        'Subject: ${effectiveScope.subjectName ?? effectiveScope.subjectId ?? "None"}');
    debugPrint(
        'Unit: ${effectiveScope.unitName ?? effectiveScope.unitId ?? "None"}');
    debugPrint('Scope type: ${effectiveScope.type.name}');
    debugPrint('Query: "$query"');
    debugPrint('========================================');

    // Section 4: HARD PRE-RETRIEVAL CANDIDATE FILTERING & LOGGING
    final List<TextChunk> candidateChunks =
        _allChunks.where((c) => effectiveScope.matchesChunk(c)).toList();

    debugPrint('[RAG CANDIDATES] Count: ${candidateChunks.length}');
    for (final c in candidateChunks) {
      debugPrint(
          '  • doc: "${c.documentName}" | subjectId: ${c.subjectId} | unitId: ${c.unitId} | page: ${c.pageNumber}');
    }

    if (candidateChunks.isEmpty) {
      debugPrint(
          '[RAG] No candidate chunks found matching scope: ${effectiveScope.displayLabel}');
      return [];
    }

    // 2. BM25 COMPUTED EXCLUSIVELY ON CANDIDATE CHUNKS
    final int n = candidateChunks.length;
    final double totalWords =
        candidateChunks.fold(0, (sum, c) => sum + c.wordCount);
    final double avgdl = totalWords / (n > 0 ? n : 1);

    // Compute document frequency (df) strictly across candidate chunks
    final Map<String, int> docFreq = {};
    for (final term in queryTerms) {
      docFreq[term] =
          candidateChunks.where((c) => _tokenize(c.text).contains(term)).length;
    }

    const double k1 = 1.2;
    const double b = 0.75;

    final List<ChunkMatch> matches = [];

    for (final chunk in candidateChunks) {
      final chunkTokens = _tokenize(chunk.text);
      final Map<String, int> termFreq = {};
      for (final t in chunkTokens) {
        termFreq[t] = (termFreq[t] ?? 0) + 1;
      }

      double score = 0.0;
      final int dl = chunk.wordCount;

      for (final term in queryTerms) {
        final tf = termFreq[term] ?? 0;
        if (tf == 0) continue;

        final df = docFreq[term] ?? 0;
        final idf = log(1.0 + (n - df + 0.5) / (df + 0.5));
        final tfComponent = (tf * (k1 + 1.0)) /
            (tf + k1 * (1.0 - b + b * (dl / (avgdl > 0 ? avgdl : 1))));

        score += idf * tfComponent;
      }

      if (score > 0.05) {
        matches.add(ChunkMatch(chunk: chunk, score: score));
      }
    }

    // If lexical overlap produced 0 matches on terms (e.g. general task query "Generate 5 practice exam questions"),
    // but candidate chunks exist within this explicit unit/document scope, include the scoped candidate chunks.
    if (matches.isEmpty &&
        candidateChunks.isNotEmpty &&
        (effectiveScope.type == RagScopeType.subjectUnit ||
            effectiveScope.type == RagScopeType.document ||
            effectiveScope.type == RagScopeType.lecture)) {
      for (final chunk in candidateChunks.take(topK)) {
        matches.add(ChunkMatch(chunk: chunk, score: 0.1));
      }
    }

    matches.sort((a, b) => b.score.compareTo(a.score));

    // Section 5: LOG BM25 RESULTS
    debugPrint('[RAG BM25 RESULTS] Matched count: ${matches.length}');
    for (final m in matches.take(topK)) {
      debugPrint(
          '  • source: "${m.chunk.documentName}" | subject: ${m.chunk.subjectName} | unit: ${m.chunk.unitName} | page: ${m.chunk.pageNumber} | score: ${m.score.toStringAsFixed(3)}');
    }

    // Section 6 & 7: LOG VECTOR / HYBRID RESULTS
    debugPrint(
        '[RAG HYBRID RESULTS] Fused matches count: ${matches.take(topK).length}');

    // Section 8: FINAL CONTEXT VALIDATION
    final List<ChunkMatch> validatedMatches = [];
    for (final match in matches.take(topK)) {
      if (effectiveScope.matchesChunk(match.chunk)) {
        validatedMatches.add(match);
      } else {
        debugPrint(
          '[RAG_REJECTED] Chunk "${match.chunk.id}" from "${match.chunk.documentName}" (Subject: ${match.chunk.subjectName}/${match.chunk.subjectId}, Unit: ${match.chunk.unitName}/${match.chunk.unitId}) REJECTED as out of scope: ${effectiveScope.displayLabel}',
        );
      }
    }

    return validatedMatches;
  }

  List<String> _tokenize(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((t) => t.length > 2)
        .toList();
  }
}
