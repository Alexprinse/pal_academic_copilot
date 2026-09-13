import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Lightweight normalization and vocabulary biasing layer for Pal Agent voice commands.
/// Corrects known phonetic Whisper Tiny artifacts on academic terms without hallucinating.
class VoiceCommandNormalizer {
  static const List<String> academicHotwords = [
    'Hey Pal',
    'Pal',
    'schedule a class',
    'schedule',
    'timetable',
    'Data Structures',
    'Operating Systems',
    'Computer Networks',
    'Discrete Mathematics',
    'Engineering Physics',
    'Artificial Intelligence',
    'Database Systems',
    'assignment',
    'deadline',
    'homework',
    '10 to 11',
    '10 AM',
    '11 AM',
    'TCP',
    'UDP',
    'IP address',
    'subnetting',
    'Peterson',
    'semaphores',
    'lecture',
    'record',
  ];

  /// Prepares a hotwords file on disk for Sherpa-ONNX
  static Future<String?> prepareHotwordsFile() async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final file = File('${docsDir.path}/pal_hotwords.txt');
      final content = academicHotwords.join('\n');
      await file.writeAsString(content);
      return file.path;
    } catch (e) {
      debugPrint('[VOICE] Notice: unable to write hotwords file: $e');
      return null;
    }
  }

  /// Normalizes spoken transcripts to correct common speech-to-text phonetic confusions,
  /// wake-word misrecognitions, and academic term variations.
  static String normalize(String rawTranscript,
      {List<String>? candidateSubjects}) {
    var text = rawTranscript.trim();
    if (text.isEmpty) return text;

    // 1. Correct wake-word variations at the start:
    // Native STT often transcribes "Hey Pal" as "Hebbal", "Hey Paul", "A Pal", "Hi Paul", "Apple", etc.
    text = text.replaceFirst(
      RegExp(
          r'^(?:(?:hey|hi|a|ok|he)?\s*(?:pal|paul|hebbal|apple|bell)|hebbal|apple)[,\s]*',
          caseSensitive: false),
      'Hey Pal, ',
    );

    // 2. Correct time period formatting: "a.m." -> "AM", "p.m." -> "PM"
    text = text.replaceAll(RegExp(r'a\.m\.?', caseSensitive: false), 'AM');
    text = text.replaceAll(RegExp(r'p\.m\.?', caseSensitive: false), 'PM');

    // 3. Correct "Tinto Levin" / "tin to eleven" / "ten to eleven" -> "10 to 11"
    text = text.replaceAll(
      RegExp(r'\b(?:of\s+)?tinto\s+levin\b', caseSensitive: false),
      'at 10 to 11',
    );
    text = text.replaceAll(
      RegExp(r'\btin\s+to\s+eleven\b', caseSensitive: false),
      '10 to 11',
    );
    text = text.replaceAll(
      RegExp(r'\bten\s+to\s+eleven\b', caseSensitive: false),
      '10 to 11',
    );

    // 4. Correct "The people and the lecture" in command position -> "Hey Pal, schedule a class"
    text = text.replaceAll(
      RegExp(
          r'^(?:the\s+people\s+and\s+the\s+lecture|the\s+people\s+schedule)\b',
          caseSensitive: false),
      'Hey Pal, schedule a class',
    );

    // 5. Academic course name canonicalization and phonetic error corrections
    // Native STT often hears "Data Structures" as "data stitches", "data structure"
    text = text.replaceAll(
      RegExp(r'\bdata\s+(?:stitches|structure)\b', caseSensitive: false),
      'Data Structures',
    );
    text = text.replaceAll(
      RegExp(r'\bdata\s+structures?\b', caseSensitive: false),
      'Data Structures',
    );
    text = text.replaceAll(
      RegExp(r'\boperating\s+systems?\b', caseSensitive: false),
      'Operating Systems',
    );
    text = text.replaceAll(
      RegExp(r'\bcomputer\s+networks?\b', caseSensitive: false),
      'Computer Networks',
    );
    text = text.replaceAll(
      RegExp(r'\bdiscrete\s+math(?:ematics)?\b', caseSensitive: false),
      'Discrete Mathematics',
    );
    text = text.replaceAll(
      RegExp(r'\bengineering\s+physics\b', caseSensitive: false),
      'Engineering Physics',
    );
    text = text.replaceAll(
      RegExp(r'\bartificial\s+intelligence\b', caseSensitive: false),
      'Artificial Intelligence',
    );
    text = text.replaceAll(
      RegExp(r'\bdatabase\s+systems?\b', caseSensitive: false),
      'Database Systems',
    );

    // 6. Fuzzy match against user's actual timetable subjects if provided
    if (candidateSubjects != null && candidateSubjects.isNotEmpty) {
      text = _fuzzyMatchSubjects(text, candidateSubjects);
    }

    // 7. Technical acronyms
    text = text.replaceAll(
        RegExp(r'\bECB\b|\be\s+c\s+b\b', caseSensitive: false), 'TCP');
    text = text.replaceAll(
        RegExp(r'\bUCP\b|\bu\s+c\s+p\b', caseSensitive: false), 'UDP');

    return text.trim();
  }

  /// Fuzzy-matches transcript tokens against user timetable subjects
  static String _fuzzyMatchSubjects(String text, List<String> subjects) {
    var result = text;
    for (final subject in subjects) {
      if (subject.trim().isEmpty) continue;
      final subLower = subject.trim().toLowerCase();
      // If already present, continue
      if (result.toLowerCase().contains(subLower)) continue;

      final subTokens = subLower.split(RegExp(r'\s+'));
      if (subTokens.isEmpty) continue;

      // Check if the first token matches or close match
      final words = result.split(RegExp(r'\s+'));
      for (int i = 0; i <= words.length - subTokens.length; i++) {
        final phrase =
            words.sublist(i, i + subTokens.length).join(' ').toLowerCase();
        if (_similarity(phrase, subLower) >= 0.70) {
          final originalPhrase =
              words.sublist(i, i + subTokens.length).join(' ');
          result = result.replaceFirst(originalPhrase, subject);
          break;
        }
      }
    }
    return result;
  }

  /// Computes Dice coefficient similarity between two strings
  static double _similarity(String s1, String s2) {
    if (s1 == s2) return 1.0;
    if (s1.length < 2 || s2.length < 2) return 0.0;

    final bigrams1 = <String>{};
    for (int i = 0; i < s1.length - 1; i++) {
      bigrams1.add(s1.substring(i, i + 2));
    }

    int matches = 0;
    for (int i = 0; i < s2.length - 1; i++) {
      if (bigrams1.contains(s2.substring(i, i + 2))) {
        matches++;
      }
    }

    return (2.0 * matches) / ((s1.length - 1) + (s2.length - 1));
  }
}
