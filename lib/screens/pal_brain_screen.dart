import 'package:flutter/material.dart';
import '../models/chat_message.dart';
import '../models/llm_model_preset.dart';
import '../models/vault_item.dart';
import '../services/llm_service.dart';
import '../services/rag_service.dart';
import '../theme/app_theme.dart';

class PalBrainScreen extends StatefulWidget {
  final String? initialQuery;
  final String? initialFilterSubject;
  final String? initialFilterUnit;

  const PalBrainScreen({
    super.key,
    this.initialQuery,
    this.initialFilterSubject,
    this.initialFilterUnit,
  });

  @override
  State<PalBrainScreen> createState() => PalBrainScreenState();
}

class PalBrainScreenState extends State<PalBrainScreen> {
  final LlmService _llmService = LlmService.instance;
  final RagService _ragService = RagService.instance;

  final List<AcademicChatMessage> _messages = [];
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  String _selectedRagScope = 'Unit 1 (OS)'; // 'Off', 'All Notes', 'Unit 1 (OS)'

  @override
  void initState() {
    super.initState();
    _llmService.addListener(_onLlmUpdate);

    if (widget.initialFilterSubject != null ||
        widget.initialFilterUnit != null) {
      _selectedRagScope = widget.initialFilterUnit ??
          widget.initialFilterSubject ??
          'All Notes';
    }

    // Seed welcome message
    _messages.add(
      AcademicChatMessage(
        id: 'msg-welcome',
        role: 'assistant',
        text:
            'Hello! I am Pal, your on-device multimodal academic copilot running locally on your Snapdragon 8 Elite hardware. Ask me anything, or query your Study Vault with RAG citations!',
        timestamp: DateTime.now(),
      ),
    );

    if (widget.initialQuery != null && widget.initialQuery!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _inputController.text = widget.initialQuery!;
        _sendMessage();
      });
    }
  }

  @override
  void dispose() {
    _llmService.removeListener(_onLlmUpdate);
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onLlmUpdate() {
    if (mounted) setState(() {});
  }

  void setQuery(String query, {String? ragScope}) {
    if (ragScope != null) {
      setState(() => _selectedRagScope = ragScope);
    }
    _inputController.text = query;
    _sendMessage();
  }

  Future<void> _sendMessage() async {
    final query = _inputController.text.trim();
    if (query.isEmpty || _llmService.isGenerating) return;

    _inputController.clear();

    // 1. Add User Message
    final userMsg = AcademicChatMessage(
      id: 'usr_${DateTime.now().millisecondsSinceEpoch}',
      role: 'user',
      text: query,
      timestamp: DateTime.now(),
    );
    setState(() => _messages.add(userMsg));
    _scrollToBottom();

    // 2. Perform BM25 RAG Retrieval if enabled
    List<ChunkMatch> citations = [];
    String promptForLlm = query;

    if (_selectedRagScope != 'Off') {
      String? subjectFilter;
      String? unitFilter;
      if (_selectedRagScope.contains('OS')) {
        subjectFilter = 'Operating Systems';
        unitFilter = 'Unit 1';
      } else if (_selectedRagScope == 'All Notes') {
        subjectFilter = null;
        unitFilter = null;
      }

      citations = _ragService.search(
        query: query,
        filterSubject: subjectFilter,
        filterUnit: unitFilter,
        topK: 3,
      );

      if (citations.isNotEmpty) {
        final contextBuffer = StringBuffer();
        contextBuffer.writeln('=== CONTEXT FROM STUDY VAULT ===');
        for (var i = 0; i < citations.length; i++) {
          final m = citations[i];
          contextBuffer.writeln(
              '[Source ${i + 1}: ${m.chunk.subject} > ${m.chunk.unit} (${m.chunk.documentName}, p.${m.chunk.pageNumber})]:');
          contextBuffer.writeln(m.chunk.text);
          contextBuffer.writeln();
        }
        contextBuffer.writeln('=== END CONTEXT ===');
        contextBuffer.writeln(
            'Answer the student\'s question based on the provided Study Vault context above. Be accurate and concise.');
        contextBuffer.writeln('Question: $query');
        promptForLlm = contextBuffer.toString();
      }
    }

    // 3. Add Assistant Placeholder
    final assistantMsg = AcademicChatMessage(
      id: 'asst_${DateTime.now().millisecondsSinceEpoch}',
      role: 'assistant',
      text: '',
      timestamp: DateTime.now(),
      citations: citations,
      isGenerating: true,
    );
    setState(() => _messages.add(assistantMsg));
    _scrollToBottom();

    // 4. Stream Tokens from Llama.cpp Engine
    try {
      final tokenStream = _llmService.generateStreaming(
        prompt: promptForLlm,
        systemPrompt:
            'You are Pal, an expert university academic copilot running on-device.',
        maxTokens: 512,
      );

      await for (final token in tokenStream) {
        if (!mounted) break;
        setState(() {
          assistantMsg.text += token;
          assistantMsg.tokensPerSecond = _llmService.currentTps;
        });
        _scrollToBottom();
      }
    } finally {
      if (mounted) {
        setState(() {
          assistantMsg.isGenerating = false;
        });
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showModelSwitcherModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceDark,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return DraggableScrollableSheet(
            initialChildSize: 0.82,
            minChildSize: 0.5,
            maxChildSize: 0.94,
            expand: false,
            builder: (context, scrollController) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'On-Device GGUF Engine',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Direct POSIX mmap • Hexagon NPU & Adreno GPU • Off-Thread Isolate',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.cyanAccent,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon:
                            const Icon(Icons.close, color: AppTheme.textMuted),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // 2. Storage & Runtime Architecture Pill
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.cardDark,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.cardBorder),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.storage,
                            size: 18, color: AppTheme.amberAccent),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Internal App Documents Sandbox (Scoped Storage Safe)',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Path: /data/user/0/.../app_flutter/ • UFS 4.0 Flash Read (3-4 GB/s) • Zero Storage Permission Prompts • Background Isolate',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: AppTheme.textSecondary
                                      .withValues(alpha: 0.85),
                                ),
                              ),
                              if (_llmService.llmStatus.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: const BoxDecoration(
                                        color: AppTheme.greenAccent,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        _llmService.llmStatus,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: AppTheme.greenAccent,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 3. Model Cards List
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      children: [
                        ..._llmService.presets.map((preset) {
                          final isActive =
                              _llmService.activePreset?.id == preset.id;
                          final isLoaded = preset.status == ModelStatus.ready;
                          final isDownloaded =
                              preset.status == ModelStatus.downloaded;
                          final isDownloading =
                              preset.status == ModelStatus.downloading;
                          final isLoading =
                              preset.status == ModelStatus.loading;

                          Color cardBorderColor = AppTheme.cardBorder;
                          if (isActive && isLoaded) {
                            cardBorderColor = AppTheme.greenAccent;
                          } else if (isDownloading) {
                            cardBorderColor = AppTheme.amberAccent;
                          } else if (isDownloaded) {
                            cardBorderColor =
                                AppTheme.cyanAccent.withValues(alpha: 0.4);
                          }

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppTheme.cardDark,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: cardBorderColor,
                                width: (isActive && isLoaded) || isDownloading
                                    ? 1.5
                                    : 1,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Title & Spec Badges
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              preset.name,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                                color: AppTheme.textPrimary,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: AppTheme.cyanAccent
                                                  .withValues(alpha: 0.12),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              '${preset.parameters} • ${preset.quant}',
                                              style: const TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: AppTheme.cyanAccent,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    // RAM & File Size Tag
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          preset.sizeMb,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: AppTheme.textPrimary,
                                          ),
                                        ),
                                        Text(
                                          'RAM: ${preset.ramUsage}',
                                          style: const TextStyle(
                                            fontSize: 10,
                                            color: AppTheme.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),

                                // Best For & Description
                                Text(
                                  preset.bestFor,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 10),

                                // Action / Progress Section
                                if (isDownloading) ...[
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      LinearProgressIndicator(
                                        value: preset.downloadProgress > 0
                                            ? preset.downloadProgress
                                            : null,
                                        color: AppTheme.amberAccent,
                                        backgroundColor: AppTheme.surfaceDark,
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              preset.downloadStatus ??
                                                  'Downloading: ${(preset.downloadProgress * 100).toStringAsFixed(1)}%',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w500,
                                                color: AppTheme.amberAccent,
                                              ),
                                            ),
                                          ),
                                          TextButton.icon(
                                            style: TextButton.styleFrom(
                                              foregroundColor:
                                                  AppTheme.redAccent,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 2),
                                              visualDensity:
                                                  VisualDensity.compact,
                                            ),
                                            icon: const Icon(Icons.cancel,
                                                size: 14),
                                            label: const Text('CANCEL',
                                                style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight:
                                                        FontWeight.bold)),
                                            onPressed: () async {
                                              await _llmService
                                                  .cancelDownload(preset);
                                              setModalState(() {});
                                            },
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ] else if (isLoading) ...[
                                  const Row(
                                    children: [
                                      SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AppTheme.cyanAccent,
                                        ),
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        'Loading model weights into Snapdragon RAM...',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: AppTheme.cyanAccent,
                                        ),
                                      ),
                                    ],
                                  ),
                                ] else ...[
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      // Status Badge
                                      if (isActive && isLoaded)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: AppTheme.greenAccent
                                                .withValues(alpha: 0.15),
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                          child: const Row(
                                            children: [
                                              Icon(Icons.check_circle,
                                                  size: 12,
                                                  color: AppTheme.greenAccent),
                                              SizedBox(width: 4),
                                              Text(
                                                'ACTIVE ON HARDWARE',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: AppTheme.greenAccent,
                                                ),
                                              ),
                                            ],
                                          ),
                                        )
                                      else if (isDownloaded)
                                        const Text(
                                          'Downloaded to Storage',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: AppTheme.textSecondary,
                                          ),
                                        )
                                      else
                                        const Text(
                                          'Hugging Face Stream',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: AppTheme.textMuted,
                                          ),
                                        ),

                                      // Buttons
                                      Row(
                                        children: [
                                          if (isDownloaded || isLoaded) ...[
                                            if (isActive && isLoaded) ...[
                                              OutlinedButton(
                                                style: OutlinedButton.styleFrom(
                                                  foregroundColor:
                                                      AppTheme.amberAccent,
                                                  side: const BorderSide(
                                                      color:
                                                          AppTheme.amberAccent,
                                                      width: 0.8),
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 10,
                                                      vertical: 6),
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                ),
                                                onPressed: () async {
                                                  await _llmService
                                                      .unloadModel();
                                                  setModalState(() {});
                                                },
                                                child: const Text(
                                                  'UNLOAD RAM',
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 10),
                                                ),
                                              ),
                                            ] else ...[
                                              ElevatedButton(
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor:
                                                      AppTheme.cyanAccent,
                                                  foregroundColor: Colors.black,
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 12,
                                                      vertical: 6),
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                ),
                                                onPressed: () async {
                                                  await _llmService
                                                      .loadModel(preset);
                                                  setModalState(() {});
                                                },
                                                child: const Text(
                                                  'LOAD MODEL',
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 10),
                                                ),
                                              ),
                                            ],
                                            const SizedBox(width: 6),
                                            IconButton(
                                              icon: const Icon(
                                                  Icons.delete_outline,
                                                  size: 18,
                                                  color: AppTheme.redAccent),
                                              tooltip:
                                                  'Delete GGUF file from phone',
                                              onPressed: () async {
                                                await _llmService
                                                    .deleteModel(preset);
                                                setModalState(() {});
                                              },
                                            ),
                                          ] else ...[
                                            ElevatedButton.icon(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor:
                                                    AppTheme.surfaceDark,
                                                foregroundColor:
                                                    AppTheme.cyanAccent,
                                                side: const BorderSide(
                                                    color: AppTheme.cyanAccent),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 12,
                                                        vertical: 6),
                                                visualDensity:
                                                    VisualDensity.compact,
                                              ),
                                              icon: const Icon(Icons.download,
                                                  size: 13),
                                              label: const Text('DOWNLOAD GGUF',
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 10)),
                                              onPressed: () async {
                                                await _llmService
                                                    .downloadModel(preset);
                                                setModalState(() {});
                                              },
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),

                  // 4. Custom Model Actions Bar
                  const Divider(color: AppTheme.cardBorder, height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.cyanAccent,
                            side: const BorderSide(color: AppTheme.cyanAccent),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          icon: const Icon(Icons.link, size: 16),
                          label: const Text('Custom GGUF URL',
                              style: TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.bold)),
                          onPressed: () {
                            _showCustomUrlDialog(context);
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.cardSurface,
                            foregroundColor: AppTheme.textPrimary,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side:
                                  const BorderSide(color: AppTheme.cardBorder),
                            ),
                          ),
                          icon: const Icon(Icons.folder_open,
                              size: 16, color: AppTheme.amberAccent),
                          label: const Text('Pick Local .gguf',
                              style: TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.bold)),
                          onPressed: () async {
                            await _llmService.pickAndLoadLocalModel();
                            setModalState(() {});
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showCustomUrlDialog(BuildContext parentContext) {
    final urlController = TextEditingController();
    final nameController = TextEditingController();

    showDialog(
      context: parentContext,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppTheme.cardDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: AppTheme.cardBorder),
        ),
        title: const Row(
          children: [
            Icon(Icons.downloading, color: AppTheme.cyanAccent, size: 20),
            SizedBox(width: 8),
            Text('Custom GGUF Download',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Stream any GGUF quantized model directly into the internal app sandbox:',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Model Name',
                hintText: 'e.g. DeepSeek-R1-Distill-1.5B',
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlController,
              decoration: const InputDecoration(
                labelText: 'Direct GGUF URL',
                hintText: 'https://huggingface.co/.../resolve/main/...gguf',
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('CANCEL',
                style: TextStyle(color: AppTheme.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.cyanAccent,
              foregroundColor: Colors.black,
            ),
            onPressed: () {
              final url = urlController.text.trim();
              final name = nameController.text.trim();
              if (url.isNotEmpty) {
                Navigator.pop(dialogCtx);
                _llmService.addCustomModelFromUrl(url, name);
              }
            },
            child: const Text('STREAM & RUN',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Pal Brain'),
            Text(
              'Snapdragon 8 Elite On-Device LLM',
              style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune, color: AppTheme.cyanAccent),
            tooltip: 'Model Presets & Switcher',
            onPressed: _showModelSwitcherModal,
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. Hardware & Active Model Telemetry Bar
          _buildTelemetryBar(),

          // 2. RAG Scope Selector Bar
          _buildRagScopeBar(),

          // 3. Chat Message Stream
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                return _buildChatBubble(message);
              },
            ),
          ),

          // 4. Input Field & Send Button
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildTelemetryBar() {
    final active = _llmService.activePreset;
    final isDownloading = _llmService.downloadingPreset != null;
    final downloading = _llmService.downloadingPreset;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppTheme.surfaceDark,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                const Icon(Icons.developer_board,
                    size: 16, color: AppTheme.cyanAccent),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        active != null
                            ? '${active.name} (${active.quant})'
                            : 'No Model Loaded',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      Text(
                        _llmService.acceleratorName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 9,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (isDownloading && downloading != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.amberAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: AppTheme.amberAccent.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(
                        strokeWidth: 1.5, color: AppTheme.amberAccent),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${(downloading.downloadProgress * 100).toStringAsFixed(0)}% (${downloading.downloadSpeedMbps.toStringAsFixed(1)} MB/s)',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.amberAccent,
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.greenAccent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  const Icon(Icons.flash_on,
                      size: 12, color: AppTheme.greenAccent),
                  const SizedBox(width: 4),
                  Text(
                    _llmService.isGenerating
                        ? '${_llmService.currentTps.toStringAsFixed(1)} tok/s'
                        : 'Hexagon NPU / GPU ON',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.greenAccent,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRagScopeBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: const BoxDecoration(
        color: AppTheme.bgDark,
        border:
            Border(bottom: BorderSide(color: AppTheme.cardBorder, width: 0.5)),
      ),
      child: Row(
        children: [
          const Text(
            'RAG Scope: ',
            style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: ['Unit 1 (OS)', 'All Notes', 'Off'].map((scope) {
                  final isSelected = _selectedRagScope == scope;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      label: Text(scope, style: const TextStyle(fontSize: 11)),
                      selected: isSelected,
                      onSelected: (val) {
                        if (val) setState(() => _selectedRagScope = scope);
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatBubble(AcademicChatMessage msg) {
    if (msg.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12, left: 48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.cyanAccent.withValues(alpha: 0.15),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
              bottomLeft: Radius.circular(16),
            ),
            border:
                Border.all(color: AppTheme.cyanAccent.withValues(alpha: 0.3)),
          ),
          child: Text(
            msg.text,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
          ),
        ),
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14, right: 24),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.cardDark,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(16),
          ),
          border: Border.all(color: AppTheme.cardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.psychology,
                        size: 16, color: AppTheme.cyanAccent),
                    SizedBox(width: 6),
                    Text(
                      'Pal On-Device Brain',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: AppTheme.cyanAccent,
                      ),
                    ),
                  ],
                ),
                if (msg.tokensPerSecond != null && msg.tokensPerSecond! > 0)
                  Text(
                    '${msg.tokensPerSecond!.toStringAsFixed(1)} tok/s',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.greenAccent,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              msg.text.isEmpty && msg.isGenerating
                  ? 'Generating on-device tokens...'
                  : msg.text,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 14,
                height: 1.45,
              ),
            ),

            // Expandable Sources & Citations Card
            if (msg.citations.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.surfaceDark,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.cardBorder),
                ),
                child: Theme(
                  data: Theme.of(context)
                      .copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                    childrenPadding:
                        const EdgeInsets.only(left: 12, right: 12, bottom: 10),
                    leading: const Icon(Icons.bookmark_added,
                        size: 16, color: AppTheme.amberAccent),
                    title: Text(
                      '${msg.citations.length} Verified Sources & Citations',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.amberAccent,
                      ),
                    ),
                    children: msg.citations.map((c) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '• ${c.chunk.documentName} (p. ${c.chunk.pageNumber})',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                    color: AppTheme.cyanAccent,
                                  ),
                                ),
                                Text(
                                  'BM25 Score: ${c.score.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: AppTheme.textMuted,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              c.chunk.text,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppTheme.textSecondary,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        color: AppTheme.surfaceDark,
        border: Border(top: BorderSide(color: AppTheme.cardBorder)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _inputController,
                minLines: 1,
                maxLines: 4,
                style: const TextStyle(fontSize: 14),
                decoration: const InputDecoration(
                  hintText: 'Ask Pal anything from your textbooks...',
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              decoration: const BoxDecoration(
                color: AppTheme.cyanAccent,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: _llmService.isGenerating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black,
                        ),
                      )
                    : const Icon(Icons.arrow_upward, color: Colors.black),
                onPressed: _sendMessage,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
