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
  final String ramUsage;
  final String bestFor;
  final String downloadUrl;
  final String filename;
  final String description;
  final int recommendedContext;
  final bool isCustom;
  final int? minSizeBytes;
  ModelStatus status;
  double downloadProgress;
  double downloadSpeedMbps;
  String? downloadStatus;
  String? localPath;
  String? errorMessage;

  LlmModelPreset({
    required this.id,
    required this.name,
    required this.parameters,
    required this.quant,
    required this.sizeMb,
    required this.ramUsage,
    required this.bestFor,
    required this.downloadUrl,
    required this.filename,
    required this.description,
    this.recommendedContext = 2048,
    this.isCustom = false,
    this.minSizeBytes,
    this.status = ModelStatus.notDownloaded,
    this.downloadProgress = 0.0,
    this.downloadSpeedMbps = 0.0,
    this.downloadStatus,
    this.localPath,
    this.errorMessage,
  });

  static List<LlmModelPreset> get defaultPresets => [
        LlmModelPreset(
          id: 'smollm2-135m',
          name: 'SmolLM2 135M Instruct',
          parameters: '135M',
          quant: 'Q4_K_M',
          sizeMb: '105 MB',
          ramUsage: '~180 MB',
          bestFor: 'Ultra-fast tests, intent parsing, instant scheduling.',
          downloadUrl:
              'https://huggingface.co/HuggingFaceTB/SmolLM2-135M-Instruct-GGUF/resolve/main/smollm2-135m-instruct-q4_k_m.gguf',
          filename: 'SmolLM2-135M.gguf',
          description:
              'Ultra-fast tests, intent parsing, instant scheduling (>60 tok/s).',
          recommendedContext: 2048,
          minSizeBytes: 95 * 1024 * 1024,
        ),
        LlmModelPreset(
          id: 'qwen2.5-0.5b',
          name: 'Qwen 2.5 0.5B Instruct',
          parameters: '0.5B',
          quant: 'Q4_K_M',
          sizeMb: '490 MB',
          ramUsage: '~600 MB',
          bestFor: 'Recommended Academic: Excellent reasoning, math & coding.',
          downloadUrl:
              'https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf',
          filename: 'qwen2.5-0.5b.gguf',
          description:
              'Recommended Academic: Excellent reasoning, math & coding.',
          recommendedContext: 2048,
          minSizeBytes: 350 * 1024 * 1024,
        ),
        LlmModelPreset(
          id: 'llama3.2-1b',
          name: 'Llama 3.2 1B Instruct',
          parameters: '1.2B',
          quant: 'Q4_K_M',
          sizeMb: '808 MB',
          ramUsage: '~1.1 GB',
          bestFor:
              'Flagship: Deep syllabus explanations, multi-step RAG citations.',
          downloadUrl:
              'https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf',
          filename: 'Llama-3.2-1B.gguf',
          description:
              'Flagship: Deep syllabus explanations, multi-step RAG citations.',
          recommendedContext: 2048,
          minSizeBytes: 750 * 1024 * 1024,
        ),
      ];
}
