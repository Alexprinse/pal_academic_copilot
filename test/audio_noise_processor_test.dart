import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pal_academic_copilot/services/audio_noise_processor.dart';

void main() {
  group('AudioNoiseProcessor', () {
    const int sampleRate = 16000;

    test('Non-destructive: original input Float32List is never mutated', () {
      final Float32List original =
          Float32List.fromList([0.1, 0.2, 0.3, 0.4, 0.5]);
      final Float32List copy = Float32List.fromList(original);

      final Float32List result = AudioNoiseProcessor.process(
        original,
        sampleRate: sampleRate,
        verbose: false,
      );

      // Verify original list has not changed at all
      expect(original, equals(copy));
      // Result is a new instance
      expect(identical(result, original), isFalse);
    });

    test('Empty audio buffer returns empty buffer safely', () {
      final Float32List empty = Float32List(0);
      final Float32List processed =
          AudioNoiseProcessor.process(empty, verbose: false);
      expect(processed.length, 0);
    });

    test('Silent buffer is handled without NaN or infinity', () {
      final Float32List silent = Float32List(1600); // 100ms of silence
      final Float32List processed =
          AudioNoiseProcessor.process(silent, verbose: false);

      expect(processed.length, 1600);
      for (final sample in processed) {
        expect(sample.isNaN, isFalse);
        expect(sample.isInfinite, isFalse);
      }
    });

    test('DC offset removal eliminates DC bias', () {
      const double dcBias = 0.25;
      final Float32List buffer = Float32List(1000);
      for (int i = 0; i < buffer.length; i++) {
        buffer[i] =
            dcBias + 0.05 * math.sin(2 * math.pi * 200 * i / sampleRate);
      }

      final AudioMetrics before = AudioNoiseProcessor.measureMetrics(buffer);
      expect(before.dcOffset, closeTo(0.25, 0.01));

      AudioNoiseProcessor.removeDcOffset(buffer);

      final AudioMetrics after = AudioNoiseProcessor.measureMetrics(buffer);
      expect(after.dcOffset.abs(), lessThan(1e-5));
    });

    test(
        '80 Hz High-Pass Filter attenuates 30 Hz sub-bass rumble more than 500 Hz speech',
        () {
      const int numSamples = 16000; // 1 second
      final Float32List rumble30Hz = Float32List(numSamples);
      final Float32List speech500Hz = Float32List(numSamples);

      for (int i = 0; i < numSamples; i++) {
        final double t = i / sampleRate;
        rumble30Hz[i] = 0.5 * math.sin(2 * math.pi * 30 * t);
        speech500Hz[i] = 0.5 * math.sin(2 * math.pi * 500 * t);
      }

      final double initialRumbleRms =
          AudioNoiseProcessor.measureMetrics(rumble30Hz).rms;
      final double initialSpeechRms =
          AudioNoiseProcessor.measureMetrics(speech500Hz).rms;

      AudioNoiseProcessor.applyHighPassFilter(rumble30Hz,
          sampleRate: sampleRate, cutoffHz: 80.0);
      AudioNoiseProcessor.applyHighPassFilter(speech500Hz,
          sampleRate: sampleRate, cutoffHz: 80.0);

      final double filteredRumbleRms =
          AudioNoiseProcessor.measureMetrics(rumble30Hz).rms;
      final double filteredSpeechRms =
          AudioNoiseProcessor.measureMetrics(speech500Hz).rms;

      final double rumbleAttenuation = filteredRumbleRms / initialRumbleRms;
      final double speechAttenuation = filteredSpeechRms / initialSpeechRms;

      // 30 Hz should be significantly attenuated (> 10 dB attenuation, ratio < 0.3)
      expect(rumbleAttenuation, lessThan(0.35));
      // 500 Hz should pass through virtually unattenuated (ratio > 0.95)
      expect(speechAttenuation, greaterThan(0.95));
    });

    test(
        'Soft Downward Expander preserves quiet speech and never zeroes out audio',
        () {
      // Create very quiet audio below threshold (0.005 vs threshold 0.018)
      final Float32List quietSpeech = Float32List(1600);
      for (int i = 0; i < quietSpeech.length; i++) {
        quietSpeech[i] = 0.005 * math.sin(2 * math.pi * 300 * i / sampleRate);
      }

      AudioNoiseProcessor.applyDownwardExpander(quietSpeech,
          sampleRate: sampleRate);

      // Measure peak amplitude after expander settles
      double maxPostExpander = 0.0;
      for (int i = 500; i < quietSpeech.length; i++) {
        if (quietSpeech[i].abs() > maxPostExpander) {
          maxPostExpander = quietSpeech[i].abs();
        }
      }

      // Peak amplitude of input was 0.005. With minExpanderGain = 0.35, the attenuated peak must be >= 0.35 * 0.005
      expect(maxPostExpander,
          greaterThanOrEqualTo(0.005 * AudioNoiseProcessor.minExpanderGain));
      // And must be attenuated relative to original
      expect(maxPostExpander, lessThan(0.005));
    });

    test(
        'Conservative Normalization clamps to peak ceiling and does not exceed max gain',
        () {
      // Quiet speech at 0.01 amplitude
      final Float32List quiet = Float32List(16000);
      for (int i = 0; i < quiet.length; i++) {
        quiet[i] = 0.01 * math.sin(2 * math.pi * 400 * i / sampleRate);
      }

      AudioNoiseProcessor.applyConservativeNormalization(quiet);
      final AudioMetrics metricsQuiet =
          AudioNoiseProcessor.measureMetrics(quiet);

      // Max gain is 4.0x (+12 dB), so 0.01 peak should not exceed ~0.045
      expect(metricsQuiet.peak, lessThanOrEqualTo(0.045));

      // Loud speech at 0.8 amplitude with potential to clip
      final Float32List loud = Float32List(16000);
      for (int i = 0; i < loud.length; i++) {
        loud[i] = 0.8 * math.sin(2 * math.pi * 400 * i / sampleRate);
      }

      AudioNoiseProcessor.applyConservativeNormalization(loud);
      final AudioMetrics metricsLoud = AudioNoiseProcessor.measureMetrics(loud);

      // Ceiling is 0.95
      expect(metricsLoud.peak,
          lessThanOrEqualTo(AudioNoiseProcessor.peakCeiling + 0.001));
    });
  });
}
