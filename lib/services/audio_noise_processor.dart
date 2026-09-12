import 'dart:math' as math;
import 'package:flutter/foundation.dart';

class AudioMetrics {
  final double rms;
  final double peak;
  final double dcOffset;
  final int sampleCount;

  const AudioMetrics({
    required this.rms,
    required this.peak,
    required this.dcOffset,
    required this.sampleCount,
  });

  double get rmsDbFs => rms > 0 ? 20.0 * (math.log(rms) / math.ln10) : -100.0;
  double get peakDbFs =>
      peak > 0 ? 20.0 * (math.log(peak) / math.ln10) : -100.0;

  @override
  String toString() =>
      'RMS: ${rms.toStringAsFixed(4)} (${rmsDbFs.toStringAsFixed(1)} dBFS), '
      'Peak: ${peak.toStringAsFixed(4)} (${peakDbFs.toStringAsFixed(1)} dBFS), '
      'DC: ${dcOffset.toStringAsFixed(5)}';
}

/// High-performance, on-device audio DSP preprocessor for Pal lecture transcription.
///
/// Prepares a temporary, preprocessed audio waveform for Whisper Tiny INT8 speech recognition
/// while ensuring the original recorded audio file is NEVER mutated.
class AudioNoiseProcessor {
  AudioNoiseProcessor._();

  /// Default high-pass filter cutoff in Hz (attenuates HVAC hum and mechanical thumps).
  static const double defaultHighPassCutoffHz = 80.0;

  /// Target RMS amplitude for speech input to Whisper (~ -22 dBFS).
  static const double targetRms = 0.08;

  /// Maximum allowed normalization gain boost (+12 dB).
  static const double maxNormalizationGain = 4.0;

  /// Peak amplitude ceiling to prevent clipping distortion.
  static const double peakCeiling = 0.95;

  /// Downward expander threshold (~ -35 dBFS).
  static const double expanderThreshold = 0.018;

  /// Minimum attenuation floor for downward expansion (-9 dB).
  /// Guarantees that quiet speech, consonants, and word endings are NEVER gated to silence.
  static const double minExpanderGain = 0.35;

  /// Processes the [input] samples and returns a NEW [Float32List] with:
  /// 1. DC Offset Removal
  /// 2. 80 Hz 2nd-order Butterworth High-Pass Filter (IIR)
  /// 3. Soft Downward Expander (gentle noise reduction)
  /// 4. Conservative RMS/Peak Normalization
  ///
  /// The [input] array is guaranteed NOT to be modified.
  static Float32List process(
    Float32List input, {
    int sampleRate = 16000,
    double highPassCutoffHz = defaultHighPassCutoffHz,
    bool enableDcRemoval = true,
    bool enableHighPass = true,
    bool enableNoiseReduction = true,
    bool enableNormalization = true,
    bool verbose = true,
  }) {
    if (input.isEmpty) {
      return Float32List(0);
    }

    final int len = input.length;
    // Work on a dedicated clone to protect original audio
    final Float32List output = Float32List.fromList(input);

    final AudioMetrics beforeMetrics = verbose
        ? measureMetrics(output)
        : const AudioMetrics(rms: 0, peak: 0, dcOffset: 0, sampleCount: 0);

    // 1. DC Offset Removal
    if (enableDcRemoval) {
      removeDcOffset(output);
    }

    // 2. 80 Hz 2nd-Order Butterworth High-Pass Filter (IIR)
    if (enableHighPass && sampleRate > 0 && highPassCutoffHz > 0) {
      applyHighPassFilter(output,
          sampleRate: sampleRate, cutoffHz: highPassCutoffHz);
    }

    // 3. Soft Downward Expander (Conservative Noise Reduction)
    if (enableNoiseReduction && sampleRate > 0) {
      applyDownwardExpander(output, sampleRate: sampleRate);
    }

    // 4. Conservative RMS/Peak Normalization
    if (enableNormalization) {
      applyConservativeNormalization(output);
    }

    if (verbose) {
      final AudioMetrics afterMetrics = measureMetrics(output);
      debugPrint('[AUDIO DSP] Preprocessing completed:');
      debugPrint(
          '[AUDIO DSP]   Sample rate: $sampleRate Hz, Samples: $len (${(len / sampleRate).toStringAsFixed(1)}s)');
      debugPrint(
          '[AUDIO DSP]   High-pass: ${highPassCutoffHz.toStringAsFixed(0)} Hz (2nd-order Butterworth)');
      debugPrint(
          '[AUDIO DSP]   RMS:  ${beforeMetrics.rms.toStringAsFixed(4)} (${beforeMetrics.rmsDbFs.toStringAsFixed(1)} dBFS) -> ${afterMetrics.rms.toStringAsFixed(4)} (${afterMetrics.rmsDbFs.toStringAsFixed(1)} dBFS)');
      debugPrint(
          '[AUDIO DSP]   Peak: ${beforeMetrics.peak.toStringAsFixed(4)} (${beforeMetrics.peakDbFs.toStringAsFixed(1)} dBFS) -> ${afterMetrics.peak.toStringAsFixed(4)} (${afterMetrics.peakDbFs.toStringAsFixed(1)} dBFS)');
    }

    return output;
  }

  /// Calculates the mean sample value and subtracts it from every sample in-place.
  static void removeDcOffset(Float32List buffer) {
    final int len = buffer.length;
    if (len == 0) return;

    double sum = 0.0;
    for (int i = 0; i < len; i++) {
      sum += buffer[i];
    }
    final double mean = sum / len;

    // Only adjust if there is a measurable offset
    if (mean.abs() > 1e-6) {
      for (int i = 0; i < len; i++) {
        buffer[i] -= mean;
      }
    }
  }

