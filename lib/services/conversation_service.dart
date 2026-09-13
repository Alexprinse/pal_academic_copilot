import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/chat_message.dart';
import '../models/conversation_session.dart';
import '../models/rag_scope.dart';

class ConversationService extends ChangeNotifier {
  static final ConversationService instance = ConversationService._internal();
  ConversationService._internal();

  final List<ConversationSession> _conversations = [];
  String? _activeConversationId;
  bool _initialized = false;

  List<ConversationSession> get conversations =>
      List.unmodifiable(_conversations);

  bool get isInitialized => _initialized;

  ConversationSession? get activeConversation {
    if (_conversations.isEmpty) return null;
    if (_activeConversationId != null) {
      try {
        return _conversations.firstWhere((c) => c.id == _activeConversationId);
      } catch (_) {}
    }
    return _conversations.first;
  }

  String? get activeConversationId => _activeConversationId;

  @visibleForTesting
  void clearForTesting() {
    _conversations.clear();
    _activeConversationId = null;
    _initialized = false;
  }

  Future<void> init() async {
    if (_initialized) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/pal_conversations.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          final List<dynamic> decoded = jsonDecode(content);
          _conversations.clear();
          for (final item in decoded) {
            if (item is Map<String, dynamic>) {
              _conversations.add(ConversationSession.fromMap(item));
            }
          }
          _sortConversations();
          if (_conversations.isNotEmpty) {
            _activeConversationId = _conversations.first.id;
          }
        }
      }
    } catch (e) {
      debugPrint('Note: unable to load pal_conversations.json: $e');
    } finally {
      _initialized = true;
      notifyListeners();
    }
  }

  void _sortConversations() {
    _conversations.sort((a, b) {
      if (a.isPinned != b.isPinned) {
        return a.isPinned ? -1 : 1;
      }
      return b.updatedAt.compareTo(a.updatedAt);
    });
  }

  Future<ConversationSession> createConversation({
    String? initialTitle,
    String? initialRagScope,
    String? lectureId,
    String? lectureTitle,
    String? documentId,
    String? documentTitle,
    String? sourceType,
    String? backgroundContext,
    String? subjectId,
    String? subjectName,
    String? unitId,
    String? unitName,
    String? ragScopeType,
    RagScope? ragScope,
    AcademicChatMessage? initialMessage,
  }) async {
    final now = DateTime.now();
    final convId = 'conv_${now.millisecondsSinceEpoch}';

    final defaultWelcomeMessage = AcademicChatMessage(
      id: 'msg_welcome_${now.millisecondsSinceEpoch}',
      conversationId: convId,
      role: 'assistant',
      text:
          "Hi, I'm **Pal** — your personal academic copilot for lectures, notes, and textbooks.\n\nAsk me anything, or tap a suggestion below to begin studying.",
      timestamp: now,
    );

    final session = ConversationSession(
      id: convId,
      title: initialTitle ?? 'New Chat',
      createdAt: now,
      updatedAt: now,
      selectedRagScope: initialRagScope ?? 'Operating Systems · Unit 1',
      messages: [initialMessage ?? defaultWelcomeMessage],
      isPinned: false,
      lectureId: lectureId,
      lectureTitle: lectureTitle,
      documentId: documentId,
      documentTitle: documentTitle,
      sourceType: sourceType,
      backgroundContext: backgroundContext,
      ragScopeType: ragScopeType ?? ragScope?.type.name,
      subjectId: subjectId ?? ragScope?.subjectId,
      subjectName: subjectName ?? ragScope?.subjectName,
      unitId: unitId ?? ragScope?.unitId,
      unitName: unitName ?? ragScope?.unitName,
      ragScope: ragScope,
    );

    _conversations.insert(0, session);
    _sortConversations();
    _activeConversationId = session.id;

    notifyListeners();
    _saveToDisk();
    return session;
  }

  ConversationSession? findConversationByLectureId(String lectureId) {
    try {
      return _conversations.firstWhere((c) => c.lectureId == lectureId);
    } catch (_) {
      return null;
    }
  }

  ConversationSession? findConversationByDocumentId(String documentId) {
    try {
      return _conversations.firstWhere((c) => c.documentId == documentId);
    } catch (_) {
      return null;
    }
  }

  Future<void> setActiveConversation(String conversationId) async {
    if (_activeConversationId == conversationId) return;
    final exists = _conversations.any((c) => c.id == conversationId);
    if (exists) {
      _activeConversationId = conversationId;
      notifyListeners();
    }
  }

  Future<void> saveConversation(ConversationSession conversation) async {
    final index = _conversations.indexWhere((c) => c.id == conversation.id);
    conversation.updatedAt = DateTime.now();

    if (index >= 0) {
      _conversations[index] = conversation;
    } else {
      _conversations.insert(0, conversation);
    }

    _sortConversations();
    notifyListeners();
    _saveToDisk();
  }

  Future<void> deleteConversation(String conversationId) async {
    _conversations.removeWhere((c) => c.id == conversationId);
    if (_activeConversationId == conversationId) {
      if (_conversations.isNotEmpty) {
        _activeConversationId = _conversations.first.id;
      } else {
        _activeConversationId = null;
      }
    }
    notifyListeners();
    _saveToDisk();
  }

  Future<void> renameConversation(
      String conversationId, String newTitle) async {
    final clean = newTitle.trim();
    if (clean.isEmpty) return;

    final index = _conversations.indexWhere((c) => c.id == conversationId);
    if (index >= 0) {
      _conversations[index].title = clean;
      _conversations[index].updatedAt = DateTime.now();
      _sortConversations();
      notifyListeners();
      _saveToDisk();
    }
  }

  Future<void> togglePinConversation(String conversationId) async {
    final index = _conversations.indexWhere((c) => c.id == conversationId);
    if (index >= 0) {
      _conversations[index].isPinned = !_conversations[index].isPinned;
      _sortConversations();
      notifyListeners();
      _saveToDisk();
    }
  }

  List<ConversationSession> searchConversations(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return conversations;

    return _conversations.where((conv) {
      if (conv.title.toLowerCase().contains(q)) return true;
      for (final msg in conv.messages) {
        if (msg.text.toLowerCase().contains(q)) return true;
      }
      return false;
    }).toList();
  }

  Future<void> _saveToDisk() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/pal_conversations.json');
      final data = _conversations.map((c) => c.toMap()).toList();
      await file.writeAsString(jsonEncode(data), flush: true);
    } catch (e) {
      debugPrint('Error saving pal_conversations.json: $e');
    }
  }

  /// Lightweight, deterministic title generator.
  /// Does NOT call the local LLM.
  static String generateTitle(String userPrompt) {
    String clean = userPrompt.trim();
    if (clean.isEmpty) return 'Study Chat';

    final lower = clean.toLowerCase();

    // Pattern 1: "Explain the difference between TCP and UDP" -> "TCP vs UDP"
    final diffRegExp = RegExp(
      r'^(?:can you\s+)?(?:please\s+)?(?:explain\s+)?(?:the\s+)?difference\s+between\s+(.+?)\s+and\s+(.+?)[\?\.\!]?$',
      caseSensitive: false,
    );
    final diffMatch = diffRegExp.firstMatch(clean);
    if (diffMatch != null) {
      final partA = diffMatch.group(1)?.trim() ?? '';
      final partB = diffMatch.group(2)?.trim() ?? '';
      if (partA.isNotEmpty && partB.isNotEmpty) {
        return '${_capitalize(partA)} vs ${_capitalize(partB)}';
      }
    }

    // Pattern 2: "What assignments are due this week?" / "Deadlines"
    if (lower.contains('assignment') &&
        (lower.contains('due') || lower.contains('deadline'))) {
      return 'Upcoming assignments';
    }
    if (lower.contains('deadline') || lower.contains('schedule due')) {
      return 'Upcoming deadlines';
    }

    // Pattern 3: "Summarize Unit 3" -> "Unit 3 Summary"
    final summarizeRegExp = RegExp(
      r'^(?:can you\s+)?(?:please\s+)?(?:summarize|give me a summary of)\s+(.+?)[\?\.\!]?$',
      caseSensitive: false,
    );
    final sumMatch = summarizeRegExp.firstMatch(clean);
    if (sumMatch != null) {
      final subject = sumMatch.group(1)?.trim() ?? '';
      if (subject.isNotEmpty) {
        return '${_capitalize(subject)} Summary';
      }
    }

    // Pattern 4: General prefix stripping
    final prefixes = [
      'can you please explain to me ',
      'can you please explain ',
      'could you please explain ',
      'can you explain ',
      'could you explain ',
      'explain to me ',
      'explain the ',
      'explain ',
      'what are the differences between ',
      'what is the difference between ',
      'what are the ',
      'what are ',
      'what is the ',
      'what is ',
      'tell me about the ',
      'tell me about ',
      'can you tell me about ',
      'how does the ',
      'how does ',
      'how do the ',
      'how do ',
      'quiz me on ',
      'test me on ',
      'give me questions on ',
      'find my ',
      'find ',
      'help me with ',
      'help me understand ',
      'notes for ',
    ];

    for (final prefix in prefixes) {
      if (lower.startsWith(prefix)) {
        clean = clean.substring(prefix.length).trim();
        break;
      }
    }

    // Strip trailing punctuation
    clean = clean.replaceAll(RegExp(r'[\?\.\!\,\;\:]+$'), '').trim();

    if (clean.isEmpty) {
      return 'Study Session';
    }

    // Truncate cleanly at word boundary up to 34 characters
    if (clean.length > 34) {
      final truncated = clean.substring(0, 34);
      final lastSpace = truncated.lastIndexOf(' ');
      if (lastSpace > 16) {
        clean = truncated.substring(0, lastSpace).trim();
      } else {
        clean = truncated.trim();
      }
    }

    return _capitalize(clean);
  }

  static String _capitalize(String s) {
    if (s.isEmpty) return s;
    final words = s.split(' ');
    final capitalized = words.map((w) {
      if (w.isEmpty) return w;
      if (w.length <= 3 && w == w.toUpperCase()) {
        return w; // Acronym like TCP, UDP, OS
      }
      return w[0].toUpperCase() + w.substring(1);
    }).join(' ');
    return capitalized;
  }
}
