import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class AgentVoiceOverlay extends StatefulWidget {
  final bool isListening;
  final bool isTranscribing;
  final String? liveTranscript;
  final VoidCallback? onCancel;

  const AgentVoiceOverlay({
    super.key,
    required this.isListening,
    this.isTranscribing = false,
    this.liveTranscript,
    this.onCancel,
  });

  @override
  State<AgentVoiceOverlay> createState() => _AgentVoiceOverlayState();
}

class _AgentVoiceOverlayState extends State<AgentVoiceOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isListening && !widget.isTranscribing) {
      return const SizedBox.shrink();
    }

    final liveWords = widget.liveTranscript?.trim() ?? '';

    return Material(
      color: Colors.black.withValues(alpha: 0.75),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top header
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AppTheme.primaryAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Pal',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Neutral voice recognition badge (never claiming 100% offline for Hold Pal)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppTheme.primaryAccent.withValues(alpha: 0.35),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: AppTheme.primaryAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'Voice recognition',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFD4AF37),
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),

                // Pulsing audio waveform visualizer
                AnimatedBuilder(
                  animation: _animController,
                  builder: (context, child) {
                    return SizedBox(
                      width: 140,
                      height: 140,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Outer ripple ring
                          Container(
                            width: 80 + (_animController.value * 50),
                            height: 80 + (_animController.value * 50),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppTheme.primaryAccent.withValues(
                                  alpha: (1.0 - _animController.value) * 0.4,
                                ),
                                width: 2,
                              ),
                            ),
                          ),
                          // Secondary ripple ring
                          Container(
                            width: 60 +
                                (((_animController.value + 0.5) % 1.0) * 40),
                            height: 60 +
                                (((_animController.value + 0.5) % 1.0) * 40),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppTheme.primaryAccent.withValues(
                                  alpha: (1.0 -
                                          ((_animController.value + 0.5) %
                                              1.0)) *
                                      0.3,
                                ),
                                width: 1.5,
                              ),
                            ),
                          ),
                          // Center glowing circle
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E1D19),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppTheme.primaryAccent,
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.primaryAccent
                                      .withValues(alpha: 0.35),
                                  blurRadius: 18,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: Center(
                              child: widget.isTranscribing
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                          AppTheme.primaryAccent,
                                        ),
                                      ),
                                    )
                                  : const Text(
                                      '✦',
                                      style: TextStyle(
                                        color: AppTheme.primaryAccent,
                                        fontSize: 34,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 28),

                // Dynamic subtle waveform bar indicators
                if (widget.isListening)
                  AnimatedBuilder(
                    animation: _animController,
                    builder: (context, child) {
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(5, (index) {
                          final wave = math.sin(
                              (_animController.value * 2 * math.pi) +
                                  (index * 0.8));
                          final height = 10.0 + (wave.abs() * 16.0);
                          return Container(
                            margin: const EdgeInsets.symmetric(horizontal: 2.5),
                            width: 3.5,
                            height: height,
                            decoration: BoxDecoration(
                              color: AppTheme.primaryAccent.withValues(
                                alpha: 0.6 + (wave.abs() * 0.4),
                              ),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          );
                        }),
                      );
                    },
                  ),
                const SizedBox(height: 20),

                // Main Status Text
                Text(
                  widget.isTranscribing ? 'Processing...' : 'Listening...',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 12),

                // Live transcript or prompt hint
                Container(
                  constraints: const BoxConstraints(maxWidth: 320),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: liveWords.isNotEmpty
                          ? AppTheme.primaryAccent.withValues(alpha: 0.4)
                          : Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                  child: liveWords.isNotEmpty
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'YOU SAID',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.primaryAccent,
                                letterSpacing: 1.0,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '"$liveWords"',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFFAF8F5),
                                height: 1.3,
                              ),
                            ),
                          ],
                        )
                      : const Text(
                          '"Add AI tomorrow at 10"',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            fontStyle: FontStyle.italic,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFFE6E3D8),
                          ),
                        ),
                ),

                const SizedBox(height: 14),

                // Subtitle Instruction
                Text(
                  widget.isTranscribing
                      ? 'Understanding your request...'
                      : 'Release when finished',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFFC7C3B7),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
