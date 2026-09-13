class LectureTranscriptChunk {
  final int chunkIndex;
  final String startTimestamp; // e.g. "00:00"
  final String endTimestamp; // e.g. "00:25"
  final String text;

  const LectureTranscriptChunk({
    required this.chunkIndex,
    required this.startTimestamp,
    required this.endTimestamp,
    required this.text,
  });

  Map<String, dynamic> toJson() => {
        'chunkIndex': chunkIndex,
        'startTimestamp': startTimestamp,
        'endTimestamp': endTimestamp,
        'text': text,
      };

  factory LectureTranscriptChunk.fromJson(Map<String, dynamic> json) =>
      LectureTranscriptChunk(
        chunkIndex: (json['chunkIndex'] as int?) ?? 0,
        startTimestamp: (json['startTimestamp'] as String?) ?? '00:00',
        endTimestamp: (json['endTimestamp'] as String?) ?? '00:25',
        text: (json['text'] as String?) ?? '',
      );
}

class LectureSummary {
  final List<String> keyPoints;
  final List<String> importantConcepts;
  final List<String> actionItems;
  final List<String> reviewQuestions;

  const LectureSummary({
    this.keyPoints = const [],
    this.importantConcepts = const [],
    this.actionItems = const [],
    this.reviewQuestions = const [],
  });

  Map<String, dynamic> toJson() => {
        'keyPoints': keyPoints,
        'importantConcepts': importantConcepts,
        'actionItems': actionItems,
        'reviewQuestions': reviewQuestions,
      };

