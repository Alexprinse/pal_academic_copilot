import 'dart:io';
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

/// Validation result after applying DSP processing to ensure audio integrity.
class DspValidationResult {
  final bool isValid;
  final String? errorMessage;
  final int invalidSampleCount;
  final double minSample;
  final double maxSample;

  const DspValidationResult({
    required this.isValid,
    this.errorMessage,
    this.invalidSampleCount = 0,
    this.minSample = 0.0,
    this.maxSample = 0.0,
  });

  @override
  String toString() => isValid
      ? 'Valid (range: [${minSample.toStringAsFixed(3)}, ${maxSample.toStringAsFixed(3)}])'
      : 'INVALID: $errorMessage';
}

/// Configuration model for the audio DSP pipeline and A/B test presets.
class DspConfig {
  final bool enableDcRemoval;
  final bool enableHighPass;
  final double highPassCutoffHz;
  final bool enableNoiseReduction;
  final double expanderThreshold;
  final double minExpanderGain;
  final bool enableNormalization;
  final double maxNormalizationGain;
  final double targetRms;
  final double peakCeiling;
  final String label;

  const DspConfig({
    this.enableDcRemoval = true,
    this.enableHighPass = true,
    this.highPassCutoffHz = AudioNoiseProcessor.defaultHighPassCutoffHz,
    this.enableNoiseReduction = true,
    this.expanderThreshold = AudioNoiseProcessor.expanderThreshold,
    this.minExpanderGain = AudioNoiseProcessor.minExpanderGain,
    this.enableNormalization = true,
    this.maxNormalizationGain = AudioNoiseProcessor.maxNormalizationGain,
    this.targetRms = AudioNoiseProcessor.targetRms,
    this.peakCeiling = AudioNoiseProcessor.peakCeiling,
    this.label = 'Full DSP Pipeline',
  });

  /// Preset A: No processing (Bypass)
  static const DspConfig bypass = DspConfig(
    enableDcRemoval: false,
    enableHighPass: false,
    enableNoiseReduction: false,
    enableNormalization: false,
    label: 'No Processing (Bypass)',
  );

  /// Preset B: High-pass filter only (attenuates rumble)
  static const DspConfig highPassOnly = DspConfig(
    enableDcRemoval: true,
    enableHighPass: true,
    enableNoiseReduction: false,
    enableNormalization: false,
    label: 'High-Pass Only (80 Hz)',
  );

  /// Preset C: Downward expander / noise gate only
  static const DspConfig noiseGateOnly = DspConfig(
    enableDcRemoval: false,
    enableHighPass: false,
    enableNoiseReduction: true,
    enableNormalization: false,
    label: 'Noise Gate Only',
  );

  /// Preset D: Conservative normalization only
  static const DspConfig normalizationOnly = DspConfig(
    enableDcRemoval: false,
    enableHighPass: false,
    enableNoiseReduction: false,
    enableNormalization: true,
    label: 'Normalization Only',
  );

  /// Preset E: High-pass + Noise Gate
  static const DspConfig highPassAndGate = DspConfig(
    enableDcRemoval: true,
    enableHighPass: true,
    enableNoiseReduction: true,
    enableNormalization: false,
    label: 'High-Pass + Noise Gate',
  );

  /// Preset F: High-pass + Normalization
  static const DspConfig highPassAndNorm = DspConfig(
    enableDcRemoval: true,
    enableHighPass: true,
    enableNoiseReduction: false,
    enableNormalization: true,
    label: 'High-Pass + Normalization',
  );

  /// Preset G: Full pipeline
  static const DspConfig full = DspConfig(
    label: 'Full DSP Pipeline',
  );

