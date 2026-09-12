enum ModelStatus {
  notDownloaded,
  downloading,
  downloaded,
  loading,
  ready,
  error,
}

class LlmModelPreset {
  final String id;
  final String name;
  final String parameters;
  final String quant;
  final String sizeMb;
  final String downloadUrl;
  final String filename;
  final String description;
  final int recommendedContext;
  ModelStatus status;
  double downloadProgress;
  String? localPath;
  String? errorMessage;

  LlmModelPreset({
    required this.id,
    required this.name,
    required this.parameters,
    required this.quant,
    required this.sizeMb,
    required this.downloadUrl,
    required this.filename,
    required this.description,
    this.recommendedContext = 2048,
    this.status = ModelStatus.notDownloaded,
    this.downloadProgress = 0.0,
    this.localPath,
    this.errorMessage,
  });

  static List<LlmModelPreset> get defaultPresets => [
        LlmModelPreset(
          id: 'smollm2-135m',
          name: 'SmolLM2 Instruct',
          parameters: '135M',
          quant: 'Q4_K_M',
          sizeMb: '85 MB',
          downloadUrl:
              'https://huggingface.co/HuggingFaceTB/SmolLM2-135M-Instruct-GGUF/resolve/main/smollm2-135m-instruct-q4_k_m.gguf',
          filename: 'smollm2-135m-instruct-q4_k_m.gguf',
          description:
              'Ultra-lightweight SLM. Instant generation (>60 tok/s), perfect for quick Q&A and task extraction.',
          recommendedContext: 2048,
        ),
        LlmModelPreset(
          id: 'qwen2.5-0.5b',
          name: 'Qwen 2.5 Instruct',
          parameters: '0.5B',
          quant: 'Q4_K_M',
          sizeMb: '398 MB',
          downloadUrl:
              'https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf',
          filename: 'qwen2.5-0.5b-instruct-q4_k_m.gguf',
          description:
              'Balanced powerhouse. Superb reasoning, STEM problem solving, and summarization accuracy.',
          recommendedContext: 2048,
        ),
        LlmModelPreset(
          id: 'llama3.2-1b',
          name: 'Llama 3.2 Instruct',
          parameters: '1.2B',
          quant: 'Q4_K_M',
          sizeMb: '800 MB',
          downloadUrl:
              'https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf',
          filename: 'llama-3.2-1b-instruct-q4_k_m.gguf',
          description:
              'Flagship academic model. Rich conceptual depth, detailed textbook synthesis, and citations.',
          recommendedContext: 2048,
        ),
      ];
}
