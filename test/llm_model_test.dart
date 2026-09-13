import 'package:flutter_test/flutter_test.dart';
import 'package:pal_academic_copilot/models/llm_model_preset.dart';
import 'package:pal_academic_copilot/services/llm_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LlmModelPreset & GGUF Specs', () {
    test('Default presets match hardware specification exactly', () {
      final presets = LlmModelPreset.defaultPresets;
      expect(presets.length, 3);

      final smol = presets.firstWhere((p) => p.id == 'smollm2-135m');
      expect(smol.name, 'SmolLM2 135M Instruct');
      expect(smol.sizeMb, '105 MB');
      expect(smol.quant, 'Q4_K_M');
      expect(smol.ramUsage, '~180 MB');
      expect(smol.filename, 'SmolLM2-135M.gguf');
      expect(smol.bestFor, contains('Ultra-fast tests'));

      final qwen = presets.firstWhere((p) => p.id == 'qwen2.5-0.5b');
      expect(qwen.name, 'Qwen 2.5 0.5B Instruct');
      expect(qwen.sizeMb, '490 MB');
      expect(qwen.quant, 'Q4_K_M');
      expect(qwen.ramUsage, '~600 MB');
      expect(qwen.filename, 'qwen2.5-0.5b.gguf');
      expect(qwen.bestFor, contains('Recommended Academic'));

      final llama = presets.firstWhere((p) => p.id == 'llama3.2-1b');
      expect(llama.name, 'Llama 3.2 1B Instruct');
      expect(llama.sizeMb, '808 MB');
      expect(llama.quant, 'Q4_K_M');
      expect(llama.ramUsage, '~1.1 GB');
      expect(llama.filename, 'Llama-3.2-1B.gguf');
      expect(llama.bestFor, contains('Flagship'));
    });

    test('LlmService memory-safe unload resets loaded status', () async {
      final service = LlmService.instance;
      await service.unloadModel();
      expect(service.loadedModelPath, isEmpty);
      expect(service.isModelLoaded, isFalse);
      expect(service.llmStatus, contains('Freed RAM/VRAM'));
    });

    test('LlmService default model selection can be changed and queried',
        () async {
      final service = LlmService.instance;
      // Default initial model is llama3.2-1b
      expect(service.defaultModelId, isNotEmpty);

      // Change default model to qwen2.5-0.5b
      await service.setDefaultModel('qwen2.5-0.5b',
          autoLoadIfDownloaded: false);
      expect(service.defaultModelId, 'qwen2.5-0.5b');
      expect(service.isDefaultModel('qwen2.5-0.5b'), isTrue);
      expect(service.isDefaultModel('smollm2-135m'), isFalse);
      expect(service.defaultPreset?.name, 'Qwen 2.5 0.5B Instruct');

      // Change back to llama3.2-1b
      await service.setDefaultModel('llama3.2-1b', autoLoadIfDownloaded: false);
      expect(service.defaultModelId, 'llama3.2-1b');
      expect(service.isDefaultModel('llama3.2-1b'), isTrue);
      expect(service.defaultPreset?.name, 'Llama 3.2 1B Instruct');
    });
  });
}
