import 'package:flutter/foundation.dart';

import '../utils/paragraph_summary.dart';
import '../utils/text_rank.dart';

abstract class SummaryService {
  Future<String> summarizeTranscript(String transcript);
}

class LocalSummaryService implements SummaryService {
  static const int _maxKeyPoints = 4;

  const LocalSummaryService();

  @override
  Future<String> summarizeTranscript(String transcript) async {
    final normalizedTranscript = transcript.trim();
    if (normalizedTranscript.isEmpty) {
      return ParagraphSummary.fromTranscript(normalizedTranscript);
    }

    final sentences = TextRank.splitSentences(normalizedTranscript);
    if (sentences.isEmpty) {
      return _fallbackToKeyPoints(normalizedTranscript);
    }

    try {
      final keyPoints = await TextRank.extractKeyPoints(
        sentences,
        topN:
            sentences.length < _maxKeyPoints ? sentences.length : _maxKeyPoints,
        windowSize: 24,
      );
      final normalizedKeyPoints = _normalizeKeyPoints(keyPoints);
      if (normalizedKeyPoints.isNotEmpty) {
        return normalizedKeyPoints
            .map((point) => '• ${_ensureTerminalPunctuation(point)}')
            .join('\n');
      }
    } catch (error) {
      debugPrint(
          'LocalSummaryService falling back to paragraph summary: $error');
    }

    return _fallbackToKeyPoints(normalizedTranscript);
  }

  Future<String> _fallbackToKeyPoints(String transcript) async {
    final paragraph = await ParagraphSummary.fromTranscript(transcript);
    final sentences = _normalizeKeyPoints(TextRank.splitSentences(paragraph));
    if (sentences.isEmpty) {
      return paragraph;
    }
    return sentences
        .map((sentence) => '• ${_ensureTerminalPunctuation(sentence)}')
        .join('\n');
  }

  List<String> _normalizeKeyPoints(List<String> candidates) {
    final deduped = <String>[];
    final seen = <String>{};

    for (final candidate in candidates) {
      final normalized = candidate.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (normalized.length < 4) continue;

      final key = normalized.toLowerCase();
      if (seen.add(key)) {
        deduped.add(normalized);
      }
    }

    return deduped;
  }

  String _ensureTerminalPunctuation(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return trimmed;
    if (RegExp(r'[。．.!?！？…]$').hasMatch(trimmed)) return trimmed;
    return '$trimmed。';
  }
}
