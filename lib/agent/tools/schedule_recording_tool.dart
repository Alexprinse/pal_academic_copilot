import '../agent_context.dart';
import '../agent_parameter.dart';
import '../agent_tool.dart';
import '../agent_tool_result.dart';
import '../../models/timetable_entry.dart';
import '../../services/lecture_recording_service.dart';
import '../../services/pal_notification_service.dart';
import '../../services/timetable_service.dart';

class ScheduleRecordingTool extends AgentTool {
  final LectureRecordingService _recordingService;
  final TimetableService _timetableService;

  ScheduleRecordingTool({
    LectureRecordingService? recordingService,
    TimetableService? timetableService,
  })  : _recordingService =
            recordingService ?? LectureRecordingService.instance,
        _timetableService = timetableService ?? TimetableService.instance,
        super(
          name: 'schedule_recording',
          description:
              'Schedule an automated lecture recording for a class, linking to the timetable and activating the recording scheduler.',
          isReadOnly: false,
          parameters: const [
            AgentParameter(
              name: 'subject',
              type: AgentParameterType.string,
              description:
                  'The subject/course to record (e.g. "Computer Networks", "Networking", "AI").',
              required: true,
            ),
            AgentParameter(
              name: 'day',
              type: AgentParameterType.string,
              description:
                  'The day of the lecture (e.g. "tomorrow", "Mon", "Wednesday").',
              required: false,
            ),
            AgentParameter(
              name: 'startTime',
              type: AgentParameterType.string,
              description:
                  'Lecture start time (e.g. "02:00 PM", "2pm", "14:00"). Optional if class exists in timetable.',
              required: false,
            ),
            AgentParameter(
              name: 'endTime',
              type: AgentParameterType.string,
              description:
                  'Lecture end time (e.g. "03:00 PM", "3pm", "15:00"). Optional.',
              required: false,
            ),
          ],
        );

  static const Map<int, String> _weekdayMap = {
    1: 'Mon',
    2: 'Tue',
    3: 'Wed',
    4: 'Thu',
    5: 'Fri',
    6: 'Sat',
    7: 'Sun',
  };

  @override
  Future<AgentToolResult> execute(
    Map<String, dynamic> arguments, {
    AgentContext? context,
  }) async {
    final rawSubject = (arguments['subject'] as String? ?? '').trim();
    if (rawSubject.isEmpty) {
      return AgentToolResult.validationError(
        tool: name,
        error: 'Subject name is required to schedule a lecture recording.',
      );
    }

    final now = context?.currentDateTime ?? DateTime.now();
    final rawDay = (arguments['day'] as String? ?? '').trim();
    final resolvedDay = rawDay.isNotEmpty
        ? _resolveDay(rawDay, now)
        : _resolveDay('tomorrow', now);

    final rawStartTime = (arguments['startTime'] as String? ?? '').trim();
    final rawEndTime = (arguments['endTime'] as String? ?? '').trim();

    // 1. Check if class exists on that day in timetable
    final entries = _timetableService.entries;
    final lowerSub = rawSubject.toLowerCase();

    TimetableEntry? existingEntry;
    for (final entry in entries) {
      final matchesDay =
          entry.dayOfWeek.toLowerCase() == resolvedDay.toLowerCase();
      final entrySub = entry.subject.toLowerCase();
      final matchesSubject = entrySub.contains(lowerSub) ||
          lowerSub.contains(entrySub) ||
          _isFuzzyMatch(lowerSub, entrySub);

      if (matchesSubject && matchesDay) {
        existingEntry = entry;
        break;
      }
    }

    String finalStartTime;
    String finalEndTime;
    String subjectName = rawSubject;

    if (existingEntry != null) {
      subjectName = existingEntry.subject;
      finalStartTime = rawStartTime.isNotEmpty
          ? _formatTimeStr(rawStartTime)
          : existingEntry.startTime;
      finalEndTime = rawEndTime.isNotEmpty
          ? _formatTimeStr(rawEndTime)
          : existingEntry.endTime;
    } else {
      // If class not found in timetable for that day
      if (rawStartTime.isEmpty) {
        // Look if it exists on any other day to help guide user
        final otherDayMatch = entries.firstWhere(
          (e) => e.subject.toLowerCase().contains(lowerSub),
          orElse: () => const TimetableEntry(
            id: '',
            subject: '',
            dayOfWeek: '',
            startTime: '',
            endTime: '',
            room: '',
            professor: '',
            type: '',
          ),
        );

        if (otherDayMatch.id.isNotEmpty) {
          return AgentToolResult.failure(
            tool: name,
            message:
                'I found ${otherDayMatch.subject} on ${otherDayMatch.dayOfWeek} at ${otherDayMatch.startTime}, but no class on $resolvedDay. What time is your $rawSubject class on $resolvedDay?',
            error: 'TIME_REQUIRED',
          );
        }

        return AgentToolResult.failure(
          tool: name,
          message:
              'What time is your $rawSubject class on $resolvedDay? Please provide the start and end time.',
          error: 'TIME_REQUIRED',
        );
      }

      finalStartTime = _formatTimeStr(rawStartTime);
      finalEndTime = rawEndTime.isNotEmpty
          ? _formatTimeStr(rawEndTime)
          : _deriveEndTime(finalStartTime);

      // Add as timetable entry so RecordingScheduler can automatically record it
      final newEntry = TimetableEntry(
        id: 'rec_${DateTime.now().millisecondsSinceEpoch}',
        subject: rawSubject,
        dayOfWeek: resolvedDay,
        startTime: finalStartTime,
        endTime: finalEndTime,
        room: 'Lecture Hall',
        professor: 'TBD',
        type: 'Lecture',
      );
      _timetableService.addEntry(newEntry);
    }

    // Ensure auto-recording is active
    _recordingService.setAutoRecordEnabled(true);

    await PalNotificationService.instance.showAgentActionNotification(
      title: '✓ Recording Scheduled · $subjectName',
      message:
          '$resolvedDay · $finalStartTime – $finalEndTime. I\'ll remind you before class.',
      entityId: subjectName,
    );

    return AgentToolResult.success(
      tool: name,
      message:
          'Scheduled automatic recording for $subjectName on $resolvedDay from $finalStartTime to $finalEndTime. Pal will notify you 10 minutes before and automatically capture the audio.',
      data: {
        'subject': subjectName,
        'day': resolvedDay,
        'startTime': finalStartTime,
        'endTime': finalEndTime,
        'autoRecordEnabled': true,
        'preClassAlertMinutes': 10,
        'action': 'schedule_recording',
        'undoable': true,
      },
    );
  }

