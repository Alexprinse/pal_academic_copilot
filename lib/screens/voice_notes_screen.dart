import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/stt_service.dart';
import '../services/deadline_service.dart';
import '../theme/app_theme.dart';

class VoiceNotesScreen extends StatefulWidget {
  final Function(int, {String? initialQuery}) onNavigateToBrain;

  const VoiceNotesScreen({super.key, required this.onNavigateToBrain});

  @override
  State<VoiceNotesScreen> createState() => _VoiceNotesScreenState();
}

class _VoiceNotesScreenState extends State<VoiceNotesScreen> {
  final SttService _sttService = SttService.instance;
  final DeadlineService _deadlineService = DeadlineService.instance;
  final TextEditingController _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _sttService.addListener(_onServiceUpdate);
    _textController.text = _sttService.transcription;
  }

  @override
  void dispose() {
    _sttService.removeListener(_onServiceUpdate);
    _textController.dispose();
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) {
      if (_sttService.transcription.isNotEmpty &&
          _textController.text != _sttService.transcription) {
        _textController.text = _sttService.transcription;
      }
      setState(() {});
    }
  }

  Future<void> _toggleRecord() async {
    try {
      if (_sttService.isRecording) {
        await _sttService.stopRecording();
      } else {
        await _sttService.startRecording();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.cardDark,
          content: Text('Recording error: $e',
              style: const TextStyle(color: AppTheme.redAccent)),
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

  void _createDeadlineFromSpeech() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    final dl = _deadlineService.parseNaturalLanguage(text);
    _deadlineService.addDeadline(dl);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppTheme.cardDark,
        behavior: SnackBarBehavior.floating,
        content: Row(
          children: [
            const Icon(Icons.check_circle,
                color: AppTheme.greenAccent, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Created: "${dl.title}" (${dl.countdownString})',
                style: const TextStyle(color: AppTheme.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Voice Notes'),
            Text(
              'Whisper Tiny INT8 Speech-to-Text',
              style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.audio_file, color: AppTheme.cyanAccent),
            tooltip: 'Import WAV File',
            onPressed: _pickAudioFile,
          ),
          IconButton(
            icon: const Icon(Icons.clear, color: AppTheme.textMuted),
            tooltip: 'Clear text',
            onPressed: () {
              _sttService.clearTranscription();
              _textController.clear();
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Engine Spec Banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.cardDark,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.cardBorder),
              ),
              child: const Row(
                children: [
                  Icon(Icons.graphic_eq, color: AppTheme.cyanAccent, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '16kHz Mono • Safe 25s Waveform Windowing • Zero Buzzing',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Main Transcription Box
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.cardDark,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.cardBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Transcription Output',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        if (_sttService.isTranscribing)
                          const Row(
                            children: [
                              SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppTheme.cyanAccent,
                                ),
                              ),
                              SizedBox(width: 6),
                              Text(
                                'Transcribing...',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.cyanAccent,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                    const Divider(color: AppTheme.cardBorder, height: 20),
                    Expanded(
                      child: TextField(
                        controller: _textController,
                        maxLines: null,
                        expands: true,
                        style: const TextStyle(
                          fontSize: 15,
                          height: 1.5,
                          color: AppTheme.textPrimary,
                        ),
                        decoration: const InputDecoration(
                          hintText:
                              'Tap the microphone below to record lecture audio, or upload a WAV file...',
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          fillColor: Colors.transparent,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Action Chips
            Wrap(
              spacing: 10,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.event_available,
                      size: 16, color: AppTheme.amberAccent),
                  label: const Text('Create Deadline from Speech'),
                  onPressed: _textController.text.trim().isNotEmpty
                      ? _createDeadlineFromSpeech
                      : null,
                ),
                ActionChip(
                  avatar: const Icon(Icons.psychology,
                      size: 16, color: AppTheme.cyanAccent),
                  label: const Text('Summarize with Pal'),
                  onPressed: _textController.text.trim().isNotEmpty
                      ? () {
                          widget.onNavigateToBrain(
                            4,
                            initialQuery:
                                'Please summarize this lecture transcript and extract key formulas/takeaways:\n\n"${_textController.text.trim()}"',
                          );
                        }
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Large Recording Button
            GestureDetector(
              onTap: _toggleRecord,
              child: Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _sttService.isRecording
                      ? AppTheme.redAccent
                      : AppTheme.cyanAccent,
                  boxShadow: [
                    BoxShadow(
                      color: (_sttService.isRecording
                              ? AppTheme.redAccent
                              : AppTheme.cyanAccent)
                          .withValues(alpha: 0.4),
                      blurRadius: 20,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: Icon(
                  _sttService.isRecording ? Icons.stop : Icons.mic,
                  color: Colors.black,
                  size: 36,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _sttService.isRecording
                  ? 'Recording 16kHz WAV (Tap to Stop)'
                  : 'Tap to Record Lecture',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _sttService.isRecording
                    ? AppTheme.redAccent
                    : AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
