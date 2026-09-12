import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../models/chat_message.dart';
import '../models/llm_model_preset.dart';
import '../models/vault_item.dart';
import '../services/llm_service.dart';
import '../services/rag_service.dart';
import '../services/stt_service.dart';
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
  final SttService _sttService = SttService.instance;

  final List<AcademicChatMessage> _messages = [];
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  String? _copiedMessageId;
  final Set<String> _likedMessageIds = <String>{};
  final Set<String> _dislikedMessageIds = <String>{};

  String _selectedRagScope = 'Unit 1 (OS)'; // 'Off', 'All Notes', 'Unit 1 (OS)'

  @override
  void initState() {
    super.initState();
    _llmService.addListener(_onLlmUpdate);
    _sttService.addListener(_onSttUpdate);

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
    _sttService.removeListener(_onSttUpdate);
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onLlmUpdate() {
    if (mounted) setState(() {});
  }

  void _onSttUpdate() {
    if (mounted) setState(() {});
  }

  Future<void> _toggleVoiceRecording() async {
    if (_sttService.isRecording) {
      final transcribed = await _sttService.stopRecording();
      if (transcribed.isNotEmpty &&
          transcribed != 'No speech detected in recording.' &&
          !transcribed.startsWith("Couldn't transcribe") &&
          mounted) {
        setState(() {
          _inputController.text = transcribed;
        });
        _scrollToBottom();
      } else if (transcribed.isNotEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(transcribed),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } else {
      try {
        await _sttService.startRecording();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppTheme.cardDark,
              content: Text('Microphone error: $e',
                  style: const TextStyle(color: AppTheme.redAccent)),
            ),
          );
        }
      }
    }
  }

  void setQuery(String query, {String? ragScope}) {
    if (ragScope != null) {
      setState(() => _selectedRagScope = ragScope);
    }
    _inputController.text = query;
    _sendMessage();
  }

  @visibleForTesting
  void addMessageForTesting(AcademicChatMessage message) {
    setState(() {
      _messages.add(message);
    });
  }

  @visibleForTesting
  void showModelSwitcherForTesting() {
    _showModelSwitcherModal();
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Expanded(
                        child: Column(
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
                                              color: AppTheme.primaryAccent
                                                  .withValues(alpha: 0.12),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              '${preset.parameters} • ${preset.quant}',
                                              style: const TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: AppTheme.primaryAccent,
                                              ),
                                            ),
                                          ),
                                          if (_llmService
                                              .isDefaultModel(preset.id)) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2),
                                              decoration: BoxDecoration(
                                                color: AppTheme.highlightBg,
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                                border: Border.all(
                                                  color: AppTheme.primaryAccent
                                                      .withValues(alpha: 0.5),
                                                ),
                                              ),
                                              child: const Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(Icons.star,
                                                      size: 10,
                                                      color: AppTheme
                                                          .primaryAccent),
                                                  SizedBox(width: 3),
                                                  Text(
                                                    'DEFAULT',
                                                    style: TextStyle(
                                                      fontSize: 9,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: AppTheme
                                                          .primaryAccent,
                                                      letterSpacing: 0.4,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
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
                                      if (_llmService.isDefaultModel(preset.id))
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: AppTheme.highlightBg,
                                            borderRadius:
                                                BorderRadius.circular(6),
                                            border: Border.all(
                                              color: AppTheme.primaryAccent
                                                  .withValues(alpha: 0.4),
                                            ),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.star,
                                                  size: 11,
                                                  color:
                                                      AppTheme.primaryAccent),
                                              SizedBox(width: 4),
                                              Text(
                                                'Default Model',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: AppTheme.primaryAccent,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  // Action Buttons Row
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      if (!_llmService
                                          .isDefaultModel(preset.id)) ...[
                                        OutlinedButton.icon(
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor:
                                                AppTheme.primaryAccent,
                                            side: const BorderSide(
                                                color: AppTheme.cardBorder),
                                            backgroundColor: AppTheme.canvasBg,
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 4),
                                            visualDensity:
                                                VisualDensity.compact,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                          ),
                                          icon: const Icon(Icons.star_outline,
                                              size: 13),
                                          label: const Text(
                                            'Set Default',
                                            style: TextStyle(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          onPressed: () async {
                                            await _llmService
                                                .setDefaultModel(preset.id);
                                            setModalState(() {});
                                            if (!context.mounted) return;
                                            ScaffoldMessenger.of(context)
                                                .clearSnackBars();
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  preset.status ==
                                                          ModelStatus.downloaded
                                                      ? "${preset.name} set as default model (auto-loads on launch)."
                                                      : "${preset.name} set as default model. Download it to auto-load on launch.",
                                                ),
                                                duration:
                                                    const Duration(seconds: 2),
                                                behavior:
                                                    SnackBarBehavior.floating,
                                              ),
                                            );
                                          },
                                        ),
                                        const SizedBox(width: 8),
                                      ],
                                      if (isDownloaded || isLoaded) ...[
                                        if (isActive && isLoaded) ...[
                                          OutlinedButton(
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor:
                                                  AppTheme.primaryAccent,
                                              side: const BorderSide(
                                                  color: AppTheme.primaryAccent,
                                                  width: 0.8),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 6),
                                              visualDensity:
                                                  VisualDensity.compact,
                                            ),
                                            onPressed: () async {
                                              await _llmService.unloadModel();
                                              setModalState(() {});
                                            },
                                            child: const Text(
                                              'UNLOAD RAM',
                                              style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 10),
                                            ),
                                          ),
                                        ] else ...[
                                          ElevatedButton(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  AppTheme.primaryAccent,
                                              foregroundColor: Colors.white,
                                              padding:
                                                  const EdgeInsets.symmetric(
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
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 10),
                                            ),
                                          ),
                                        ],
                                        const SizedBox(width: 6),
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline,
                                              size: 18,
                                              color: AppTheme.overduePillText),
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
                                                AppTheme.primaryAccent,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 12, vertical: 6),
                                            visualDensity:
                                                VisualDensity.compact,
                                          ),
                                          icon: const Icon(Icons.download,
                                              size: 13),
                                          label: const Text('DOWNLOAD GGUF',
                                              style: TextStyle(
                                                  fontWeight: FontWeight.bold,
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
      backgroundColor: AppTheme.canvasBg,
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
            icon: const Icon(Icons.tune, color: AppTheme.primaryAccent),
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
      decoration: const BoxDecoration(
        color: AppTheme.cardSurface,
        border: Border(
          bottom: BorderSide(color: AppTheme.cardBorder, width: 0.5),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                const Icon(Icons.developer_board,
                    size: 16, color: AppTheme.primaryAccent),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _llmService.isModelLoaded && active != null
                            ? '${active.name} (${active.quant})'
                            : 'No Model Loaded · Default: ${_llmService.defaultPreset?.name ?? "Llama 3.2 1B"}',
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
                color: AppTheme.detectedPillFill,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: AppTheme.primaryAccent.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(
                        strokeWidth: 1.5, color: AppTheme.primaryAccent),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${(downloading.downloadProgress * 100).toStringAsFixed(0)}% (${downloading.downloadSpeedMbps.toStringAsFixed(1)} MB/s)',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.detectedPillText,
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.trustPillFill,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  const Icon(Icons.flash_on,
                      size: 12, color: AppTheme.trustPillText),
                  const SizedBox(width: 4),
                  Text(
                    _llmService.isGenerating
                        ? '${_llmService.currentTps.toStringAsFixed(1)} tok/s'
                        : 'Hexagon NPU / GPU ON',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.trustPillText,
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
        color: AppTheme.canvasBg,
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
                      selectedColor: AppTheme.highlightBg,
                      backgroundColor: AppTheme.neutralPillFill,
                      side: BorderSide(
                        color: isSelected
                            ? AppTheme.primaryAccent
                            : AppTheme.cardBorder,
                      ),
                      labelStyle: TextStyle(
                        fontSize: 11,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected
                            ? AppTheme.primaryAccent
                            : AppTheme.textPrimary,
                      ),
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
      return _buildUserMessage(msg);
    }
    return _buildAssistantMessage(msg);
  }

  Widget _buildUserMessage(AcademicChatMessage msg) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16, left: 52),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.highlightBg,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(18),
            bottomRight: Radius.circular(4),
          ),
          border:
              Border.all(color: AppTheme.primaryAccent.withValues(alpha: 0.3)),
          boxShadow: AppTheme.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              msg.text,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 14.5,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _formatTime(msg.timestamp),
              style: const TextStyle(
                fontSize: 10,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAssistantMessage(AcademicChatMessage msg) {
    final isCopied = _copiedMessageId == msg.id;
    final isLiked = _likedMessageIds.contains(msg.id);
    final isDisliked = _dislikedMessageIds.contains(msg.id);

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 18),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.cardSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.cardBorder),
          boxShadow: AppTheme.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Header: Avatar + Copilot Title + Speed badge
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: AppTheme.highlightBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppTheme.primaryAccent.withValues(alpha: 0.3),
                        ),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.psychology,
                          size: 16,
                          color: AppTheme.primaryAccent,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Pal Academic Copilot',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
                if (msg.tokensPerSecond != null && msg.tokensPerSecond! > 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.trustPillFill,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppTheme.trustPillText.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.bolt,
                            size: 11, color: AppTheme.trustPillText),
                        const SizedBox(width: 3),
                        Text(
                          '${msg.tokensPerSecond!.toStringAsFixed(1)} tok/s',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.trustPillText,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // 2. Body: Markdown response or loading state
            if (msg.text.isEmpty && msg.isGenerating)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: const [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.primaryAccent,
                      ),
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Formulating on-device response...',
                      style: TextStyle(
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              )
            else
              MarkdownBody(
                data: msg.text,
                selectable: true,
                styleSheet: MarkdownStyleSheet(
                  p: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    height: 1.55,
                  ),
                  h1: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    height: 1.35,
                  ),
                  h2: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    height: 1.35,
                  ),
                  h3: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold,
                    height: 1.35,
                  ),
                  strong: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                  em: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontStyle: FontStyle.italic,
                  ),
                  blockquote: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontStyle: FontStyle.italic,
                    fontSize: 13.5,
                  ),
                  blockquoteDecoration: BoxDecoration(
                    color: AppTheme.neutralPillFill.withValues(alpha: 0.5),
                    border: const Border(
                      left: BorderSide(
                        color: AppTheme.primaryAccent,
                        width: 3,
                      ),
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  code: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontFamily: 'monospace',
                    fontSize: 12.5,
                    backgroundColor: Colors.transparent,
                  ),
                  codeblockDecoration: BoxDecoration(
                    color: AppTheme.neutralPillFill,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.cardBorder),
                  ),
                  listBullet: const TextStyle(
                    color: AppTheme.primaryAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

            // 3. Citations Chips (if any)
            if (msg.citations.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Divider(height: 1, color: AppTheme.cardBorder),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.verified_outlined,
                      size: 13, color: AppTheme.trustPillText),
                  const SizedBox(width: 5),
                  Text(
                    '${msg.citations.length} Vault Sources Used:',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: msg.citations
                    .map((c) => _buildCitationChip(context, c))
                    .toList(),
              ),
            ],

            const SizedBox(height: 12),
            const Divider(height: 1, color: AppTheme.cardBorder),
            const SizedBox(height: 8),

            // 4. Action Row: Copy, Feedback, More Options, Timestamp
            Row(
              children: [
                // Copy Action
                InkWell(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: msg.text));
                    setState(() => _copiedMessageId = msg.id);
                    Future.delayed(const Duration(seconds: 2), () {
                      if (mounted && _copiedMessageId == msg.id) {
                        setState(() => _copiedMessageId = null);
                      }
                    });
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isCopied ? Icons.check : Icons.copy_outlined,
                          size: 14,
                          color: isCopied
                              ? AppTheme.trustPillText
                              : AppTheme.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isCopied ? 'Copied' : 'Copy',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: isCopied
                                ? AppTheme.trustPillText
                                : AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),

                // Thumbs Up
                IconButton(
                  iconSize: 15,
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(),
                  icon: Icon(
                    isLiked ? Icons.thumb_up : Icons.thumb_up_outlined,
                    color: isLiked
                        ? AppTheme.primaryAccent
                        : AppTheme.textSecondary,
                  ),
                  tooltip: 'Helpful',
                  onPressed: () {
                    setState(() {
                      if (isLiked) {
                        _likedMessageIds.remove(msg.id);
                      } else {
                        _likedMessageIds.add(msg.id);
                        _dislikedMessageIds.remove(msg.id);
                      }
                    });
                  },
                ),
                const SizedBox(width: 4),

                // Thumbs Down
                IconButton(
                  iconSize: 15,
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(),
                  icon: Icon(
                    isDisliked ? Icons.thumb_down : Icons.thumb_down_outlined,
                    color: isDisliked
                        ? AppTheme.overduePillText
                        : AppTheme.textSecondary,
                  ),
                  tooltip: 'Not helpful',
                  onPressed: () {
                    setState(() {
                      if (isDisliked) {
                        _dislikedMessageIds.remove(msg.id);
                      } else {
                        _dislikedMessageIds.add(msg.id);
                        _likedMessageIds.remove(msg.id);
                      }
                    });
                  },
                ),
                const SizedBox(width: 4),

                // More Options Menu
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert,
                      size: 15, color: AppTheme.textSecondary),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  onSelected: (val) {
                    if (val == 'copy') {
                      Clipboard.setData(ClipboardData(text: msg.text));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Response copied to clipboard'),
                          duration: Duration(seconds: 2),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    } else if (val == 'regenerate') {
                      _regenerateResponse(msg);
                    }
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      value: 'copy',
                      child: Row(
                        children: [
                          Icon(Icons.content_copy,
                              size: 16, color: AppTheme.textPrimary),
                          SizedBox(width: 8),
                          Text('Copy text', style: TextStyle(fontSize: 13)),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'regenerate',
                      child: Row(
                        children: [
                          Icon(Icons.refresh,
                              size: 16, color: AppTheme.primaryAccent),
                          SizedBox(width: 8),
                          Text('Regenerate response',
                              style: TextStyle(fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                ),

                const Spacer(),

                // Timestamp
                Text(
                  _formatTime(msg.timestamp),
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCitationChip(BuildContext context, ChunkMatch match) {
    return InkWell(
      onTap: () => _showCitationModal(context, match),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: AppTheme.neutralPillFill,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.cardBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.menu_book,
                size: 12, color: AppTheme.primaryAccent),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                '${match.chunk.documentName} · p.${match.chunk.pageNumber}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCitationModal(BuildContext context, ChunkMatch match) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: AppTheme.cardBorder,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    const Icon(Icons.menu_book,
                        size: 18, color: AppTheme.primaryAccent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        match.chunk.documentName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.detectedPillFill,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Page ${match.chunk.pageNumber}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.detectedPillText,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${match.chunk.subject} • ${match.chunk.unit} • BM25 Score: ${match.score.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'VERIFIED SOURCE EXCERPT',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                    color: AppTheme.textInactive,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.neutralPillFill.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.cardBorder),
                  ),
                  child: Text(
                    match.chunk.text,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: AppTheme.textPrimary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    icon: const Icon(Icons.copy,
                        size: 14, color: AppTheme.primaryAccent),
                    label: const Text(
                      'Copy Citation Excerpt',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.primaryAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: match.chunk.text));
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).clearSnackBars();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Citation excerpt copied to clipboard'),
                          duration: Duration(seconds: 2),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _regenerateResponse(AcademicChatMessage assistantMsg) {
    final idx = _messages.indexOf(assistantMsg);
    if (idx <= 0) return;
    final priorUserMsg = _messages[idx - 1];
    if (!priorUserMsg.isUser) return;
    _inputController.text = priorUserMsg.text;
    _sendMessage();
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  Widget _buildInputBar() {
    final isRecording = _sttService.isRecording;
    final isTranscribing = _sttService.isTranscribing;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        color: AppTheme.cardSurface,
        border: Border(top: BorderSide(color: AppTheme.cardBorder)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Whisper Live Status Banner
            if (isRecording) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.overduePillFill,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: AppTheme.overduePillText.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    SizedBox(
                      width: 8,
                      height: 8,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppTheme.overduePillText,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Listening... Tap mic again to transcribe with On-Device Whisper',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.overduePillText,
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (isTranscribing) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.detectedPillFill,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: AppTheme.primaryAccent.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: AppTheme.primaryAccent,
                      ),
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Whisper Tiny INT8 converting speech to text locally...',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primaryAccent,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Input Controls Row
            Row(
              children: [
                // On-Device Whisper Microphone Button
                Container(
                  decoration: BoxDecoration(
                    color: isRecording
                        ? AppTheme.overduePillFill
                        : AppTheme.neutralPillFill,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isRecording
                          ? AppTheme.overduePillText
                          : AppTheme.cardBorder,
                      width: isRecording ? 1.5 : 1,
                    ),
                  ),
                  child: IconButton(
                    icon: isTranscribing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.primaryAccent,
                            ),
                          )
                        : Icon(
                            isRecording ? Icons.mic : Icons.mic_none,
                            color: isRecording
                                ? AppTheme.overduePillText
                                : AppTheme.primaryAccent,
                            size: 20,
                          ),
                    tooltip: isRecording
                        ? 'Stop recording & transcribe'
                        : 'Speak question (Whisper STT)',
                    onPressed: isTranscribing ? null : _toggleVoiceRecording,
                  ),
                ),
                const SizedBox(width: 8),

                // Text Input
                Expanded(
                  child: TextField(
                    controller: _inputController,
                    minLines: 1,
                    maxLines: 4,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppTheme.textPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: isRecording
                          ? 'Listening to your voice...'
                          : 'Ask Pal anything from your textbooks...',
                      hintStyle: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 13.5,
                      ),
                      isDense: true,
                      filled: true,
                      fillColor: AppTheme.canvasBg,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide:
                            const BorderSide(color: AppTheme.cardBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide:
                            const BorderSide(color: AppTheme.cardBorder),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide:
                            const BorderSide(color: AppTheme.primaryAccent),
                      ),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),

                // Send to LLM Button
                Container(
                  decoration: const BoxDecoration(
                    color: AppTheme.primaryAccent,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: _llmService.isGenerating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.arrow_upward, color: Colors.white),
                    onPressed: _sendMessage,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