  String _resolveDay(String input, DateTime reference) {
    final lower = input.toLowerCase().trim();
    if (lower == 'today') {
      return _weekdayMap[reference.weekday] ?? 'Mon';
    }
    if (lower == 'tomorrow') {
      final tomorrow = reference.add(const Duration(days: 1));
      return _weekdayMap[tomorrow.weekday] ?? 'Mon';
    }
    for (final entry in _weekdayMap.entries) {
      if (lower.startsWith(entry.value.toLowerCase())) {
        return entry.value;
      }
    }
    final fullDays = {
      'monday': 'Mon',
      'tuesday': 'Tue',
      'wednesday': 'Wed',
      'thursday': 'Thu',
      'friday': 'Fri',
      'saturday': 'Sat',
      'sunday': 'Sun',
    };
    if (fullDays.containsKey(lower)) {
      return fullDays[lower]!;
    }
    return input;
  }

  String _formatTimeStr(String raw) {
    final trimmed = raw.trim();
    final match12 =
        RegExp(r'^(\d{1,2})(?::(\d{2}))?\s*(am|pm)?$', caseSensitive: false)
            .firstMatch(trimmed);
    if (match12 != null) {
      int hour = int.parse(match12.group(1)!);
      final minute = match12.group(2) ?? '00';
      final period = match12.group(3)?.toUpperCase();

      if (period != null) {
        return '${hour.toString().padLeft(2, '0')}:$minute $period';
      }
      if (hour < 8) {
        hour += 12;
        return '${(hour - 12).toString().padLeft(2, '0')}:$minute PM';
      } else if (hour < 12) {
        return '${hour.toString().padLeft(2, '0')}:$minute AM';
      } else if (hour == 12) {
        return '12:$minute PM';
      } else {
        return '${(hour - 12).toString().padLeft(2, '0')}:$minute PM';
      }
    }
    return trimmed;
  }

  String _deriveEndTime(String startTimeStr) {
    final match = RegExp(r'^(\d{1,2}):(\d{2})\s*(AM|PM)$', caseSensitive: false)
        .firstMatch(startTimeStr);
    if (match != null) {
      var hour = int.parse(match.group(1)!);
      final min = match.group(2)!;
      var period = match.group(3)!.toUpperCase();

      if (hour == 12) {
        hour = 1;
      } else if (hour == 11) {
        hour = 12;
        period = (period == 'AM') ? 'PM' : 'AM';
      } else {
        hour += 1;
      }
      return '${hour.toString().padLeft(2, '0')}:$min $period';
    }
    return '01 hour later';
  }

  bool _isFuzzyMatch(String a, String b) {
    if (a == b) return true;
    if (a == 'network' && (b.contains('network') || b.contains('networking'))) {
      return true;
    }
    if (a == 'networking' &&
        (b.contains('network') || b.contains('networking'))) {
      return true;
    }
    if (a == 'ai' &&
        (b.contains('artificial intelligence') || b.contains('ai'))) {
      return true;
    }
    if (b == 'ai' &&
        (a.contains('artificial intelligence') || a.contains('ai'))) {
      return true;
    }
    if (a == 'os' && (b.contains('operating system') || b.contains('os'))) {
      return true;
    }
    if (b == 'os' && (a.contains('operating system') || a.contains('os'))) {
      return true;
    }
    return false;
  }
}
