import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pal_academic_copilot/services/audio_noise_processor.dart';
import 'package:pal_academic_copilot/services/stt_service.dart';

void main() {
  group('WAV Validation & Audio Resampling Tests', () {
    test(
        'validateWavFile correctly parses physical lecture recording (16kHz mono)',
        () async {
      final physicalFile = File(
          '/Users/shalem/.gemini/antigravity/brain/08cef75b-94fd-40dd-b04f-d7e0dcf5b2f4/scratch/physical_lecture.wav');
      if (!await physicalFile.exists()) return;

      final meta = await SttService.validateWavFile(physicalFile.path);
      expect(meta.isValid, isTrue);
      expect(meta.numChannels, equals(1));
      expect(meta.sampleRate, equals(16000));
      expect(meta.bitsPerSample, equals(16));
      expect(meta.fileSizeBytes, equals(227884));
      expect(meta.durationSeconds, closeTo(7.12, 0.1));
      expect(meta.needsResampling, isFalse);
    });

    test('validateWavFile correctly parses asset 0.wav (16kHz mono)', () async {
      final assetFile = File(
          '/Users/shalem/Desktop/pal_academic_copilot/assets/models/whisper-tiny-en/sherpa-onnx-whisper-tiny.en/test_wavs/0.wav');
      if (!await assetFile.exists()) return;

      final meta = await SttService.validateWavFile(assetFile.path);
      expect(meta.isValid, isTrue);
      expect(meta.numChannels, equals(1));
      expect(meta.sampleRate, equals(16000));
      expect(meta.bitsPerSample, equals(16));
      expect(meta.durationSeconds, greaterThan(1.0));
      expect(meta.needsResampling, isFalse);
    });

    test('validateWavFile accepts 8kHz WAV and flags needsResampling',
        () async {
      final assetFile = File(
          '/Users/shalem/Desktop/pal_academic_copilot/assets/models/whisper-tiny-en/sherpa-onnx-whisper-tiny.en/test_wavs/8k.wav');
      if (!await assetFile.exists()) return;

      final meta = await SttService.validateWavFile(assetFile.path);
      expect(meta.isValid, isTrue);
      expect(meta.sampleRate, equals(8000));
      expect(meta.needsResampling, isTrue);
    });

    test('validateWavFile accepts 48kHz WAV and flags needsResampling',
        () async {
      final tempFile = File(
          '${Directory.systemTemp.path}/test_48k_${DateTime.now().millisecondsSinceEpoch}.wav');

      // Create 48kHz mono 16-bit WAV (1 second = 48,000 samples)
      final numSamples = 48000;
      final dataSize = numSamples * 2;
      final header = Uint8List(44);
      final byteData = ByteData.sublistView(header);

      header.setRange(0, 4, 'RIFF'.codeUnits);
      byteData.setUint32(4, 36 + dataSize, Endian.little);
      header.setRange(8, 12, 'WAVE'.codeUnits);
      header.setRange(12, 16, 'fmt '.codeUnits);
      byteData.setUint32(16, 16, Endian.little); // PCM subchunk size
      byteData.setUint16(20, 1, Endian.little); // PCM
      byteData.setUint16(22, 1, Endian.little); // 1 channel
      byteData.setUint32(24, 48000, Endian.little); // 48kHz
      byteData.setUint32(28, 48000 * 2, Endian.little); // ByteRate
      byteData.setUint16(32, 2, Endian.little); // BlockAlign
      byteData.setUint16(34, 16, Endian.little); // 16 bits
      header.setRange(36, 40, 'data'.codeUnits);
      byteData.setUint32(40, dataSize, Endian.little);

      final pcmBytes = Uint8List(44 + dataSize);
      pcmBytes.setRange(0, 44, header);
      await tempFile.writeAsBytes(pcmBytes);

      final meta = await SttService.validateWavFile(tempFile.path);
      expect(meta.isValid, isTrue);
      expect(meta.sampleRate, equals(48000));
      expect(meta.numChannels, equals(1));
      expect(meta.bitsPerSample, equals(16));
      expect(meta.durationSeconds, closeTo(1.0, 0.05));
      expect(meta.needsResampling, isTrue);

      if (await tempFile.exists()) await tempFile.delete();
    });

    test('validateWavFile accepts 44.1kHz Stereo WAV and flags needsResampling',
        () async {
      final tempFile = File(
          '${Directory.systemTemp.path}/test_stereo_${DateTime.now().millisecondsSinceEpoch}.wav');

      final numFrames = 44100;
      final channels = 2;
      final dataSize = numFrames * channels * 2;
      final header = Uint8List(44);
      final byteData = ByteData.sublistView(header);

      header.setRange(0, 4, 'RIFF'.codeUnits);
      byteData.setUint32(4, 36 + dataSize, Endian.little);
      header.setRange(8, 12, 'WAVE'.codeUnits);
      header.setRange(12, 16, 'fmt '.codeUnits);
      byteData.setUint32(16, 16, Endian.little);
      byteData.setUint16(20, 1, Endian.little);
      byteData.setUint16(22, channels, Endian.little); // 2 channels
      byteData.setUint32(24, 44100, Endian.little);
      byteData.setUint32(28, 44100 * channels * 2, Endian.little);
      byteData.setUint16(32, 4, Endian.little);
      byteData.setUint16(34, 16, Endian.little);
      header.setRange(36, 40, 'data'.codeUnits);
      byteData.setUint32(40, dataSize, Endian.little);

      final pcmBytes = Uint8List(44 + dataSize);
      pcmBytes.setRange(0, 44, header);
      await tempFile.writeAsBytes(pcmBytes);

      final meta = await SttService.validateWavFile(tempFile.path);
      expect(meta.isValid, isTrue);
      expect(meta.sampleRate, equals(44100));
      expect(meta.numChannels, equals(2));
      expect(meta.needsResampling, isTrue);

      if (await tempFile.exists()) await tempFile.delete();
    });

    test('AudioNoiseProcessor.resample correctly downsamples 48kHz to 16kHz',
        () {
      final inputSamples = Float32List(48000);
      for (int i = 0; i < inputSamples.length; i++) {
        inputSamples[i] = math.sin(2.0 * math.pi * 440.0 * i / 48000.0);
      }

      final resampled = AudioNoiseProcessor.resample(
        inputSamples,
        inputRate: 48000,
        targetRate: 16000,
      );

      expect(resampled.length, equals(16000));
      // First sample sin(0) = 0
      expect(resampled[0], closeTo(0.0, 0.01));
      // Check waveform bounds
      for (final s in resampled) {
        expect(s, inInclusiveRange(-1.0, 1.0));
      }
    });

    test('AudioNoiseProcessor.resample correctly upsamples 8kHz to 16kHz', () {
      final inputSamples = Float32List(8000);
      for (int i = 0; i < inputSamples.length; i++) {
        inputSamples[i] = math.sin(2.0 * math.pi * 200.0 * i / 8000.0);
      }

      final resampled = AudioNoiseProcessor.resample(
        inputSamples,
        inputRate: 8000,
        targetRate: 16000,
      );

      expect(resampled.length, equals(16000));
      for (final s in resampled) {
        expect(s, inInclusiveRange(-1.0, 1.0));
      }
    });

    test('AudioNoiseProcessor.findNaturalPauseSplitPoint finds silence dip',
        () {
      // 30 seconds at 16kHz = 480,000 samples
      final samples = Float32List(16000 * 30);
      // High speech energy everywhere
      for (int i = 0; i < samples.length; i++) {
        samples[i] = 0.5 * math.sin(i * 0.1);
      }
      // Insert a silence pause at 24.5s (sample 392,000) for 0.5s (8,000 samples)
      final pauseStart = 16000 * 24 + 8000;
      final pauseEnd = pauseStart + 8000;
      for (int i = pauseStart; i < pauseEnd; i++) {
        samples[i] = 0.0001; // Silence
      }

      final splitPoint = AudioNoiseProcessor.findNaturalPauseSplitPoint(
        samples,
        targetOffset: 16000 * 25, // target 25s
        searchRadiusSamples: 32000, // +/- 2s (23s to 27s)
      );

      // Split point should land in the pause region (around 24.5s - 25.0s)
      expect(splitPoint, greaterThanOrEqualTo(pauseStart));
      expect(splitPoint, lessThanOrEqualTo(pauseEnd + 800));
    });

    test(
        'AudioNoiseProcessor.readWavFile converts stereo to mono by channel averaging',
        () async {
      final tempFile = File(
          '${Directory.systemTemp.path}/test_stereo_read_${DateTime.now().millisecondsSinceEpoch}.wav');

      const numFrames = 1000;
      const channels = 2;
      const dataSize = numFrames * channels * 2;
      final header = Uint8List(44);
      final byteData = ByteData.sublistView(header);

      header.setRange(0, 4, 'RIFF'.codeUnits);
      byteData.setUint32(4, 36 + dataSize, Endian.little);
      header.setRange(8, 12, 'WAVE'.codeUnits);
      header.setRange(12, 16, 'fmt '.codeUnits);
      byteData.setUint32(16, 16, Endian.little);
      byteData.setUint16(20, 1, Endian.little);
      byteData.setUint16(22, channels, Endian.little);
      byteData.setUint32(24, 16000, Endian.little);
      byteData.setUint32(28, 16000 * channels * 2, Endian.little);
      byteData.setUint16(32, 4, Endian.little);
      byteData.setUint16(34, 16, Endian.little);
      header.setRange(36, 40, 'data'.codeUnits);
      byteData.setUint32(40, dataSize, Endian.little);

      final pcmBytes = Uint8List(44 + dataSize);
      pcmBytes.setRange(0, 44, header);

      final pcmData = ByteData.view(pcmBytes.buffer, 44, dataSize);
      for (int i = 0; i < numFrames; i++) {
        // Left channel: 0.5 (16384), Right channel: -0.5 (-16384) -> Average = 0.0
        pcmData.setInt16(i * 4, 16384, Endian.little);
        pcmData.setInt16(i * 4 + 2, -16384, Endian.little);
      }

      await tempFile.writeAsBytes(pcmBytes);

      final wave = await AudioNoiseProcessor.readWavFile(tempFile.path);
      expect(wave.sampleRate, equals(16000));
      expect(wave.samples.length, equals(numFrames));
      // Average of 0.5 and -0.5 is 0.0
      expect(wave.samples[0], closeTo(0.0, 0.01));

      if (await tempFile.exists()) await tempFile.delete();
    });
  });
}
