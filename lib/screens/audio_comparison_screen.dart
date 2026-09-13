import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/lecture_recording.dart';
import '../services/audio_comparison_service.dart';
import '../services/audio_noise_processor.dart';
import '../theme/app_theme.dart';

class AudioComparisonScreen extends StatefulWidget {
  final LectureRecording recording;
  final AudioComparisonResult? initialResult;
  final AudioPlayer? playerOrig;
  final AudioPlayer? playerProc;
  final bool enablePlayers;

  const AudioComparisonScreen({
    super.key,
    required this.recording,
    this.initialResult,
    this.playerOrig,
    this.playerProc,
    this.enablePlayers = true,
  });

  @override
  State<AudioComparisonScreen> createState() => _AudioComparisonScreenState();
}

class _AudioComparisonScreenState extends State<AudioComparisonScreen> {
  // Config & State
  DspConfig _selectedConfig = DspConfig.full;
  bool _isLoading = false;
  String? _errorMessage;
  AudioComparisonResult? _comparisonResult;

  // Audio Players
  AudioPlayer? _playerOrig;
  AudioPlayer? _playerProc;

  PlayerState _stateOrig = PlayerState.stopped;
  PlayerState _stateProc = PlayerState.stopped;

  Duration _posOrig = Duration.zero;
  Duration _durOrig = Duration.zero;

  Duration _posProc = Duration.zero;
  Duration _durProc = Duration.zero;

  StreamSubscription? _origStateSub;
  StreamSubscription? _origPosSub;
  StreamSubscription? _origDurSub;

  StreamSubscription? _procStateSub;
  StreamSubscription? _procPosSub;
  StreamSubscription? _procDurSub;

  @override
  void initState() {
    super.initState();
    _initPlayers();
    if (widget.initialResult != null) {
      _comparisonResult = widget.initialResult;
      _selectedConfig = widget.initialResult!.dspConfig;
      _isLoading = false;
    } else {
      _runComparison();
    }
  }

