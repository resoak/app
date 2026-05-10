import 'package:flutter/foundation.dart';

import 'android_local_llm_runtime_service.dart';
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

class AndroidLocalLlmSummaryService implements SummaryService {
  AndroidLocalLlmSummaryService({
    LocalLlmTranscriptSummaryRuntime? runtime,
    SummaryService? fallbackService,
  })  : _runtime = runtime ?? AndroidLocalLlmRuntimeService(),
        _fallbackService = fallbackService ?? const MiniLmSummaryService();

  final LocalLlmTranscriptSummaryRuntime _runtime;
  final SummaryService _fallbackService;

  /// Known prompt-leakage phrases that small models tend to echo back.
  static final RegExp _promptLeakagePattern = RegExp(
    r'(逐字稿|重點摘要|開頭|原句|以下|請閱讀|請根據|請產出|不要重述|改寫成|'
    r'使用繁體中文|不要加標題|不要加前言|im_start|im_end|'
    r'assistant|system|user|開始摘要|以上是|'
    r'請問|是什麼|做成中文|不能貼近)',
    caseSensitive: false,
  );

  /// Lines ending with a question mark are prompt echoes, not summaries.
  static final RegExp _questionPattern = RegExp(r'[？?]\s*$');

  @override
  Future<String> summarizeTranscript(String transcript) async {
    final normalizedTranscript = transcript.trim();
    if (normalizedTranscript.isEmpty) {
      return '';
    }

    try {
      final attempt = await _runtime.summarizeTranscript(normalizedTranscript);
      if (attempt.hasSummary) {
        final formattedSummary = _formatRuntimeSummary(
          attempt.summary!,
          transcript: normalizedTranscript,
        );
        if (formattedSummary.isNotEmpty) {
          return formattedSummary;
        }
        debugPrint(
          'AndroidLocalLlmSummaryService produced no usable bullet lines, falling back.',
        );
      } else if (attempt.isUnavailable) {
        debugPrint(
          'AndroidLocalLlmSummaryService unavailable: ${attempt.message}',
        );
      }
    } catch (error) {
      debugPrint('AndroidLocalLlmSummaryService fallback: $error');
    }

    final fallbackSummary =
        await _fallbackService.summarizeTranscript(transcript);
    if (fallbackSummary.trim().isNotEmpty) {
      return fallbackSummary;
    }
    return '';
  }

  /// Check if a line is too similar to the original transcript (verbatim copy).
  static bool _isVerbatimCopy(String line, String transcript) {
    if (line.length < 10) return false;
    final normalizedLine = line.replaceAll(RegExp(r'\s+'), '');
    final normalizedTranscript = transcript.replaceAll(RegExp(r'\s+'), '');
    // If the line appears verbatim as a substring of the transcript
    if (normalizedTranscript.contains(normalizedLine)) return true;
    // For longer lines, check character-level overlap with a sliding window
    if (normalizedLine.length > 40) {
      final windowSize = normalizedLine.length;
      final maxStart = normalizedTranscript.length - windowSize;
      for (var i = 0; i <= maxStart; i++) {
        final window = normalizedTranscript.substring(i, i + windowSize);
        var matches = 0;
        for (var j = 0; j < windowSize; j++) {
          if (normalizedLine[j] == window[j]) {
            matches++;
          }
        }
        if (matches / windowSize > 0.8) return true;
      }
    }
    return false;
  }

  /// Returns true if the line should be kept as a valid summary bullet.
  bool _isUsableSummaryLine(String line, String transcript) {
    if (line.isEmpty) return false;
    if (line.startsWith('摘要')) return false;
    if (_promptLeakagePattern.hasMatch(line)) return false;
    if (_questionPattern.hasMatch(line)) return false;
    if (transcript.isNotEmpty && _isVerbatimCopy(line, transcript)) {
      return false;
    }
    return true;
  }

  String _formatRuntimeSummary(String rawSummary, {String transcript = ''}) {
    final cleanedSummary = rawSummary
        .replaceAll('<|eot_id|>', '')
        .replaceAll('<|im_end|>', '')
        .replaceAll('<|im_start|>', '');

    final normalizedLines = cleanedSummary
        .replaceAll('\r\n', '\n')
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .map(
          (line) => line.replaceFirst(
            RegExp(r'^(?:[•*\-]|\d+[.)、])\s*'),
            '',
          ),
        )
        .where((line) => _isUsableSummaryLine(line, transcript))
        .toList(growable: false);

    final bulletLines = normalizeKeyPoints(normalizedLines).take(5).toList();
    if (bulletLines.isNotEmpty) {
      return formatSummaryBullets(bulletLines);
    }

    final sentenceLines =
        normalizeKeyPoints(TextRank.splitSentences(rawSummary))
            .where((line) => _isUsableSummaryLine(line, transcript))
            .take(5)
            .toList(growable: false);
    if (sentenceLines.isNotEmpty) {
      return formatSummaryBullets(sentenceLines);
    }

    return '';
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