  DspConfig copyWith({
    bool? enableDcRemoval,
    bool? enableHighPass,
    double? highPassCutoffHz,
    bool? enableNoiseReduction,
    double? expanderThreshold,
    double? minExpanderGain,
    bool? enableNormalization,
    double? maxNormalizationGain,
    double? targetRms,
    double? peakCeiling,
    String? label,
  }) {
    return DspConfig(
      enableDcRemoval: enableDcRemoval ?? this.enableDcRemoval,
      enableHighPass: enableHighPass ?? this.enableHighPass,
      highPassCutoffHz: highPassCutoffHz ?? this.highPassCutoffHz,
      enableNoiseReduction: enableNoiseReduction ?? this.enableNoiseReduction,
      expanderThreshold: expanderThreshold ?? this.expanderThreshold,
      minExpanderGain: minExpanderGain ?? this.minExpanderGain,
      enableNormalization: enableNormalization ?? this.enableNormalization,
      maxNormalizationGain: maxNormalizationGain ?? this.maxNormalizationGain,
      targetRms: targetRms ?? this.targetRms,
      peakCeiling: peakCeiling ?? this.peakCeiling,
      label: label ?? this.label,
    );
  }
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
    DspConfig? config,
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

    // Apply config if provided
    final bool useDc = config?.enableDcRemoval ?? enableDcRemoval;
    final bool useHp = config?.enableHighPass ?? enableHighPass;
    final double hpCutoff = config?.highPassCutoffHz ?? highPassCutoffHz;
    final bool useNoise = config?.enableNoiseReduction ?? enableNoiseReduction;
    final double expThreshold = config?.expanderThreshold ?? expanderThreshold;
    final double expMinGain = config?.minExpanderGain ?? minExpanderGain;
    final bool useNorm = config?.enableNormalization ?? enableNormalization;
    final double normMaxGain =
        config?.maxNormalizationGain ?? maxNormalizationGain;
    final double normTargetRms = config?.targetRms ?? targetRms;
    final double normCeiling = config?.peakCeiling ?? peakCeiling;

    final int len = input.length;
    // Work on a dedicated clone to protect original audio
    final Float32List output = Float32List.fromList(input);

    final AudioMetrics beforeMetrics = verbose
        ? measureMetrics(output)
        : const AudioMetrics(rms: 0, peak: 0, dcOffset: 0, sampleCount: 0);

    // 1. DC Offset Removal
    if (useDc) {
      removeDcOffset(output);
    }

    // 2. 80 Hz 2nd-Order Butterworth High-Pass Filter (IIR)
    if (useHp && sampleRate > 0 && hpCutoff > 0) {
      applyHighPassFilter(output, sampleRate: sampleRate, cutoffHz: hpCutoff);
    }

    // 3. Soft Downward Expander (Conservative Noise Reduction)
    if (useNoise && sampleRate > 0) {
      applyDownwardExpander(
        output,
        sampleRate: sampleRate,
        threshold: expThreshold,
        minGain: expMinGain,
      );
    }

    // 4. Conservative RMS/Peak Normalization
    if (useNorm) {
      applyConservativeNormalization(
        output,
        targetRms: normTargetRms,
        maxGain: normMaxGain,
        ceiling: normCeiling,
      );
    }

