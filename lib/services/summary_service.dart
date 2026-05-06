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
  static const int _verbatimSummaryThreshold = 120;

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
      return ''; // 真的沒文字就回傳空，不要觸發 fallback 的範例文字
    }

    // 針對非常短的文字（例如匯入音檔辨識不佳），至少嘗試提取第一句
    final sentences = TextRank.splitSentences(normalizedTranscript);
    if (sentences.length < 2) {
      if (sentences.isEmpty) {
        return '';
      }
      if (normalizedTranscript.length <= _verbatimSummaryThreshold) {
        return '• ${ensureTerminalPunctuation(sentences.first)}';
      }
      return _fallbackService.summarizeTranscript(transcript);
    }

    final candidates = normalizeKeyPoints(sentences)
        .take(_maxCandidateSentences)
        .toList(growable: false);

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
      debugPrint('MiniLmSummaryService fallback: $error');
    }

    return _fallbackService.summarizeTranscript(transcript);
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
