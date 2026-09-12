import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/lecture_recording.dart';
import '../services/lecture_recording_service.dart';
import '../theme/app_theme.dart';
import 'pal_brain_screen.dart';

class LectureDetailsScreen extends StatefulWidget {
  final LectureRecording recording;

  const LectureDetailsScreen({
    super.key,
    required this.recording,
  });

  @override
  State<LectureDetailsScreen> createState() => _LectureDetailsScreenState();
}

class _LectureDetailsScreenState extends State<LectureDetailsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late LectureRecording _currentRecording;

  late AudioPlayer _audioPlayer;
  PlayerState _playerState = PlayerState.stopped;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  StreamSubscription? _playerStateSub;
  StreamSubscription? _positionSub;
  StreamSubscription? _durationSub;
  StreamSubscription? _playerCompleteSub;

  bool get _isPlaying => _playerState == PlayerState.playing;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _currentRecording = widget.recording;

    _initAudioPlayer();

    // Listen to service updates for async transcription/summary
    LectureRecordingService.instance.addListener(_onServiceUpdate);
  }

  void _initAudioPlayer() {
    _audioPlayer = AudioPlayer();
    _duration = Duration(seconds: _currentRecording.durationSeconds);

    _playerStateSub = _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _playerState = state);
    });

    _positionSub = _audioPlayer.onPositionChanged.listen((pos) {
      if (mounted) setState(() => _position = pos);
    });

    _durationSub = _audioPlayer.onDurationChanged.listen((dur) {
      if (dur.inSeconds > 0 && mounted) {
        setState(() => _duration = dur);
      }
    });

    _playerCompleteSub = _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _position = Duration.zero;
          _playerState = PlayerState.stopped;
        });
      }
    });
  }

  void _onServiceUpdate() {
    final updated = LectureRecordingService.instance.recordings.firstWhere(
      (r) => r.id == widget.recording.id,
      orElse: () => _currentRecording,
    );
    if (mounted && updated != _currentRecording) {
      setState(() {
        _currentRecording = updated;
        if (_duration.inSeconds == 0 && updated.durationSeconds > 0) {
          _duration = Duration(seconds: updated.durationSeconds);
        }
      });
    }
  }

  @override
  void dispose() {
    LectureRecordingService.instance.removeListener(_onServiceUpdate);
    _playerStateSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _playerCompleteSub?.cancel();
    _audioPlayer.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _togglePlayPause() async {
    final file = File(_currentRecording.audioPath);
    if (!file.existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.cardSurface,
          content: Text(
            'Audio file not found at: ${_currentRecording.audioPath}',
            style: const TextStyle(color: AppTheme.overduePillText),
          ),
        ),
      );
      return;
    }

    try {
      if (_isPlaying) {
        await _audioPlayer.pause();
      } else {
        debugPrint('[PLAYBACK] audio path: ${_currentRecording.audioPath}');
        await _audioPlayer.play(DeviceFileSource(_currentRecording.audioPath));
      }
    } catch (e) {
      debugPrint('[PLAYBACK] Playback error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Playback failed: $e')),
        );
      }
    }
  }

  Future<void> _seekAudio(Duration position) async {
    try {
      await _audioPlayer.seek(position);
    } catch (e) {
      debugPrint('[PLAYBACK] Seek error: $e');
    }
  }

  Future<void> _seekToTimestamp(String timestamp) async {
    final parts = timestamp.split(':');
    int seconds = 0;
    if (parts.length == 2) {
      final m = int.tryParse(parts[0]) ?? 0;
      final s = int.tryParse(parts[1]) ?? 0;
      seconds = m * 60 + s;
    } else if (parts.length == 3) {
      final h = int.tryParse(parts[0]) ?? 0;
      final m = int.tryParse(parts[1]) ?? 0;
      final s = int.tryParse(parts[2]) ?? 0;
      seconds = h * 3600 + m * 60 + s;
    }

    final target = Duration(seconds: seconds);
    await _seekAudio(target);
    if (!_isPlaying) {
      await _togglePlayPause();
    }
  }

  String _formatPlayerDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes % 60;
    final seconds = d.inSeconds % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _currentRecording.subject,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            Text(
              '${_currentRecording.scheduledStart} - ${_currentRecording.scheduledEnd} • ${_currentRecording.formattedDuration}',
              style: const TextStyle(
                fontSize: 11,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon:
                const Icon(Icons.delete_outline, color: AppTheme.textSecondary),
            tooltip: 'Delete Lecture',
            onPressed: _confirmDelete,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.primaryAccent,
          indicatorWeight: 2,
          labelColor: AppTheme.primaryAccent,
          unselectedLabelColor: AppTheme.textSecondary,
          labelStyle:
              const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Transcript'),
            Tab(text: 'Summary'),
            Tab(text: 'Deadlines'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOverviewTab(),
          _buildTranscriptTab(),
          _buildSummaryTab(),
          _buildDeadlinesTab(),
        ],
      ),
    );
  }

  Widget _buildAudioPlayerCard() {
    final maxSec = _duration.inSeconds > 0
        ? _duration.inSeconds
        : (_currentRecording.durationSeconds > 0
            ? _currentRecording.durationSeconds
            : 1);
    final curSec = _position.inSeconds.clamp(0, maxSec);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InkWell(
                onTap: _togglePlayPause,
                borderRadius: BorderRadius.circular(24),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: AppTheme.primaryAccent,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _currentRecording.subject,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_formatDate(_currentRecording.date)} · ${_currentRecording.scheduledStart}  •  ${_currentRecording.formattedFileSize}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.replay_10,
                    size: 22, color: AppTheme.textSecondary),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'Rewind 10s',
                onPressed: () {
                  final newPos = _position - const Duration(seconds: 10);
                  _seekAudio(newPos < Duration.zero ? Duration.zero : newPos);
                },
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.forward_10,
                    size: 22, color: AppTheme.textSecondary),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'Forward 10s',
                onPressed: () {
                  final newPos = _position + const Duration(seconds: 10);
                  _seekAudio(newPos > _duration ? _duration : newPos);
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              activeTrackColor: AppTheme.primaryAccent,
              inactiveTrackColor: AppTheme.cardBorder,
              thumbColor: AppTheme.primaryAccent,
            ),
            child: Slider(
              value: curSec.toDouble(),
              min: 0,
              max: maxSec.toDouble(),
              onChanged: (val) {
                _seekAudio(Duration(seconds: val.toInt()));
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatPlayerDuration(_position),
                  style: const TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                  ),
                ),
                Text(
                  _formatPlayerDuration(Duration(seconds: maxSec)),
                  style: const TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewTab() {
    final isCompleted = _currentRecording.transcriptionStatus == 'completed';
    final isTranscribing =
        _currentRecording.transcriptionStatus == 'transcribing';
    final isFailed = _currentRecording.transcriptionStatus == 'failed';

    final statusBg = isCompleted
        ? AppTheme.trustPillFill
        : (isFailed
            ? AppTheme.overduePillFill
            : (isTranscribing
                ? AppTheme.detectedPillFill
                : AppTheme.neutralPillFill));
    final statusFg = isCompleted
        ? AppTheme.trustPillText
        : (isFailed
            ? AppTheme.overduePillText
            : (isTranscribing
                ? AppTheme.primaryAccent
                : AppTheme.textSecondary));

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Top status card
        Container(
          padding: const EdgeInsets.all(18),
          decoration: AppTheme.cardDecoration,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      isFailed
                          ? 'TRANSCRIPTION FAILED'
                          : _currentRecording.transcriptionStatus.toUpperCase(),
                      style: TextStyle(
                        color: statusFg,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  Text(
                    _currentRecording.formattedDuration,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                _currentRecording.subject,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Recorded on ${_formatDate(_currentRecording.date)}  •  ${_currentRecording.scheduledStart} - ${_currentRecording.scheduledEnd}',
                style: const TextStyle(
                    fontSize: 13, color: AppTheme.textSecondary),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Audio Player Card
        _buildAudioPlayerCard(),

        const SizedBox(height: 16),

        // Transcription Action Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: AppTheme.cardDecoration,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Transcription & Notes',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                isCompleted
                    ? 'Transcribed with Whisper Tiny ONNX on-device. Key concepts and deadlines extracted.'
                    : (isTranscribing
                        ? 'Whisper ONNX is processing 25-second audio chunks...'
                        : (isFailed
                            ? 'Failed to transcribe recording. You can verify audio playback and try again.'
                            : 'This recording has not been transcribed yet.')),
                style: const TextStyle(
                    fontSize: 12, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 14),
              if (isTranscribing)
                const Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppTheme.primaryAccent),
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Transcribing locally...',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primaryAccent,
                      ),
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: () {
                        LectureRecordingService.instance.transcribeLecture(
                          _currentRecording.id,
                          forceRetry: true,
                        );
                      },
                      icon: Icon(
                        isCompleted
                            ? Icons.refresh
                            : Icons.text_snippet_outlined,
                        size: 16,
                        color: Colors.white,
                      ),
                      label: Text(
                        isCompleted
                            ? 'Transcribe Again'
                            : (isFailed ? 'Try Again' : 'Transcribe'),
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryAccent,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PalBrainScreen(
                              initialQuery:
                                  'Summarize the ${_currentRecording.subject} lecture and clarify key points.',
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.psychology_outlined,
                          size: 16, color: AppTheme.primaryAccent),
                      label: const Text(
                        'Ask Pal',
                        style: TextStyle(
                            color: AppTheme.primaryAccent,
                            fontWeight: FontWeight.w600),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppTheme.primaryAccent),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Quick Stats row
        Row(
          children: [
            Expanded(
              child: _buildMetricTile(
                title: 'Chunks',
                value: '${_currentRecording.chunks.length}',
                subtitle: '25s segments',
                icon: Icons.graphic_eq,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricTile(
                title: 'Deadlines',
                value: '${_currentRecording.extractedDeadlineIds.length}',
                subtitle: 'Spoken detected',
                icon: Icons.alarm,
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),

        // Audio & Privacy badge
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.trustPillFill,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: AppTheme.trustPillText.withValues(alpha: 0.2)),
          ),
          child: const Row(
            children: [
              Icon(Icons.lock_outline, size: 20, color: AppTheme.trustPillText),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'This recording and transcript are stored 100% on your device and will never be synced to the cloud.',
                  style: TextStyle(
                      fontSize: 12, color: AppTheme.trustPillText, height: 1.3),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMetricTile({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.textSecondary)),
              Icon(icon, size: 16, color: AppTheme.primaryAccent),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(subtitle,
              style:
                  const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildTranscriptTab() {
    if (_currentRecording.transcriptionStatus == 'transcribing') {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: AppTheme.primaryAccent),
            SizedBox(height: 16),
            Text(
              'Transcribing lecture with Whisper ONNX...',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
          ],
        ),
      );
    }

    if (_currentRecording.transcriptionStatus == 'failed') {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline,
                  size: 48, color: AppTheme.overduePillText),
              const SizedBox(height: 16),
              const Text(
                "Couldn't transcribe this recording.",
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 8),
              const Text(
                'The audio could not be processed by Whisper ONNX. Check audio playback to verify your recording.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: _togglePlayPause,
                    icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow,
                        size: 16),
                    label: Text(_isPlaying ? 'Pause' : 'Play Recording'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryAccent,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: () {
                      LectureRecordingService.instance.transcribeLecture(
                        _currentRecording.id,
                        forceRetry: true,
                      );
                    },
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Try Again'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primaryAccent,
                      side: const BorderSide(color: AppTheme.primaryAccent),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    if (_currentRecording.chunks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.description_outlined,
                  size: 48, color: AppTheme.textSecondary),
              const SizedBox(height: 16),
              const Text(
                'No Transcript Yet',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                _currentRecording.transcriptText.isNotEmpty
                    ? _currentRecording.transcriptText
                    : 'Transcribe this lecture to generate searchable notes.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () {
                  LectureRecordingService.instance.transcribeLecture(
                    _currentRecording.id,
                    forceRetry: true,
                  );
                },
                icon: const Icon(Icons.text_snippet_outlined,
                    size: 16, color: Colors.white),
                label: const Text('Transcribe',
                    style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryAccent),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        // Mini player toolbar at top of transcript
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.cardSurface,
            border: Border(bottom: BorderSide(color: AppTheme.cardBorder)),
          ),
          child: Row(
            children: [
              InkWell(
                onTap: _togglePlayPause,
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: const BoxDecoration(
                    color: AppTheme.primaryAccent,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                _isPlaying ? 'Playing' : 'Paused',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${_formatPlayerDuration(_position)} / ${_formatPlayerDuration(_duration)}',
                style: const TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: AppTheme.textSecondary,
                ),
              ),
              const Spacer(),
              const Text(
                'Tap timestamp to seek',
                style: TextStyle(
                  fontSize: 11,
                  color: AppTheme.textInactive,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: _currentRecording.chunks.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final chunk = _currentRecording.chunks[index];
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: AppTheme.cardDecoration,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Clickable timestamp chip that seeks audio player
                        InkWell(
                          onTap: () => _seekToTimestamp(chunk.startTimestamp),
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppTheme.detectedPillFill,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.play_circle_outline,
                                    size: 14, color: AppTheme.primaryAccent),
                                const SizedBox(width: 5),
                                Text(
                                  '${chunk.startTimestamp} - ${chunk.endTimestamp}',
                                  style: const TextStyle(
                                    color: AppTheme.primaryAccent,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy,
                              size: 16, color: AppTheme.textSecondary),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          tooltip: 'Copy text',
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: chunk.text));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content:
                                      Text('Chunk text copied to clipboard')),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      chunk.text,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppTheme.textPrimary,
                        height: 1.45,
                        fontFamily: 'serif',
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryTab() {
    final summary = _currentRecording.summary;

    if (_currentRecording.summaryStatus == 'generating') {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: AppTheme.primaryAccent),
            SizedBox(height: 16),
            Text(
              'Generating academic summary & key points...',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
          ],
        ),
      );
    }

    if (summary == null) {
      return const Center(
        child: Text(
          'Summary not generated yet.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (summary.keyPoints.isNotEmpty) ...[
          _buildSummarySection(
            title: 'Key Takeaways',
            icon: Icons.lightbulb_outline,
            items: summary.keyPoints,
          ),
          const SizedBox(height: 16),
        ],
        if (summary.importantConcepts.isNotEmpty) ...[
          _buildSummarySection(
            title: 'Important Concepts',
            icon: Icons.menu_book_outlined,
            items: summary.importantConcepts,
          ),
          const SizedBox(height: 16),
        ],
        if (summary.actionItems.isNotEmpty) ...[
          _buildSummarySection(
            title: 'Action Items & Homework',
            icon: Icons.check_box_outlined,
            items: summary.actionItems,
          ),
          const SizedBox(height: 16),
        ],
        if (summary.reviewQuestions.isNotEmpty) ...[
          _buildSummarySection(
            title: 'Self-Review Questions',
            icon: Icons.help_outline,
            items: summary.reviewQuestions,
          ),
        ],
      ],
    );
  }

  Widget _buildSummarySection({
    required String title,
    required IconData icon,
    required List<String> items,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppTheme.primaryAccent),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('• ',
                      style: TextStyle(
                          color: AppTheme.primaryAccent, fontSize: 16)),
                  Expanded(
                    child: Text(
                      item,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.textPrimary,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeadlinesTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: AppTheme.cardDecoration,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.alarm, size: 18, color: AppTheme.primaryAccent),
                  SizedBox(width: 8),
                  Text(
                    'Extracted Spoken Deadlines',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_currentRecording.extractedDeadlineIds.isEmpty)
                const Text(
                  'No spoken deadlines were detected in this lecture.',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                )
              else
                ..._currentRecording.extractedDeadlineIds.map(
                  (id) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_outline,
                            size: 16, color: AppTheme.trustPillText),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Deadline ID: $id (Added to Tasks)',
                            style: const TextStyle(
                                color: AppTheme.textPrimary, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardSurface,
        title: const Text('Delete Lecture?',
            style: TextStyle(color: AppTheme.textPrimary)),
        content: const Text(
          'This will permanently remove the audio, transcript, and summary from this device.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              LectureRecordingService.instance
                  .deleteRecording(_currentRecording.id);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.overduePillText),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.month}/${dt.day}/${dt.year}';
  }
}