  factory LectureSummary.fromJson(Map<String, dynamic> json) => LectureSummary(
        keyPoints: (json['keyPoints'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        importantConcepts: (json['importantConcepts'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        actionItems: (json['actionItems'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        reviewQuestions: (json['reviewQuestions'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
      );
}

class LectureRecording {
  final String id;
  final String subject;
  final String? title;
  final String? timetableEntryId;
  final DateTime date;
  final String scheduledStart;
  final String scheduledEnd;
  final DateTime actualStart;
  final DateTime? actualEnd;
  final String audioPath;
  final int durationSeconds;
  final int fileSizeBytes;
  final String
      transcriptionStatus; // 'pending', 'transcribing', 'completed', 'failed'
  final String summaryStatus; // 'none', 'generating', 'completed', 'failed'
  final String transcriptText;
  final List<LectureTranscriptChunk> chunks;
  final LectureSummary? summary;
  final List<String> extractedDeadlineIds;
  final String sourceType; // 'scheduledLecture', 'liveCapture', 'importedAudio'

  final String? subjectId;
  final String? unitId;
  final String? unitName;

  const LectureRecording({
    required this.id,
    required this.subject,
    this.title,
    this.timetableEntryId,
    required this.date,
    required this.scheduledStart,
    required this.scheduledEnd,
    required this.actualStart,
    this.actualEnd,
    required this.audioPath,
    required this.durationSeconds,
    this.fileSizeBytes = 0,
    this.transcriptionStatus = 'pending',
    this.summaryStatus = 'none',
    this.transcriptText = '',
    this.chunks = const [],
    this.summary,
    this.extractedDeadlineIds = const [],
    this.sourceType = 'scheduledLecture',
    this.subjectId,
    this.unitId,
    this.unitName,
  });

  bool get isLiveCapture => sourceType == 'liveCapture';

  String get displayTitle =>
      (title != null && title!.trim().isNotEmpty) ? title! : subject;

  String get formattedFileSize {
    if (fileSizeBytes <= 0) return '0 KB';
    if (fileSizeBytes >= 1024 * 1024) {
      final mb = fileSizeBytes / (1024 * 1024);
      return '${mb.toStringAsFixed(2)} MB';
    }
    final kb = fileSizeBytes / 1024;
    return '${kb.toStringAsFixed(1)} KB';
  }

  String get formattedDuration {
    final minutes = durationSeconds ~/ 60;
    final seconds = durationSeconds % 60;
    if (minutes >= 60) {
      final hours = minutes ~/ 60;
      final remMin = minutes % 60;
      return '$hours hr $remMin min';
    } else if (minutes > 0) {
      return '$minutes min';
    } else {
      return '$seconds sec';
    }
  }

  LectureRecording copyWith({
    String? id,
    String? subject,
    String? title,
    String? timetableEntryId,
    DateTime? date,
    String? scheduledStart,
    String? scheduledEnd,
    DateTime? actualStart,
    DateTime? actualEnd,
    String? audioPath,
    int? durationSeconds,
    int? fileSizeBytes,
    String? transcriptionStatus,
    String? summaryStatus,
    String? transcriptText,
    List<LectureTranscriptChunk>? chunks,
    LectureSummary? summary,
    List<String>? extractedDeadlineIds,
    String? sourceType,
    String? subjectId,
    String? unitId,
    String? unitName,
  }) {
    return LectureRecording(
      id: id ?? this.id,
      subject: subject ?? this.subject,
      title: title ?? this.title,
      timetableEntryId: timetableEntryId ?? this.timetableEntryId,
      date: date ?? this.date,
      scheduledStart: scheduledStart ?? this.scheduledStart,
      scheduledEnd: scheduledEnd ?? this.scheduledEnd,
      actualStart: actualStart ?? this.actualStart,
      actualEnd: actualEnd ?? this.actualEnd,
      audioPath: audioPath ?? this.audioPath,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      transcriptionStatus: transcriptionStatus ?? this.transcriptionStatus,
      summaryStatus: summaryStatus ?? this.summaryStatus,
      transcriptText: transcriptText ?? this.transcriptText,
      chunks: chunks ?? this.chunks,
      summary: summary ?? this.summary,
      extractedDeadlineIds: extractedDeadlineIds ?? this.extractedDeadlineIds,
      sourceType: sourceType ?? this.sourceType,
      subjectId: subjectId ?? this.subjectId,
      unitId: unitId ?? this.unitId,
      unitName: unitName ?? this.unitName,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'subject': subject,
        'title': title,
        'timetableEntryId': timetableEntryId,
        'date': date.toIso8601String(),
        'scheduledStart': scheduledStart,
        'scheduledEnd': scheduledEnd,
        'actualStart': actualStart.toIso8601String(),
        'actualEnd': actualEnd?.toIso8601String(),
        'audioPath': audioPath,
        'durationSeconds': durationSeconds,
        'fileSizeBytes': fileSizeBytes,
        'transcriptionStatus': transcriptionStatus,
        'summaryStatus': summaryStatus,
        'transcriptText': transcriptText,
        'chunks': chunks.map((c) => c.toJson()).toList(),
        'summary': summary?.toJson(),
        'extractedDeadlineIds': extractedDeadlineIds,
        'sourceType': sourceType,
        if (subjectId != null) 'subjectId': subjectId,
        if (unitId != null) 'unitId': unitId,
        if (unitName != null) 'unitName': unitName,
      };

  factory LectureRecording.fromJson(Map<String, dynamic> json) =>
      LectureRecording(
        id: json['id'] as String,
        subject: json['subject'] as String,
        title: json['title'] as String?,
        timetableEntryId: json['timetableEntryId'] as String?,
        date: DateTime.parse(json['date'] as String),
        scheduledStart: (json['scheduledStart'] as String?) ?? '09:00 AM',
        scheduledEnd: (json['scheduledEnd'] as String?) ?? '10:00 AM',
        actualStart: DateTime.parse(json['actualStart'] as String),
        actualEnd: json['actualEnd'] != null
            ? DateTime.parse(json['actualEnd'] as String)
            : null,
        audioPath: json['audioPath'] as String,
        durationSeconds: (json['durationSeconds'] as int?) ?? 0,
        fileSizeBytes: (json['fileSizeBytes'] as int?) ?? 0,
        transcriptionStatus:
            (json['transcriptionStatus'] as String?) ?? 'pending',
        summaryStatus: (json['summaryStatus'] as String?) ?? 'none',
        transcriptText: (json['transcriptText'] as String?) ?? '',
        chunks: (json['chunks'] as List<dynamic>?)
                ?.map((c) =>
                    LectureTranscriptChunk.fromJson(c as Map<String, dynamic>))
                .toList() ??
            const [],
        summary: json['summary'] != null
            ? LectureSummary.fromJson(json['summary'] as Map<String, dynamic>)
            : null,
        extractedDeadlineIds: (json['extractedDeadlineIds'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        sourceType: (json['sourceType'] as String?) ?? 'scheduledLecture',
        subjectId: json['subjectId'] as String?,
        unitId: json['unitId'] as String?,
        unitName: json['unitName'] as String?,
      );
}
