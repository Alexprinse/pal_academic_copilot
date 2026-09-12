import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../models/chat_message.dart';
import '../models/conversation_session.dart';
import '../models/llm_model_preset.dart';
import '../models/vault_item.dart';
import '../services/conversation_service.dart';
import '../services/llm_service.dart';
import '../services/rag_service.dart';
import '../services/stt_service.dart';
import '../theme/app_theme.dart';
import '../widgets/chat_history_drawer.dart';

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
  final ConversationService _conversationService = ConversationService.instance;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  ConversationSession? _activeSession;

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
    _conversationService.addListener(_onConversationServiceUpdate);

    if (widget.initialFilterSubject != null ||
        widget.initialFilterUnit != null) {
      _selectedRagScope = widget.initialFilterUnit ??
          widget.initialFilterSubject ??
          'All Notes';
    }

    _initActiveSession();

    if (widget.initialQuery != null && widget.initialQuery!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _inputController.text = widget.initialQuery!;
        _sendMessage();
      });
    }
  }

  void _initActiveSession() {
    final active = _conversationService.activeConversation;
    if (active != null) {
      _activeSession = active;
      _selectedRagScope = active.selectedRagScope;
      _messages.clear();
      _messages.addAll(active.messages);
    } else {
      final now = DateTime.now();
      final convId = 'conv_${now.millisecondsSinceEpoch}';
      final welcomeMsg = AcademicChatMessage(
        id: 'msg-welcome',
        conversationId: convId,
        role: 'assistant',
        text:
            "Hi, I'm **Pal** — your personal academic copilot for lectures, notes, and textbooks.\n\nAsk me anything, or tap a suggestion below to begin studying.",
        timestamp: now,
      );
      _activeSession = ConversationSession(
        id: convId,
        title: 'New Chat',
        createdAt: now,
        updatedAt: now,
        selectedRagScope: _selectedRagScope,
        messages: [welcomeMsg],
      );
      _messages.clear();
      _messages.add(welcomeMsg);
      _conversationService.saveConversation(_activeSession!);
    }
  }

  void _onConversationServiceUpdate() {
    if (!mounted) return;
    final currentActive = _conversationService.activeConversation;
    if (currentActive == null) {
      _initActiveSession();
      setState(() {});
    } else if (_activeSession != null &&
        !_conversationService.conversations
            .any((c) => c.id == _activeSession!.id)) {
      _selectConversation(currentActive);
    } else {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _llmService.removeListener(_onLlmUpdate);
    _sttService.removeListener(_onSttUpdate);
    _conversationService.removeListener(_onConversationServiceUpdate);
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
      if (_activeSession != null) {
        _activeSession!.selectedRagScope = ragScope;
        _conversationService.saveConversation(_activeSession!);
      }
    }
    _inputController.text = query;
    _sendMessage();
  }

  @visibleForTesting
  void addMessageForTesting(AcademicChatMessage message) {
    setState(() {
      _messages.add(message);
      _activeSession?.messages.add(message);
    });
  }

  @visibleForTesting
  ConversationSession? get activeSessionForTesting => _activeSession;

  @visibleForTesting
  void showModelSwitcherForTesting() {
    _showModelSwitcherModal();
  }

  Future<void> _promptOrStartNewChat() async {
    if (_llmService.isGenerating) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please wait for current response to finish.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final hasUserMessages = _messages.any((m) => m.isUser);
    if (!hasUserMessages) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppTheme.cardBorder),
        ),
        title: const Text(
          'Start a new chat?',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        content: const Text(
          'Your current conversation will be safely saved in Chat History.',
          style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryAccent,
              foregroundColor: AppTheme.primaryButtonText,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('New Chat'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _startNewChat();
    }
  }

  Future<void> _startNewChat() async {
    if (_activeSession != null) {
      _activeSession!.messages.clear();
      _activeSession!.messages.addAll(_messages);
      _activeSession!.selectedRagScope = _selectedRagScope;
      await _conversationService.saveConversation(_activeSession!);
    }

    final newSession = await _conversationService.createConversation(
      initialRagScope: _selectedRagScope,
    );

    setState(() {
      _activeSession = newSession;
      _messages.clear();
      _messages.addAll(newSession.messages);
      _selectedRagScope = newSession.selectedRagScope;
      _inputController.clear();
    });
  }

  Future<void> _selectConversation(ConversationSession conversation) async {
    if (_activeSession?.id == conversation.id) return;

    if (_activeSession != null) {
      _activeSession!.messages.clear();
      _activeSession!.messages.addAll(_messages);
      _activeSession!.selectedRagScope = _selectedRagScope;
      await _conversationService.saveConversation(_activeSession!);
    }

    await _conversationService.setActiveConversation(conversation.id);

    setState(() {
      _activeSession = conversation;
      _messages.clear();
      _messages.addAll(conversation.messages);
      _selectedRagScope = conversation.selectedRagScope;
      _inputController.clear();
    });

    _scrollToBottom();
  }

  Future<void> _sendMessage() async {
    final query = _inputController.text.trim();
    if (query.isEmpty || _llmService.isGenerating) return;

    _inputController.clear();

    _activeSession ??= await _conversationService.createConversation(
      initialRagScope: _selectedRagScope,
    );

    if (_activeSession!.userMessagesCount == 0) {
      final autoTitle = ConversationService.generateTitle(query);
      _activeSession!.title = autoTitle;
    }

    final targetConvId = _activeSession!.id;

    // 1. Add User Message
    final userMsg = AcademicChatMessage(
      id: 'usr_${DateTime.now().millisecondsSinceEpoch}',
      conversationId: targetConvId,
      role: 'user',
      text: query,
      timestamp: DateTime.now(),
    );
    _messages.add(userMsg);
    _activeSession!.messages.add(userMsg);
    await _conversationService.saveConversation(_activeSession!);

    setState(() {});
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
          final ocrTag =
              m.chunk.isOcr ? ' (${m.chunk.extractionType.label})' : '';
          contextBuffer.writeln(
              '[Source ${i + 1}: ${m.chunk.subject} > ${m.chunk.unit} (${m.chunk.documentName}, p.${m.chunk.pageNumber}$ocrTag)]:');
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
      conversationId: targetConvId,
      role: 'assistant',
      text: '',
      timestamp: DateTime.now(),
      citations: citations,
      isGenerating: true,
    );
    _messages.add(assistantMsg);
    _activeSession!.messages.add(assistantMsg);
    setState(() {});
    _scrollToBottom();

    // Collect prior multi-turn context (excluding welcome msg, userMsg, and assistantMsg)
    final history = _messages
        .where((m) =>
            m.id != 'msg-welcome' &&
            m.id != userMsg.id &&
            m.id != assistantMsg.id &&
            !m.isGenerating &&
            m.text.trim().isNotEmpty)
        .toList();
    final recentHistory =
        history.length > 6 ? history.sublist(history.length - 6) : history;

    // 4. Stream Tokens from Llama.cpp Engine
    try {
      final tokenStream = _llmService.generateStreaming(
        prompt: promptForLlm,
        systemPrompt:
            'You are Pal, an expert university academic copilot running on-device.',
        maxTokens: 512,
        conversationHistory: recentHistory,
      );

      await for (final token in tokenStream) {
        assistantMsg.text += token;
        assistantMsg.tokensPerSecond = _llmService.currentTps;

        // Only trigger UI re-render if current active conversation is targetConvId
        if (mounted && _activeSession?.id == targetConvId) {
          setState(() {});
          _scrollToBottom();
        }
      }
    } finally {
      assistantMsg.isGenerating = false;

      final sessionToSave = _conversationService.conversations
          .cast<ConversationSession?>()
          .firstWhere((c) => c?.id == targetConvId, orElse: () => null);
      if (sessionToSave != null) {
        await _conversationService.saveConversation(sessionToSave);
      } else if (_activeSession?.id == targetConvId) {
        await _conversationService.saveConversation(_activeSession!);
      }

      if (mounted && _activeSession?.id == targetConvId) {
        setState(() {});
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
      key: _scaffoldKey,
      drawer: ChatHistoryDrawer(
        activeConversationId: _activeSession?.id,
        onSelectConversation: _selectConversation,
        onNewChat: _startNewChat,
      ),
      backgroundColor: AppTheme.canvasBg,
      appBar: AppBar(
        backgroundColor: AppTheme.canvasBg,
        elevation: 0,
        centerTitle: false,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.menu, color: AppTheme.textPrimary, size: 22),
          tooltip: 'Chat History',
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: AppTheme.highlightBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppTheme.primaryAccent.withValues(alpha: 0.35),
                ),
              ),
              child: const Center(
                child: Icon(Icons.auto_awesome,
                    size: 14, color: AppTheme.primaryAccent),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Pal Brain',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: AppTheme.trustPillFill,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.shield_outlined,
                                size: 9, color: AppTheme.trustPillText),
                            SizedBox(width: 2.5),
                            Text(
                              'On-device',
                              style: TextStyle(
                                fontSize: 8.5,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.trustPillText,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  Text(
                    _activeSession != null &&
                            _activeSession!.userMessagesCount > 0
                        ? _activeSession!.title
                        : 'Your personal academic copilot',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          // Subtle New Chat button matching Pal palette
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: _promptOrStartNewChat,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: AppTheme.neutralPillFill,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.cardBorder, width: 0.8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add, size: 14, color: AppTheme.textPrimary),
                  SizedBox(width: 3),
                  Text(
                    'New',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 2),
          IconButton(
            icon: const Icon(Icons.tune_outlined,
                color: AppTheme.primaryAccent, size: 20),
            tooltip: 'Model Settings & Diagnostics',
            onPressed: _showModelSwitcherModal,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // 1. Compact Contextual Control Bar
          _buildContextBar(),

          // 2. Chat Message Stream with Conversational Suggestions
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              itemCount: _messages.length + (_messages.length <= 1 ? 1 : 0),
              itemBuilder: (context, index) {
                if (index < _messages.length) {
                  return _buildChatBubble(_messages[index]);
                }
                return _buildQuickSuggestions();
              },
            ),
          ),

          // 3. Bottom Input Composer
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildContextBar() {
    final hasContext = _selectedRagScope != 'Off';
    final isDownloading = _llmService.downloadingPreset != null;
    final downloading = _llmService.downloadingPreset;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      decoration: BoxDecoration(
        color: AppTheme.canvasBg,
        border: Border(
          bottom: BorderSide(
            color: AppTheme.cardBorder.withValues(alpha: 0.6),
            width: 0.8,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              InkWell(
                onTap: _showScopePickerModal,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
                  decoration: BoxDecoration(
                    color: hasContext
                        ? AppTheme.highlightBg
                        : AppTheme.neutralPillFill,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: hasContext
                          ? AppTheme.primaryAccent.withValues(alpha: 0.45)
                          : AppTheme.cardBorder,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        hasContext ? Icons.menu_book : Icons.public,
                        size: 13,
                        color: hasContext
                            ? AppTheme.primaryAccent
                            : AppTheme.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        hasContext
                            ? 'Context: $_selectedRagScope'
                            : 'General Knowledge (No Vault)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: hasContext
                              ? AppTheme.textPrimary
                              : AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.keyboard_arrow_down,
                        size: 14,
                        color: hasContext
                            ? AppTheme.primaryAccent
                            : AppTheme.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              if (hasContext)
                Text(
                  '${_ragService.totalIndexedChunks} sources',
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: AppTheme.textSecondary,
                  ),
                ),
            ],
          ),
          if (isDownloading && downloading != null) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: downloading.downloadProgress,
                backgroundColor: AppTheme.neutralPillFill,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(AppTheme.primaryAccent),
                minHeight: 3,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Downloading ${downloading.name}...',
                  style: const TextStyle(
                      fontSize: 9.5, color: AppTheme.textSecondary),
                ),
                Text(
                  '${(downloading.downloadProgress * 100).toStringAsFixed(0)}% • ${downloading.downloadSpeedMbps.toStringAsFixed(1)} MB/s',
                  style: const TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primaryAccent,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _showScopePickerModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
                const Text(
                  'Academic Context Scope',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Select the textbook or lecture note units Pal uses for grounded answers and citations.',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 16),
                _buildScopeOptionTile(
                  title: 'Unit 1 (OS)',
                  subtitle:
                      'Operating Systems · Process Synchronization & Concurrency',
                  scopeKey: 'Unit 1 (OS)',
                  icon: Icons.menu_book,
                  modalContext: ctx,
                ),
                _buildScopeOptionTile(
                  title: 'All Notes',
                  subtitle: 'Search across all indexed subjects in Study Vault',
                  scopeKey: 'All Notes',
                  icon: Icons.library_books_outlined,
                  modalContext: ctx,
                ),
                _buildScopeOptionTile(
                  title: 'Off (General Knowledge)',
                  subtitle:
                      'Rely on on-device LLM general knowledge without Vault retrieval',
                  scopeKey: 'Off',
                  icon: Icons.public,
                  modalContext: ctx,
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildScopeOptionTile({
    required String title,
    required String subtitle,
    required String scopeKey,
    required IconData icon,
    required BuildContext modalContext,
  }) {
    final isSelected = _selectedRagScope == scopeKey;
    return InkWell(
      onTap: () {
        setState(() => _selectedRagScope = scopeKey);
        if (_activeSession != null) {
          _activeSession!.selectedRagScope = scopeKey;
          _conversationService.saveConversation(_activeSession!);
        }
        Navigator.pop(modalContext);
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.highlightBg
              : AppTheme.neutralPillFill.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppTheme.primaryAccent : AppTheme.cardBorder,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 20,
                color: isSelected
                    ? AppTheme.primaryAccent
                    : AppTheme.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w600,
                      color: isSelected
                          ? AppTheme.primaryAccent
                          : AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                        fontSize: 11, color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle,
                  size: 18, color: AppTheme.primaryAccent),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickSuggestions() {
    final suggestions = _selectedRagScope != 'Off'
        ? [
            'Explain the core principles of $_selectedRagScope',
            'Summarize my uploaded notes for this topic',
            'Quiz me with 3 practice exam questions',
            'Find my upcoming assignment deadlines',
          ]
        : [
            'Explain TCP vs UDP simply',
            'Summarize my uploaded lecture notes',
            'Quiz me on operating systems concepts',
            'Find my upcoming assignment deadlines',
          ];

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text(
              _selectedRagScope != 'Off'
                  ? 'Suggested for $_selectedRagScope:'
                  : 'Try asking:',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
                letterSpacing: 0.2,
              ),
            ),
          ),
          ...suggestions.map((prompt) => _buildPromptSuggestionCard(prompt)),
        ],
      ),
    );
  }

  Widget _buildPromptSuggestionCard(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => setQuery(text),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.cardSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.cardBorder),
          ),
          child: Row(
            children: [
              const Icon(Icons.auto_awesome,
                  size: 14, color: AppTheme.primaryAccent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              const Icon(Icons.arrow_forward_ios,
                  size: 11, color: AppTheme.textInactive),
            ],
          ),
        ),
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
        margin: const EdgeInsets.only(bottom: 14, left: 56),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.highlightBg,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(4),
          ),
          border: Border.all(
            color: AppTheme.primaryAccent.withValues(alpha: 0.25),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              msg.text,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 14,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              _formatTime(msg.timestamp),
              style: const TextStyle(
                fontSize: 9.5,
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
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.cardSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.cardBorder),
          boxShadow: AppTheme.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Header: Avatar + Pal Title + Optional Speed badge
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: AppTheme.highlightBg,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppTheme.primaryAccent.withValues(alpha: 0.35),
                        ),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.auto_awesome,
                          size: 13,
                          color: AppTheme.primaryAccent,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Pal',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
                if (msg.tokensPerSecond != null && msg.tokensPerSecond! > 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.neutralPillFill,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppTheme.cardBorder,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.bolt,
                            size: 11, color: AppTheme.primaryAccent),
                        const SizedBox(width: 2),
                        Text(
                          '${msg.tokensPerSecond!.toStringAsFixed(1)} tok/s',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),

            // 2. Body: Markdown response or thinking state
            if (msg.text.isEmpty && msg.isGenerating)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: const [
                    SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.8,
                        color: AppTheme.primaryAccent,
                      ),
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Pal is thinking…',
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
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    height: 1.35,
                  ),
                  h2: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 15.5,
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

            // 3. Citations Section (if any)
            if (msg.citations.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'SOURCES',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: AppTheme.textInactive,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: msg.citations
                    .map((c) => _buildCitationChip(context, c))
                    .toList(),
              ),
            ],

            // 4. Action Row: Copy, Feedback, More Options, Timestamp (Only shown once completed)
            if (!msg.isGenerating) ...[
              const SizedBox(height: 10),
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 4),
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
                  const SizedBox(width: 4),

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
                  const SizedBox(width: 2),

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
                  const SizedBox(width: 2),

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
                '${match.chunk.documentName} · p.${match.chunk.pageNumber}${match.chunk.isOcr ? ' (OCR)' : ''}',
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
                    if (match.chunk.isOcr) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.trustPillFill,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          match.chunk.extractionType.label,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.trustPillText,
                          ),
                        ),
                      ),
                    ],
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

    String hintText;
    if (isRecording) {
      hintText = 'Listening to your voice...';
    } else if (_selectedRagScope != 'Off') {
      hintText = 'Ask Pal about $_selectedRagScope...';
    } else {
      hintText = 'Ask Pal about your notes, lectures...';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        border: Border(
          top: BorderSide(
            color: AppTheme.cardBorder.withValues(alpha: 0.7),
            width: 0.8,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Voice status banner
            if (isRecording) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.overduePillFill,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.overduePillText.withValues(alpha: 0.3),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 7,
                      height: 7,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppTheme.overduePillText,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Listening… Tap mic to finish',
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
                margin: const EdgeInsets.only(bottom: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.detectedPillFill,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.primaryAccent.withValues(alpha: 0.3),
                  ),
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
                    SizedBox(width: 6),
                    Text(
                      'Transcribing with On-Device Whisper...',
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
                // Voice input button
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isRecording
                        ? AppTheme.overduePillFill
                        : AppTheme.neutralPillFill,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isRecording
                          ? AppTheme.overduePillText
                          : AppTheme.cardBorder,
                    ),
                  ),
                  child: IconButton(
                    padding: EdgeInsets.zero,
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
                            size: 19,
                          ),
                    tooltip: isRecording
                        ? 'Stop recording & transcribe'
                        : 'Voice Input',
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
                      hintText: hintText,
                      hintStyle: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 13.5,
                      ),
                      isDense: true,
                      filled: true,
                      fillColor: AppTheme.canvasBg,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide:
                            const BorderSide(color: AppTheme.cardBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide:
                            const BorderSide(color: AppTheme.cardBorder),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
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
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    color: AppTheme.primaryAccent,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: _llmService.isGenerating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.arrow_upward,
                            color: Colors.white, size: 20),
                    tooltip: 'Send question',
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