  void _initPlayers() {
    if (!widget.enablePlayers) return;
    final orig = widget.playerOrig ?? AudioPlayer(playerId: 'ab_player_orig');
    final proc = widget.playerProc ?? AudioPlayer(playerId: 'ab_player_proc');
    _playerOrig = orig;
    _playerProc = proc;

    _origStateSub = orig.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _stateOrig = s);
    });
    _origPosSub = orig.onPositionChanged.listen((p) {
      if (mounted) setState(() => _posOrig = p);
    });
    _origDurSub = orig.onDurationChanged.listen((d) {
      if (mounted && d.inSeconds > 0) setState(() => _durOrig = d);
    });

    _procStateSub = proc.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _stateProc = s);
    });
    _procPosSub = proc.onPositionChanged.listen((p) {
      if (mounted) setState(() => _posProc = p);
    });
    _procDurSub = proc.onDurationChanged.listen((d) {
      if (mounted && d.inSeconds > 0) setState(() => _durProc = d);
    });
  }

  @override
  void dispose() {
    _origStateSub?.cancel();
    _origPosSub?.cancel();
    _origDurSub?.cancel();
    _procStateSub?.cancel();
    _procPosSub?.cancel();
    _procDurSub?.cancel();

    _playerOrig?.dispose();
    _playerProc?.dispose();

    // Clean up temporary processed WAV if created
    final tempPath = _comparisonResult?.processedAudioPath;
    if (tempPath != null) {
      try {
        final f = File(tempPath);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
    super.dispose();
  }

  Future<void> _playOriginal() async {
    final orig = _playerOrig;
    if (orig == null) return;
    await _playerProc?.pause();
    final path = widget.recording.audioPath;
    if (!File(path).existsSync()) return;

    if (_stateOrig == PlayerState.playing) {
      await orig.pause();
    } else {
      await orig.play(DeviceFileSource(path));
    }
  }

  Future<void> _playProcessed() async {
    final proc = _playerProc;
    if (proc == null) return;
    await _playerOrig?.pause();
    final path = _comparisonResult?.processedAudioPath;
    if (path == null || !File(path).existsSync()) return;

    if (_stateProc == PlayerState.playing) {
      await proc.pause();
    } else {
      await proc.play(DeviceFileSource(path));
    }
  }

  Future<void> _runComparison() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await AudioComparisonService.instance.runComparison(
        originalAudioPath: widget.recording.audioPath,
        recordingId: widget.recording.id,
        config: _selectedConfig,
        runStt: true,
      );

      if (mounted) {
        setState(() {
          _comparisonResult = result;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
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
            const Text(
              'Audio A/B Comparison',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            Text(
              widget.recording.displayTitle,
              style: const TextStyle(
                fontSize: 11,
                color: AppTheme.textSecondary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppTheme.primaryAccent),
            tooltip: 'Rerun Comparison',
            onPressed: _isLoading ? null : _runComparison,
          ),
        ],
      ),
      body: _isLoading
          ? _buildLoadingView()
          : _errorMessage != null
              ? _buildErrorView()
              : _buildContentView(),
    );
  }

  Widget _buildLoadingView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(
            color: AppTheme.primaryAccent,
            strokeWidth: 3,
          ),
          const SizedBox(height: 20),
          const Text(
            'Running Audio A/B Comparison...',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Path A: Original Audio -> Whisper Tiny\nPath B: Pal DSP -> Processed Audio -> Whisper Tiny',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary.withValues(alpha: 0.9),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline,
                size: 48, color: AppTheme.overduePillText),
            const SizedBox(height: 16),
            const Text(
              'A/B Comparison Failed',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? 'Unknown error occurred.',
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _runComparison,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryAccent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContentView() {
    final result = _comparisonResult!;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildInfoBanner(),
        const SizedBox(height: 16),
        _buildPresetSelector(),
        const SizedBox(height: 16),
        _buildDualAudioPlayer(result),
        const SizedBox(height: 16),
        _buildMetricsCard(result),
        const SizedBox(height: 16),
        _buildWordDiffCard(result),
        const SizedBox(height: 16),
        _buildTranscriptsComparison(result),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildInfoBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline,
              size: 20, color: AppTheme.primaryAccent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Deterministic A/B Audio Pipeline',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '• Recorded Audio: 16kHz Mono WAV captured with device hardware flags\n'
                  '• Recorded Audio + Pal DSP: Identical input with software DC offset removal, '
                  '2nd-order high-pass, gentle expander & conservative normalization\n'
                  '• Original audio is NEVER overwritten or mutated.',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary.withValues(alpha: 0.9),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetSelector() {
    final presets = [
      ('Preset G (Full)', DspConfig.full),
      ('Preset A (Bypass)', DspConfig.bypass),
      ('Preset B (HPF 80Hz)', DspConfig.highPassOnly),
      ('Preset C (Gate Only)', DspConfig.noiseGateOnly),
      ('Preset D (Norm Only)', DspConfig.normalizationOnly),
      ('Preset E (HPF+Gate)', DspConfig.highPassAndGate),
      ('Preset F (HPF+Norm)', DspConfig.highPassAndNorm),
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'DSP Test Presets',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _selectedConfig.label,
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primaryAccent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: presets.map((item) {
                final isSelected = _selectedConfig.label == item.$2.label;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(
                      item.$1,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w500,
                        color:
                            isSelected ? Colors.white : AppTheme.textSecondary,
                      ),
                    ),
                    selected: isSelected,
                    selectedColor: AppTheme.primaryAccent,
                    backgroundColor: AppTheme.canvasBg,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(
                        color: isSelected
                            ? AppTheme.primaryAccent
                            : AppTheme.cardBorder,
                      ),
                    ),
                    onSelected: (val) {
                      if (val) {
                        setState(() => _selectedConfig = item.$2);
                        _runComparison();
                      }
                    },
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDualAudioPlayer(AudioComparisonResult result) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Auditory A/B Comparison',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Listen directly to the exact audio waveforms fed into Whisper Tiny.',
            style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 16),

          // Player A: Recorded Audio
          _buildPlayerRow(
            title: 'Path A: Recorded Audio',
            subtitle: 'Direct hardware-recorded WAV',
            isPlaying: _stateOrig == PlayerState.playing,
            position: _posOrig,
            duration: _durOrig.inSeconds > 0
                ? _durOrig
                : Duration(seconds: result.durationSeconds.round()),
            onPlayPause: _playOriginal,
            onSeek: (pos) => _playerOrig?.seek(pos),
            accentColor: Colors.blueAccent,
          ),

          const Divider(height: 28, color: AppTheme.cardBorder),

          // Player B: Recorded Audio + Pal DSP
          _buildPlayerRow(
            title: 'Path B: Recorded Audio + Pal DSP',
            subtitle: 'Cleaned with ${result.dspConfig.label}',
            isPlaying: _stateProc == PlayerState.playing,
            position: _posProc,
            duration: _durProc.inSeconds > 0
                ? _durProc
                : Duration(seconds: result.durationSeconds.round()),
            onPlayPause: _playProcessed,
            onSeek: (pos) => _playerProc?.seek(pos),
            accentColor: AppTheme.primaryAccent,
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerRow({
    required String title,
    required String subtitle,
    required bool isPlaying,
    required Duration position,
    required Duration duration,
    required VoidCallback onPlayPause,
    required ValueChanged<Duration> onSeek,
    required Color accentColor,
  }) {
    final maxSec = duration.inSeconds > 0 ? duration.inSeconds : 1;
    final curSec = position.inSeconds.clamp(0, maxSec);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            InkWell(
              onTap: onPlayPause,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accentColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.replay_10,
                  size: 20, color: AppTheme.textSecondary),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () {
                final p = position - const Duration(seconds: 10);
                onSeek(p < Duration.zero ? Duration.zero : p);
              },
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.forward_10,
                  size: 20, color: AppTheme.textSecondary),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () {
                final p = position + const Duration(seconds: 10);
                onSeek(p > duration ? duration : p);
              },
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2.5,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
            activeTrackColor: accentColor,
            inactiveTrackColor: AppTheme.cardBorder,
            thumbColor: accentColor,
          ),
          child: Slider(
            value: curSec.toDouble(),
            min: 0,
            max: maxSec.toDouble(),
            onChanged: (val) => onSeek(Duration(seconds: val.toInt())),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(position),
                style: const TextStyle(
                  fontSize: 10,
                  fontFamily: 'monospace',
                  color: AppTheme.textSecondary,
                ),
              ),
              Text(
                _formatDuration(duration),
                style: const TextStyle(
                  fontSize: 10,
                  fontFamily: 'monospace',
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMetricsCard(AudioComparisonResult result) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text(
                  'A/B Signal Metrics',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: result.validation.isValid
                      ? AppTheme.trustPillFill
                      : AppTheme.overduePillFill,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  result.validation.isValid
                      ? 'DSP VALIDATED'
                      : 'VALIDATION ERROR',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: result.validation.isValid
                        ? AppTheme.trustPillText
                        : AppTheme.overduePillText,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Table(
            border: TableBorder.all(
              color: AppTheme.cardBorder,
              width: 0.5,
              borderRadius: BorderRadius.circular(8),
            ),
            children: [
              _buildTableHeader('Metric', 'Recorded', 'Processed', 'Delta'),
              _buildTableRow(
                'RMS',
                '${result.originalMetrics.rms.toStringAsFixed(3)} (${result.originalMetrics.rmsDbFs.toStringAsFixed(1)} dB)',
                '${result.processedMetrics.rms.toStringAsFixed(3)} (${result.processedMetrics.rmsDbFs.toStringAsFixed(1)} dB)',
                '${result.rmsChangeDb >= 0 ? '+' : ''}${result.rmsChangeDb.toStringAsFixed(1)} dB',
              ),
              _buildTableRow(
                'Peak',
                '${result.originalMetrics.peak.toStringAsFixed(3)} (${result.originalMetrics.peakDbFs.toStringAsFixed(1)} dB)',
                '${result.processedMetrics.peak.toStringAsFixed(3)} (${result.processedMetrics.peakDbFs.toStringAsFixed(1)} dB)',
                '${result.peakChangeDb >= 0 ? '+' : ''}${result.peakChangeDb.toStringAsFixed(1)} dB',
              ),
              _buildTableRow(
                'DC Offset',
                result.originalMetrics.dcOffset.toStringAsFixed(5),
                result.processedMetrics.dcOffset.toStringAsFixed(5),
                (result.processedMetrics.dcOffset.abs() -
                        result.originalMetrics.dcOffset.abs())
                    .toStringAsFixed(5),
              ),
              _buildTableRow(
                'Duration',
                '${result.durationSeconds.toStringAsFixed(1)}s',
                '${result.durationSeconds.toStringAsFixed(1)}s',
                '0.0s (Identical)',
              ),
              _buildTableRow(
                'Sample Rate',
                '${result.sampleRate} Hz',
                '${result.sampleRate} Hz',
                'Match',
              ),
              _buildTableRow(
                'Sample Count',
                '${result.sampleCount}',
                '${result.sampleCount}',
                'Match',
              ),
              _buildTableRow(
                'Execution',
                'STT: ${result.originalSttElapsedMs}ms',
                'DSP: ${result.dspElapsedMs}ms\nSTT: ${result.processedSttElapsedMs}ms',
                '${result.processedSttElapsedMs - result.originalSttElapsedMs >= 0 ? '+' : ''}${result.processedSttElapsedMs - result.originalSttElapsedMs}ms',
              ),
            ],
          ),
        ],
      ),
    );
  }

  TableRow _buildTableHeader(
      String col1, String col2, String col3, String col4) {
    return TableRow(
      decoration: const BoxDecoration(color: AppTheme.cardSurface),
      children: [
        _buildTableCell(col1, isHeader: true),
        _buildTableCell(col2, isHeader: true),
        _buildTableCell(col3, isHeader: true),
        _buildTableCell(col4, isHeader: true),
      ],
    );
  }

  TableRow _buildTableRow(String col1, String col2, String col3, String col4) {
    return TableRow(
      children: [
        _buildTableCell(col1, isLabel: true),
        _buildTableCell(col2),
        _buildTableCell(col3),
        _buildTableCell(col4),
      ],
    );
  }

  Widget _buildTableCell(String text,
      {bool isHeader = false, bool isLabel = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: isHeader
              ? FontWeight.w700
              : (isLabel ? FontWeight.w600 : FontWeight.w400),
          color: isHeader
              ? AppTheme.primaryAccent
              : (isLabel ? AppTheme.textPrimary : AppTheme.textSecondary),
        ),
      ),
    );
  }

  Widget _buildWordDiffCard(AudioComparisonResult result) {
    final diff = result.wordDiff;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text(
                  'Deterministic Word Diff',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.canvasBg,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppTheme.cardBorder),
                ),
                child: Text(
                  'Overlap: ${(diff.similarityScore * 100).toStringAsFixed(1)}%',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryAccent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Objective token difference between Path A and Path B (zero LLM inference).',
            style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildMetricTile(
                  'Original Words',
                  '${diff.originalWordCount}',
                  Colors.blueAccent,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricTile(
                  'Processed Words',
                  '${diff.processedWordCount}',
                  AppTheme.primaryAccent,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricTile(
                  'Common Words',
                  '${diff.commonWords.length}',
                  AppTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (diff.uniqueToOriginal.isNotEmpty) ...[
            const Text(
              'Words Unique to Recorded Audio (Path A):',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.blueAccent,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: diff.uniqueToOriginal.map((w) {
                return Chip(
                  label: Text(w, style: const TextStyle(fontSize: 10)),
                  backgroundColor: Colors.blueAccent.withValues(alpha: 0.15),
                  padding: EdgeInsets.zero,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6)),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
          ],
          if (diff.uniqueToProcessed.isNotEmpty) ...[
            const Text(
              'Words Unique to Processed Audio (Path B):',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppTheme.primaryAccent,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: diff.uniqueToProcessed.map((w) {
                return Chip(
                  label: Text(w, style: const TextStyle(fontSize: 10)),
                  backgroundColor:
                      AppTheme.primaryAccent.withValues(alpha: 0.15),
                  padding: EdgeInsets.zero,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6)),
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
          ],
          if (diff.areIdentical)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.trustPillFill,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_circle_outline,
                      size: 16, color: AppTheme.trustPillText),
                  SizedBox(width: 8),
                  Text(
                    'Transcriptions are 100% identical in word content.',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.trustPillText,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMetricTile(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 9,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTranscriptsComparison(AudioComparisonResult result) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Transcription Outputs',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 12),

          // Path A
          _buildTranscriptCard(
            label: 'Path A: Recorded Audio',
            transcript: result.originalTranscript,
            color: Colors.blueAccent,
          ),

          const SizedBox(height: 12),

          // Path B
          _buildTranscriptCard(
            label: 'Path B: Recorded Audio + Pal DSP',
            transcript: result.processedTranscript,
            color: AppTheme.primaryAccent,
          ),
        ],
      ),
    );
  }

  Widget _buildTranscriptCard({
    required String label,
    required String transcript,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.canvasBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy,
                    size: 14, color: AppTheme.textSecondary),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'Copy Transcript',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: transcript));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Copied transcript to clipboard'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            transcript.isNotEmpty ? transcript : 'No speech detected.',
            style: const TextStyle(
              fontSize: 12,
              height: 1.5,
              color: AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
