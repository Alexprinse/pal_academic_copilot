import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../models/deadline.dart';
import '../services/lecture_recording_service.dart';
import '../services/stt_service.dart';
import '../services/deadline_service.dart';
import '../theme/app_theme.dart';
import 'lectures_history_screen.dart';

class VoiceNotesScreen extends StatefulWidget {
  final Function(int, {String? initialQuery}) onNavigateToBrain;

  const VoiceNotesScreen({super.key, required this.onNavigateToBrain});

  @override
  State<VoiceNotesScreen> createState() => _VoiceNotesScreenState();
}

class _VoiceNotesScreenState extends State<VoiceNotesScreen>
    with SingleTickerProviderStateMixin {
  final SttService _sttService = SttService.instance;
  final DeadlineService _deadlineService = DeadlineService.instance;

  Timer? _recordTimer;
  int _elapsedSeconds = 0;
  Deadline? _detectedDeadline;
  String? _detectedPhrase;
  bool _taskSaved = false;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _sttService.addListener(_onServiceUpdate);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _inspectTextForDeadlines(_sttService.transcription);
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _pulseController.dispose();
    _sttService.removeListener(_onServiceUpdate);
    super.dispose();
  }

  void _onServiceUpdate() {
    if (!mounted) return;

    if (_sttService.isRecording && _recordTimer == null) {
      _startTimer();
    } else if (!_sttService.isRecording && _recordTimer != null) {
      _stopTimer();
    }

    _inspectTextForDeadlines(_sttService.transcription);
    setState(() {});
  }

  void _startTimer() {
    _elapsedSeconds = 0;
    _recordTimer?.cancel();
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _elapsedSeconds++;
        });
      }
    });
  }

  void _stopTimer() {
    _recordTimer?.cancel();
    _recordTimer = null;
  }

  void _inspectTextForDeadlines(String text) {
    if (text.trim().isEmpty) {
      _detectedPhrase = null;
      _detectedDeadline = null;
      return;
    }

    final triggerPattern = RegExp(
      r'([^.\n]*?(?:submit|due|deadline|homework|lab|assignment|by\s+[A-Za-z]+|at\s+\d+)[^.\n]*?\.)',
      caseSensitive: false,
    );

    final match = triggerPattern.firstMatch(text);
    if (match != null) {
      final phrase = match.group(0)?.trim();
      if (phrase != null && phrase != _detectedPhrase) {
        _detectedPhrase = phrase;
        _detectedDeadline = _deadlineService.parseNaturalLanguage(phrase);
      }
    }
  }

  String _formatDuration(int seconds) {
    final mins = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  Future<void> _toggleRecord() async {
    try {
      if (_sttService.isRecording) {
        await _sttService.stopRecording();
        _stopTimer();
      } else {
        await _sttService.startRecording();
        _startTimer();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.cardSurface,
          content: Text('Recording error: $e',
              style: const TextStyle(color: AppTheme.overduePillText)),
        ),
      );
    }
  }

  Future<void> _pickAudioFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['wav'],
    );
    if (result != null && result.files.single.path != null) {
      await _sttService.transcribeAudioFile(result.files.single.path!);
    }
  }

  void _saveDetectedDeadline() {
    if (_detectedDeadline == null) return;

    final newDl = Deadline(
      id: 'dl_${DateTime.now().millisecondsSinceEpoch}',
      title: _detectedDeadline!.title,
      course: _detectedDeadline!.course,
      dueDate: _detectedDeadline!.dueDate,
      priority: _detectedDeadline!.priority,
      isSpokenDetected: true,
      audioTimestamp:
          _formatDuration(_elapsedSeconds > 0 ? _elapsedSeconds : 148),
      sourceLocation: 'Lecture 3 Audio',
    );

    _deadlineService.addDeadline(newDl);

    setState(() {
      _taskSaved = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppTheme.cardSurface,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppTheme.cardBorder),
        ),
        content: Row(
          children: [
            const Icon(Icons.check_circle,
                color: AppTheme.trustPillText, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Added to tasks: "${newDl.title}"',
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final transcription = _sttService.transcription.trim();
    final hasRealTranscription = transcription.isNotEmpty;

    return Scaffold(
      backgroundColor: AppTheme.canvasBg,
      appBar: AppBar(
        backgroundColor: AppTheme.canvasBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Row(
          children: [
            const Text(
              'Live Capture',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.neutralPillFill,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.cardBorder),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.airplanemode_active,
                      size: 13, color: AppTheme.textSecondary),
                  SizedBox(width: 4),
                  Text(
                    'Offline',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.history_edu, color: AppTheme.primaryAccent),
            tooltip: 'My Recorded Lectures',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const LecturesHistoryScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.audio_file_outlined,
                color: AppTheme.primaryAccent),
            tooltip: 'Import WAV File',
            onPressed: _pickAudioFile,
          ),
          IconButton(
            icon: const Icon(Icons.clear, color: AppTheme.textInactive),
            tooltip: 'Clear text',
            onPressed: () {
              _sttService.clearTranscription();
              setState(() {
                _detectedPhrase = null;
                _detectedDeadline = null;
                _taskSaved = false;
              });
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (LectureRecordingService.instance.isRecordingNow) ...[
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: Colors.redAccent.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.fiber_manual_record,
                          color: Colors.redAccent, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Auto-recording active: ${LectureRecordingService.instance.activeRecording?.subject}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.redAccent,
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const LecturesHistoryScreen()),
                          );
                        },
                        child: const Text(
                          'View →',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.redAccent),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: AppTheme.trustPillFill,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.trustPillText.withValues(alpha: 0.25),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.shield_outlined,
                        color: AppTheme.trustPillText, size: 18),
                    SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        'All speech transcription runs 100% on Snapdragon NPU. No network used.',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.trustPillText,
                          height: 1.25,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (context, child) {
                      final isRec = _sttService.isRecording;
                      return Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isRec
                              ? AppTheme.overduePillText
                                  .withValues(alpha: _pulseAnimation.value)
                              : AppTheme.textInactive,
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 7),
                  Text(
                    _sttService.isRecording ? 'LIVE RECORDING' : 'MIC STANDBY',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: _sttService.isRecording
                          ? AppTheme.overduePillText
                          : AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '·  ${_formatDuration(_elapsedSeconds)}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  if (_sttService.isTranscribing)
                    const Row(
                      children: [
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.primaryAccent,
                          ),
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Transcribing...',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.primaryAccent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: AppTheme.cardDecoration,
                  child: Stack(
                    children: [
                      if (!hasRealTranscription)
                        const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.mic_none_outlined,
                                  size: 40, color: AppTheme.textInactive),
                              SizedBox(height: 12),
                              Text(
                                'No speech transcribed yet',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              SizedBox(height: 6),
                              Text(
                                'Tap the microphone button below to record live audio or import a WAV file.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        SingleChildScrollView(
                          child: Builder(builder: (context) {
                            final phrase = _detectedPhrase;
                            if (phrase != null &&
                                transcription.contains(phrase)) {
                              final pIdx = transcription.indexOf(phrase);
                              final before = transcription.substring(0, pIdx);
                              final after =
                                  transcription.substring(pIdx + phrase.length);
                              return RichText(
                                text: TextSpan(
                                  style: const TextStyle(
                                    fontSize: 16,
                                    height: 1.65,
                                    fontFamily: 'serif',
                                    color: AppTheme.textPrimary,
                                  ),
                                  children: [
                                    if (before.isNotEmpty)
                                      TextSpan(text: before),
                                    WidgetSpan(
                                      alignment: PlaceholderAlignment.baseline,
                                      baseline: TextBaseline.alphabetic,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 4, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppTheme.highlightBg,
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          phrase,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            height: 1.65,
                                            fontFamily: 'serif',
                                            fontWeight: FontWeight.w600,
                                            color: AppTheme.textPrimary,
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (after.isNotEmpty) TextSpan(text: after),
                                  ],
                                ),
                              );
                            }
                            return Text(
                              transcription,
                              style: const TextStyle(
                                fontSize: 16,
                                height: 1.65,
                                fontFamily: 'serif',
                                color: AppTheme.textPrimary,
                              ),
                            );
                          }),
                        ),
                      if (_detectedDeadline != null && !_taskSaved)
                        Positioned(
                          right: 4,
                          bottom: 4,
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: _saveDetectedDeadline,
                              borderRadius: BorderRadius.circular(20),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  color: AppTheme.cardSurface,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                      color: AppTheme.primaryAccent,
                                      width: 1.2),
                                  boxShadow: AppTheme.cardShadow,
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.add,
                                        size: 15,
                                        color: AppTheme.primaryAccent),
                                    SizedBox(width: 4),
                                    Text(
                                      '+ Add to Tasks',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.primaryAccent,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (_detectedDeadline != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.detectedPillFill,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppTheme.detectedPillText.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color:
                              AppTheme.detectedPillText.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.schedule,
                          color: AppTheme.detectedPillText,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Task detected just now',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.detectedPillText,
                                letterSpacing: 0.3,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _detectedDeadline!.title,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Due: ${_detectedDeadline!.countdownString} · ${_detectedDeadline!.course}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppTheme.detectedPillText,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!_taskSaved)
                        TextButton(
                          onPressed: _saveDetectedDeadline,
                          style: TextButton.styleFrom(
                            backgroundColor: AppTheme.cardSurface,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            minimumSize: Size.zero,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side:
                                  const BorderSide(color: AppTheme.cardBorder),
                            ),
                          ),
                          child: const Text(
                            'Save',
                            style: TextStyle(
                              color: AppTheme.detectedPillText,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        )
                      else
                        const Row(
                          children: [
                            Icon(Icons.check,
                                size: 16, color: AppTheme.trustPillText),
                            SizedBox(width: 4),
                            Text(
                              'Saved',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.trustPillText,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _toggleRecord,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.darkSurface,
                    foregroundColor: AppTheme.canvasBg,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _sttService.isRecording
                            ? Icons.stop_circle_outlined
                            : Icons.mic,
                        size: 20,
                        color: _sttService.isRecording
                            ? AppTheme.overduePillText
                            : AppTheme.primaryAccent,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _sttService.isRecording
                            ? 'Stop capture'
                            : 'Start live capture',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.canvasBg,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
            ],
          ),
        ),
      ),
    );
  }
}
