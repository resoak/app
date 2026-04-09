import 'dart:math' as math;

class TextRank {
  static final RegExp _latinWordPattern = RegExp(r'[A-Za-z0-9]+');
  static final RegExp _cjkCharPattern = RegExp(r'[\u3400-\u4DBF\u4E00-\u9FFF]');
  static const Set<String> _englishStopWords = {
    'a',
    'an',
    'and',
    'are',
    'as',
    'at',
    'be',
    'by',
    'for',
    'from',
    'in',
    'into',
    'is',
    'it',
    'of',
    'on',
    'or',
    'that',
    'the',
    'this',
    'to',
    'was',
    'with',
  };

  static Future<List<String>> extractKeyPoints(
    List<String> sentences, {
    int topN = 5,
    int? windowSize,
  }) async {
    if (sentences.isEmpty) return [];

    final workSet = (windowSize != null && sentences.length > windowSize)
        ? sentences.sublist(sentences.length - windowSize)
        : sentences;

    if (workSet.length <= topN) return workSet;

    final n = workSet.length;
    final tokenized = workSet.map(_tokenizeSentence).toList(growable: false);
    final documentFrequency = <String, int>{};

    for (final tokens in tokenized) {
      for (final token in tokens.keys) {
        documentFrequency.update(token, (count) => count + 1,
            ifAbsent: () => 1);
      }
    }

    final inverseDocumentFrequency = <String, double>{
      for (final entry in documentFrequency.entries)
        entry.key: _inverseDocumentFrequency(n, entry.value),
    };

    final weightedLengths = tokenized
        .map((tokens) => _weightedLength(tokens, inverseDocumentFrequency))
        .toList(growable: false);

    if (tokenized.every((tokens) => tokens.isEmpty)) {
      return workSet.take(topN).toList(growable: false);
    }

    final matrix = List.generate(n, (i) {
      return List.generate(n, (j) {
        if (i == j) return 0.0;
        return _sentenceSimilarity(
          tokenized[i],
          tokenized[j],
          inverseDocumentFrequency,
          weightedLengths[i],
          weightedLengths[j],
        );
      });
    });

    final scores = _pageRank(matrix);

    final indexed = List.generate(n, (i) {
      final score = scores[i] + _positionBias(i, n) + _lengthBias(workSet[i]);
      return MapEntry(i, score);
    });
    indexed.sort((a, b) {
      final scoreDiff = b.value.compareTo(a.value);
      if (scoreDiff != 0) return scoreDiff;
      return a.key.compareTo(b.key);
    });
    final topIndices = indexed.take(topN).map((e) => e.key).toList()..sort();

    return topIndices.map((i) => workSet[i]).toList();
  }

  static List<String> splitSentences(String text) {
    return text
        .split(RegExp(r'[。？！\n\.!?]+'))
        .map((s) => s.trim())
        .where((s) => s.length > 5)
        .toList();
  }

  static List<double> _pageRank(
    List<List<double>> matrix, {
    int iterations = 30,
    double dampingFactor = 0.85,
  }) {
    final n = matrix.length;
    var scores = List.filled(n, 1.0 / n);

    final normalized = List.generate(n, (i) {
      final rowSum = matrix[i].fold(0.0, (a, b) => a + b);
      return rowSum == 0
          ? List.filled(n, 0.0)
          : matrix[i].map((v) => v / rowSum).toList();
    });

    for (int iter = 0; iter < iterations; iter++) {
      final newScores = List.filled(n, (1 - dampingFactor) / n);
      for (int i = 0; i < n; i++) {
        for (int j = 0; j < n; j++) {
          newScores[i] += dampingFactor * scores[j] * normalized[j][i];
        }
      }
      scores = newScores;
    }

    return scores;
  }

  static Map<String, int> _tokenizeSentence(String sentence) {
    final tokens = <String, int>{};
    final lowered = sentence.toLowerCase();

    for (final match in _latinWordPattern.allMatches(lowered)) {
      final token = match.group(0)!;
      if (token.length <= 1 || _englishStopWords.contains(token)) continue;
      tokens.update(token, (count) => count + 1, ifAbsent: () => 1);
    }

    for (final match in _cjkCharPattern.allMatches(sentence)) {
      final token = match.group(0)!;
      tokens.update(token, (count) => count + 1, ifAbsent: () => 1);
    }

    return tokens;
  }

  static double _sentenceSimilarity(
    Map<String, int> left,
    Map<String, int> right,
    Map<String, double> inverseDocumentFrequency,
    double leftLength,
    double rightLength,
  ) {
    if (left.isEmpty || right.isEmpty || leftLength == 0 || rightLength == 0) {
      return 0.0;
    }

    final smaller = left.length <= right.length ? left : right;
    final larger = identical(smaller, left) ? right : left;

    double overlap = 0.0;
    for (final entry in smaller.entries) {
      final otherCount = larger[entry.key];
      if (otherCount == null) continue;
      final weight = inverseDocumentFrequency[entry.key] ?? 1.0;
      overlap += (entry.value < otherCount ? entry.value : otherCount) * weight;
    }

    if (overlap == 0.0) return 0.0;
    return overlap / (leftLength * rightLength).sqrt();
  }

  static double _inverseDocumentFrequency(
      int sentenceCount, int documentCount) {
    return 1.0 + (sentenceCount / documentCount).log();
  }

  static double _weightedLength(
    Map<String, int> tokens,
    Map<String, double> inverseDocumentFrequency,
  ) {
    double total = 0.0;
    for (final entry in tokens.entries) {
      final weight = inverseDocumentFrequency[entry.key] ?? 1.0;
      total += entry.value * weight;
    }
    return total;
  }

  static double _positionBias(int index, int total) {
    if (index == 0) return 0.2;
    if (index == total - 1) return 0.08;
    return 0.0;
  }

  static double _lengthBias(String sentence) {
    final normalized = sentence.length / 160;
    if (normalized <= 0) return 0.0;
    return normalized.clamp(0.0, 0.08);
  }
}

extension on num {
  double log() => math.log(toDouble());
  double sqrt() => math.sqrt(toDouble());
}
