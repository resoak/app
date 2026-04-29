import 'package:flutter/foundation.dart';

import '../utils/embedding_extractive_ranker.dart';
import '../utils/paragraph_summary.dart';
import '../utils/text_rank.dart';
import 'minilm_runtime_service.dart';

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
      final normalizedKeyPoints = normalizeKeyPoints(keyPoints);
      if (normalizedKeyPoints.isNotEmpty) {
        return formatSummaryBullets(normalizedKeyPoints);
      }
    } catch (error) {
      debugPrint(
          'LocalSummaryService falling back to paragraph summary: $error');
    }

    return _fallbackToKeyPoints(normalizedTranscript);
  }

  Future<String> _fallbackToKeyPoints(String transcript) async {
    final paragraph = await ParagraphSummary.fromTranscript(transcript);
    final sentences = normalizeKeyPoints(TextRank.splitSentences(paragraph));
    if (sentences.isEmpty) {
      return paragraph;
    }
    return formatSummaryBullets(sentences);
  }
}

class MiniLmSummaryService implements SummaryService {
  static const int _maxCandidateSentences = 24;
  static const int _maxKeyPoints = 4;

  const MiniLmSummaryService({
    SentenceEmbeddingRuntime? runtime,
    SummaryService? fallbackService,
  })  : _runtime = runtime ?? const MiniLmRuntimeService(),
        _fallbackService = fallbackService ?? const LocalSummaryService();

  final SentenceEmbeddingRuntime _runtime;
  final SummaryService _fallbackService;

  @override
  Future<String> summarizeTranscript(String transcript) async {
    final normalizedTranscript = transcript.trim();
    if (normalizedTranscript.isEmpty) {
      return _fallbackService.summarizeTranscript(normalizedTranscript);
    }

    final candidates = normalizeKeyPoints(
      TextRank.splitSentences(normalizedTranscript),
    ).take(_maxCandidateSentences).toList(growable: false);
    if (candidates.length < 2) {
      return _fallbackService.summarizeTranscript(normalizedTranscript);
    }

    try {
      final embeddings = await _runtime.embedSentences(candidates);
      final keyPoints = EmbeddingExtractiveRanker.selectKeyPoints(
        sentences: candidates,
        embeddings: embeddings,
        maxKeyPoints: _maxKeyPoints,
      );
      final normalizedKeyPoints = normalizeKeyPoints(keyPoints);
      if (normalizedKeyPoints.isNotEmpty) {
        return formatSummaryBullets(normalizedKeyPoints);
      }
    } catch (error) {
      debugPrint(
          'MiniLmSummaryService falling back to local summarizer: $error');
    }

    return _fallbackService.summarizeTranscript(normalizedTranscript);
  }
}

List<String> normalizeKeyPoints(List<String> candidates) {
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

String formatSummaryBullets(List<String> keyPoints) {
  return keyPoints
      .map((point) => '• ${ensureTerminalPunctuation(point)}')
      .join('\n');
}

String ensureTerminalPunctuation(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return trimmed;
  if (RegExp(r'[。．.!?！？…]$').hasMatch(trimmed)) return trimmed;
  return '$trimmed。';
}