  /// Stable 2nd-order Butterworth High-Pass Biquad filter (Direct Form II Transposed).
  ///
  /// Removes low-frequency rumble (HVAC, room air currents, table vibrations, handling noise)
  /// while keeping 100% of human speech fundamentals (> 85 Hz).
  static void applyHighPassFilter(
    Float32List buffer, {
    required int sampleRate,
    required double cutoffHz,
  }) {
    final int len = buffer.length;
    if (len == 0) return;

    // Safety clamping on cutoff frequency
    final double safeCutoff = cutoffHz.clamp(20.0, sampleRate * 0.45);
    final double omega = 2.0 * math.pi * safeCutoff / sampleRate;
    final double cosOmega = math.cos(omega);
    final double sinOmega = math.sin(omega);

    // Q = 1 / sqrt(2) for Butterworth maximally flat response
    const double q = 0.7071067811865475;
    final double alpha = sinOmega / (2.0 * q);

    final double b0 = (1.0 + cosOmega) / 2.0;
    final double b1 = -(1.0 + cosOmega);
    final double b2 = (1.0 + cosOmega) / 2.0;
    final double a0 = 1.0 + alpha;
    final double a1 = -2.0 * cosOmega;
    final double a2 = 1.0 - alpha;

    // Normalized biquad coefficients
    final double cb0 = b0 / a0;
    final double cb1 = b1 / a0;
    final double cb2 = b2 / a0;
    final double ca1 = a1 / a0;
    final double ca2 = a2 / a0;

    // Direct Form II Transposed state variables
    double d1 = 0.0;
    double d2 = 0.0;

    for (int i = 0; i < len; i++) {
      final double x = buffer[i];
      final double y = cb0 * x + d1;
      d1 = cb1 * x - ca1 * y + d2;
      d2 = cb2 * x - ca2 * y;
      buffer[i] = y;
    }
  }

  /// Soft downward expander with smooth attack (10ms) and release (150ms).
  ///
  /// Gently attenuates quiet noise floor below [expanderThreshold] without cutting to zero.
  /// Bounded to [minExpanderGain] so whispers, consonant tails, and quiet words are 100% preserved.
  static void applyDownwardExpander(
    Float32List buffer, {
    required int sampleRate,
    double threshold = expanderThreshold,
    double minGain = minExpanderGain,
  }) {
    final int len = buffer.length;
    if (len == 0) return;

    // Time constants: 10ms attack, 150ms release
    final double attackAlpha = math.exp(-1.0 / (sampleRate * 0.010));
    final double releaseAlpha = math.exp(-1.0 / (sampleRate * 0.150));

    double envelope = 0.0;

    for (int i = 0; i < len; i++) {
      final double absSample = buffer[i].abs();

      // Envelope tracking with fast attack, smooth release
      if (absSample > envelope) {
        envelope = attackAlpha * envelope + (1.0 - attackAlpha) * absSample;
      } else {
        envelope = releaseAlpha * envelope + (1.0 - releaseAlpha) * absSample;
      }

      // Compute gentle downward expansion gain
      double gain = 1.0;
      if (envelope < threshold) {
        // Smooth 1.5:1 expansion curve
        final double ratio = threshold > 0 ? (envelope / threshold) : 0.0;
        gain = math.max(minGain, math.sqrt(ratio));
      }

      buffer[i] *= gain;
    }
  }

  /// Conservative RMS and peak normalization.
  ///
  /// Scales speech to consistent loudness optimal for Whisper Tiny without amplifying
  /// empty room noise or causing digital clipping.
  static void applyConservativeNormalization(Float32List buffer) {
    final int len = buffer.length;
    if (len == 0) return;

    double sumSq = 0.0;
    double peak = 0.0;

    for (int i = 0; i < len; i++) {
      final double s = buffer[i];
      sumSq += s * s;
      final double absS = s.abs();
      if (absS > peak) peak = absS;
    }

    final double rms = math.sqrt(sumSq / len);

    // If completely silent or noise floor only, do not blow up gain
    if (rms < 0.001 || peak < 0.001) return;

    // Desired gain to reach target RMS (~ -22 dBFS)
    double gain = targetRms / rms;

    // Bound gain boost to avoid extreme amplification of background noise
    gain = gain.clamp(0.25, maxNormalizationGain);

    // Prevent any clipping beyond peak ceiling
    if (peak * gain > peakCeiling) {
      gain = peakCeiling / peak;
    }

    // Apply gain safely with final clamping
    for (int i = 0; i < len; i++) {
      final double sample = buffer[i] * gain;
      buffer[i] = sample.clamp(-peakCeiling, peakCeiling);
    }
  }

  /// Measures RMS, Peak, and DC offset metrics of the provided [samples].
  static AudioMetrics measureMetrics(Float32List samples) {
    final int len = samples.length;
    if (len == 0) {
      return const AudioMetrics(rms: 0, peak: 0, dcOffset: 0, sampleCount: 0);
    }

    double sum = 0.0;
    double sumSq = 0.0;
    double peak = 0.0;

    for (int i = 0; i < len; i++) {
      final double s = samples[i];
      sum += s;
      sumSq += s * s;
      final double absS = s.abs();
      if (absS > peak) peak = absS;
    }

    final double dc = sum / len;
    final double rms = math.sqrt(sumSq / len);

    return AudioMetrics(
      rms: rms,
      peak: peak,
      dcOffset: dc,
      sampleCount: len,
    );
  }
}
