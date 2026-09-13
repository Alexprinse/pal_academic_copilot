import 'package:flutter/material.dart';
import '../models/lecture_recording.dart';
import '../services/lecture_recording_service.dart';
import '../theme/app_theme.dart';
import 'lecture_details_screen.dart';

class LecturesHistoryScreen extends StatelessWidget {
  const LecturesHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.canvasBg,
      appBar: AppBar(
        backgroundColor: AppTheme.canvasBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              size: 18, color: AppTheme.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'My Lectures',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppTheme.textPrimary,
            letterSpacing: -0.4,
          ),
        ),
      ),
      body: ListenableBuilder(
        listenable: LectureRecordingService.instance,
        builder: (context, _) {
          final recordings = LectureRecordingService.instance.recordings;
          final activeRecording =
              LectureRecordingService.instance.activeRecording;

          if (recordings.isEmpty && activeRecording == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppTheme.cardSurface,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppTheme.cardBorder),
                        boxShadow: AppTheme.cardShadow,
                      ),
                      child: const Icon(
                        Icons.mic_none_outlined,
                        size: 40,
                        color: AppTheme.primaryAccent,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'No Recorded Lectures Yet',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Classes from your timetable will automatically record here when auto-record is enabled.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            children: [
              // Active Recording Banner if ongoing
              if (activeRecording != null) ...[
                _buildActiveRecordingCard(context, activeRecording),
                const SizedBox(height: 18),
              ],

              const Padding(
                padding: EdgeInsets.only(left: 4, bottom: 12),
                child: Text(
                  'PAST RECORDINGS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),

              ...recordings
                  .map((recording) => _buildRecordingItem(context, recording)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildActiveRecordingCard(
      BuildContext context, LectureRecording active) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: AppTheme.overduePillText.withValues(alpha: 0.5), width: 1.5),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.overduePillText.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.fiber_manual_record,
                color: AppTheme.overduePillText, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Text(
                      'RECORDING NOW',
                      style: TextStyle(
                        color: AppTheme.overduePillText,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  active.subject,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Text(
                  '${active.scheduledStart} - ${active.scheduledEnd}',
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 11.5),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () =>
                LectureRecordingService.instance.stopActiveRecording(),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.overduePillFill,
              foregroundColor: AppTheme.overduePillText,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: const BorderSide(color: AppTheme.overduePillText),
              ),
            ),
            child: const Text('Stop',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordingItem(BuildContext context, LectureRecording recording) {
    final statusBadge = _buildStatusBadge(recording.transcriptionStatus);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: AppTheme.cardDecoration,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => LectureDetailsScreen(recording: recording),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.detectedPillFill,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.audiotrack,
                    color: AppTheme.primaryAccent,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    recording.displayTitle,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.textPrimary,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: recording.isLiveCapture
                                        ? AppTheme.detectedPillFill
                                        : AppTheme.neutralPillFill,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    recording.isLiveCapture
                                        ? 'LIVE'
                                        : (recording.sourceType ==
                                                'importedAudio'
                                            ? 'IMPORTED'
                                            : 'SCHEDULED'),
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                      color: recording.isLiveCapture
                                          ? AppTheme.primaryAccent
                                          : AppTheme.textSecondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          statusBadge,
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        recording.isLiveCapture
                            ? '${recording.formattedDuration} · ${_formatItemDate(recording.date)}'
                            : '${recording.scheduledStart} - ${recording.scheduledEnd} • ${recording.formattedDuration}',
                        style: const TextStyle(
                            fontSize: 12, color: AppTheme.textSecondary),
                      ),
                      if (recording.summary != null &&
                          recording.summary!.keyPoints.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          recording.summary!.keyPoints.first,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11.5, color: AppTheme.textSecondary),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right,
                    color: AppTheme.textSecondary, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color bg;
    Color fg;
    String text;

    switch (status) {
      case 'completed':
        bg = AppTheme.trustPillFill;
        fg = AppTheme.trustPillText;
        text = 'Transcribed';
        break;
      case 'transcribing':
        bg = AppTheme.detectedPillFill;
        fg = AppTheme.primaryAccent;
        text = 'Transcribing...';
        break;
      case 'failed':
        bg = AppTheme.overduePillFill;
        fg = AppTheme.overduePillText;
        text = 'Failed';
        break;
      default:
        bg = AppTheme.neutralPillFill;
        fg = AppTheme.neutralPillText;
        text = 'Pending';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(color: fg, fontSize: 10, fontWeight: FontWeight.w700),
      ),
    );
  }

  static String _formatItemDate(DateTime dt) {
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
    return '${months[dt.month - 1]} ${dt.day}';
  }
}