    if (verbose) {
      final AudioMetrics afterMetrics = measureMetrics(output);
      debugPrint('[AUDIO DSP] Preprocessing completed:');
      debugPrint(
          '[AUDIO DSP]   Sample rate: $sampleRate Hz, Samples: $len (${(len / sampleRate).toStringAsFixed(1)}s)');
      debugPrint(
          '[AUDIO DSP]   High-pass: ${hpCutoff.toStringAsFixed(0)} Hz (2nd-order Butterworth)');
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
  static void applyConservativeNormalization(
    Float32List buffer, {
    double targetRms = targetRms,
    double maxGain = maxNormalizationGain,
    double ceiling = peakCeiling,
  }) {
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
    gain = gain.clamp(0.25, maxGain);

    // Prevent any clipping beyond peak ceiling
    if (peak * gain > ceiling) {
      gain = ceiling / peak;
    }

    // Apply gain safely with final clamping
    for (int i = 0; i < len; i++) {
      final double sample = buffer[i] * gain;
      buffer[i] = sample.clamp(-ceiling, ceiling);
    }
  }

  /// Validates that audio samples are well-formed:
  /// - No NaN values
  /// - No Infinity values
  /// - Values bounded within [-1.0, 1.0]
  /// - If [expectedLength] is provided, length matches exactly
  static DspValidationResult validateSamples(
    Float32List samples, {
    int? expectedLength,
  }) {
    if (expectedLength != null && samples.length != expectedLength) {
      return DspValidationResult(
        isValid: false,
        errorMessage:
            'Length mismatch: expected $expectedLength samples but got ${samples.length}',
      );
    }

    int invalidCount = 0;
    double minSample = samples.isNotEmpty ? samples[0] : 0.0;
    double maxSample = samples.isNotEmpty ? samples[0] : 0.0;

    for (int i = 0; i < samples.length; i++) {
      final double s = samples[i];
      if (s.isNaN || s.isInfinite) {
        invalidCount++;
        continue;
      }
      if (s < minSample) minSample = s;
      if (s > maxSample) maxSample = s;
      if (s < -1.0 || s > 1.0) {
        invalidCount++;
      }
    }

    if (invalidCount > 0) {
      return DspValidationResult(
        isValid: false,
        errorMessage:
            'Found $invalidCount invalid samples (NaN, Inf, or outside [-1.0, 1.0])',
        invalidSampleCount: invalidCount,
        minSample: minSample,
        maxSample: maxSample,
      );
    }

    return DspValidationResult(
      isValid: true,
      minSample: minSample,
      maxSample: maxSample,
    );
  }

  /// Writes [samples] to a standard 16-bit PCM Mono WAV file at [targetPath].
  ///
  /// Uses a pure Dart implementation to write the standard 44-byte RIFF WAV header
  /// followed by 16-bit signed integer little-endian PCM samples.
  /// This ensures it works cross-platform (including in test environments without Sherpa native binaries).
  static Future<File> writeWavFile(
    String targetPath,
    Float32List samples, {
    int sampleRate = 16000,
  }) async {
    final file = File(targetPath);
    final parentDir = file.parent;
    if (!await parentDir.exists()) {
      await parentDir.create(recursive: true);
    }

    final int numSamples = samples.length;
    final int byteRate =
        sampleRate * 1 * 2; // sampleRate * channels * bytesPerSample
    final int dataChunkSize = numSamples * 2;
    final int totalFileSize = 36 + dataChunkSize;

    final ByteData header = ByteData(44);
    // RIFF chunk descriptor
    header.setUint8(0, 0x52); // 'R'
    header.setUint8(1, 0x49); // 'I'
    header.setUint8(2, 0x46); // 'F'
    header.setUint8(3, 0x46); // 'F'
    header.setUint32(4, totalFileSize, Endian.little);
    header.setUint8(8, 0x57); // 'W'
    header.setUint8(9, 0x41); // 'A'
    header.setUint8(10, 0x56); // 'V'
    header.setUint8(11, 0x45); // 'E'

    // fmt sub-chunk
    header.setUint8(12, 0x66); // 'f'
    header.setUint8(13, 0x6D); // 'm'
    header.setUint8(14, 0x74); // 't'
    header.setUint8(15, 0x20); // ' '
    header.setUint32(16, 16, Endian.little); // Subchunk1Size for PCM
    header.setUint16(20, 1, Endian.little); // AudioFormat = 1 (PCM)
    header.setUint16(22, 1, Endian.little); // NumChannels = 1 (Mono)
    header.setUint32(24, sampleRate, Endian.little); // SampleRate
    header.setUint32(28, byteRate, Endian.little); // ByteRate
    header.setUint16(32, 2, Endian.little); // BlockAlign = 2
    header.setUint16(34, 16, Endian.little); // BitsPerSample = 16

    // data sub-chunk
    header.setUint8(36, 0x64); // 'd'
    header.setUint8(37, 0x61); // 'a'
    header.setUint8(38, 0x74); // 't'
    header.setUint8(39, 0x61); // 'a'
    header.setUint32(40, dataChunkSize, Endian.little);

    final Uint8List pcmBytes = Uint8List(44 + dataChunkSize);
    pcmBytes.setRange(0, 44, header.buffer.asUint8List());

    final ByteData pcmView = ByteData.view(pcmBytes.buffer, 44, dataChunkSize);
    for (int i = 0; i < numSamples; i++) {
      // Clamped scale to signed 16-bit integer [-32768, 32767]
      final double clamped = samples[i].clamp(-1.0, 1.0);
      final int intSample = (clamped * 32767.0).round().clamp(-32768, 32767);
      pcmView.setInt16(i * 2, intSample, Endian.little);
    }

    await file.writeAsBytes(pcmBytes, flush: true);
    return file;
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

  /// Resamples [samples] from [inputRate] to [targetRate] (typically 16000 Hz).
  ///
  /// Uses band-safe linear interpolation.
  /// If [inputRate] == [targetRate], returns [samples] directly.
  static Float32List resample(
    Float32List samples, {
    required int inputRate,
    int targetRate = 16000,
  }) {
    if (samples.isEmpty ||
        inputRate <= 0 ||
        targetRate <= 0 ||
        inputRate == targetRate) {
      return samples;
    }

    final double ratio = inputRate / targetRate;
    final int outputLength = (samples.length / ratio).floor();
    if (outputLength <= 0) return Float32List(0);

    final Float32List resampled = Float32List(outputLength);

    for (int i = 0; i < outputLength; i++) {
      final double inIndex = i * ratio;
      final int indexLow = inIndex.floor();
      final int indexHigh =
          (indexLow + 1 < samples.length) ? indexLow + 1 : indexLow;
      final double fraction = inIndex - indexLow;

      final double sampleLow = samples[indexLow];
      final double sampleHigh = samples[indexHigh];

      resampled[i] =
          (sampleLow + fraction * (sampleHigh - sampleLow)).clamp(-1.0, 1.0);
    }

    return resampled;
  }

  /// Finds the best split point in [samples] around [targetOffset] within [searchRadiusSamples],
  /// by locating the frame with the lowest local RMS energy (natural pause / silence).
  ///
  /// Prevents chopping words or syllables mid-utterance across 25-second chunk boundaries.
  static int findNaturalPauseSplitPoint(
    Float32List samples, {
    required int targetOffset,
    int searchRadiusSamples = 32000, // +/- 2 seconds at 16kHz
    int frameSize = 800, // 50ms at 16kHz
  }) {
    if (samples.isEmpty) return 0;
    final int minSearch = math.max(0, targetOffset - searchRadiusSamples);
    final int maxSearch = math.min(
        samples.length - frameSize, targetOffset + searchRadiusSamples);

    if (minSearch >= maxSearch) {
      return targetOffset.clamp(0, samples.length);
    }

    int bestSplit = targetOffset;
    double minEnergy = double.infinity;

    for (int i = minSearch; i <= maxSearch; i += frameSize ~/ 2) {
      double sumSq = 0.0;
      for (int j = 0; j < frameSize; j++) {
        final double s = samples[i + j];
        sumSq += s * s;
      }
      if (sumSq < minEnergy) {
        minEnergy = sumSq;
        bestSplit = i + (frameSize ~/ 2);
      }
    }

    return bestSplit.clamp(0, samples.length);
  }

  /// Reads a WAV file and returns the audio samples normalized to [-1.0, 1.0] and sample rate.
  /// Converts stereo or multi-channel audio to mono by channel averaging.
  /// Supports 16-bit, 24-bit PCM, and 32-bit PCM/Float.
  /// Works completely in pure Dart without native bindings.
  static Future<({Float32List samples, int sampleRate})> readWavFile(
      String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw FileSystemException('WAV file not found', path);
    }
    final Uint8List bytes = await file.readAsBytes();
    if (bytes.length < 44) {
      throw FormatException('WAV file too short (${bytes.length} bytes)');
    }

    final ByteData data =
        ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes);

    // Verify RIFF & WAVE
    if (bytes[0] != 0x52 ||
        bytes[1] != 0x49 ||
        bytes[2] != 0x46 ||
        bytes[3] != 0x46 ||
        bytes[8] != 0x57 ||
        bytes[9] != 0x41 ||
        bytes[10] != 0x56 ||
        bytes[11] != 0x45) {
      throw const FormatException('Not a valid RIFF WAVE file');
    }

    int offset = 12;
    int sampleRate = 16000;
    int numChannels = 1;
    int bitsPerSample = 16;
    int dataOffset = -1;
    int dataSize = 0;

    while (offset + 8 <= bytes.length) {
      final String chunkId =
          String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final int chunkSize = data.getUint32(offset + 4, Endian.little);
      offset += 8;

      if (chunkId == 'fmt ') {
        numChannels = data.getUint16(offset + 2, Endian.little);
        sampleRate = data.getUint32(offset + 4, Endian.little);
        bitsPerSample = data.getUint16(offset + 14, Endian.little);
      } else if (chunkId == 'data') {
        dataOffset = offset;
        dataSize = chunkSize;
        break;
      }
      offset += chunkSize;
    }

    if (dataOffset == -1 || dataOffset + dataSize > bytes.length) {
      dataOffset = 44;
      dataSize = bytes.length - 44;
    }

    final int bytesPerSample = bitsPerSample ~/ 8;
    if (bytesPerSample <= 0) {
      throw const FormatException('Invalid bitsPerSample in WAV header');
    }
    final int totalRawSamples = dataSize ~/ bytesPerSample;
    final int numFrames =
        totalRawSamples ~/ (numChannels > 0 ? numChannels : 1);

    final Float32List samples = Float32List(numFrames);

    if (bitsPerSample == 16) {
      for (int i = 0; i < numFrames; i++) {
        final int sampleIdx = dataOffset + (i * numChannels) * 2;
        if (numChannels == 1) {
          if (sampleIdx + 2 <= bytes.length) {
            final int intVal = data.getInt16(sampleIdx, Endian.little);
            samples[i] = (intVal / 32768.0).clamp(-1.0, 1.0);
          }
        } else {
          // Downmix multi-channel / stereo to mono
          if (sampleIdx + 4 <= bytes.length) {
            final int left = data.getInt16(sampleIdx, Endian.little);
            final int right = data.getInt16(sampleIdx + 2, Endian.little);
            samples[i] = ((left + right) / (2.0 * 32768.0)).clamp(-1.0, 1.0);
          }
        }
      }
    } else if (bitsPerSample == 24) {
      for (int i = 0; i < numFrames; i++) {
        final int sampleIdx = dataOffset + (i * numChannels) * 3;
        if (numChannels == 1) {
          if (sampleIdx + 3 <= bytes.length) {
            int intVal = bytes[sampleIdx] |
                (bytes[sampleIdx + 1] << 8) |
                (bytes[sampleIdx + 2] << 16);
            if ((intVal & 0x800000) != 0) intVal |= ~0xFFFFFF;
            samples[i] = (intVal / 8388608.0).clamp(-1.0, 1.0);
          }
        } else {
          if (sampleIdx + 6 <= bytes.length) {
            int left = bytes[sampleIdx] |
                (bytes[sampleIdx + 1] << 8) |
                (bytes[sampleIdx + 2] << 16);
            if ((left & 0x800000) != 0) left |= ~0xFFFFFF;
            int right = bytes[sampleIdx + 3] |
                (bytes[sampleIdx + 4] << 8) |
                (bytes[sampleIdx + 5] << 16);
            if ((right & 0x800000) != 0) right |= ~0xFFFFFF;
            samples[i] = ((left + right) / (2.0 * 8388608.0)).clamp(-1.0, 1.0);
          }
        }
      }
    } else if (bitsPerSample == 32) {
      for (int i = 0; i < numFrames; i++) {
        final int sampleIdx = dataOffset + (i * numChannels) * 4;
        if (sampleIdx + 4 <= bytes.length) {
          try {
            final double val = data.getFloat32(sampleIdx, Endian.little);
            samples[i] = val.clamp(-1.0, 1.0);
          } catch (_) {
            final int intVal = data.getInt32(sampleIdx, Endian.little);
            samples[i] = (intVal / 2147483648.0).clamp(-1.0, 1.0);
          }
        }
      }
    } else {
      throw FormatException(
          'Unsupported bitsPerSample: $bitsPerSample (expected 16, 24, or 32-bit PCM)');
    }

    return (samples: samples, sampleRate: sampleRate);
  }
}
