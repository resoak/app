import 'dart:math' as math;

class EmbeddingExtractiveRanker {
  const EmbeddingExtractiveRanker._();

  static List<String> selectKeyPoints({
    required List<String> sentences,
    required List<List<double>> embeddings,
    int maxKeyPoints = 4,
  }) {
    if (sentences.isEmpty || embeddings.isEmpty) {
      return const [];
    }

    final effectiveLength = math.min(sentences.length, embeddings.length);
    if (effectiveLength == 0) {
      return const [];
    }

    final candidates = List<_SentenceCandidate>.generate(
      effectiveLength,
      (index) => _SentenceCandidate(
        sentence: sentences[index],
        embedding: _normalize(embeddings[index]),
        originalIndex: index,
      ),
      growable: false,
    );

    final centroid =
        _buildCentroid(candidates.map((c) => c.embedding).toList());
    final rankedCandidates = candidates
        .map(
          (candidate) => candidate.copyWith(
            relevanceScore: _baseScore(
              sentence: candidate.sentence,
              embedding: candidate.embedding,
              centroid: centroid,
              originalIndex: candidate.originalIndex,
              totalSentences: candidates.length,
            ),
          ),
        )
        .toList(growable: false)
      ..sort(
          (left, right) => right.relevanceScore.compareTo(left.relevanceScore));

    final selected = <_SentenceCandidate>[];
    final limit = math.min(maxKeyPoints, rankedCandidates.length);
    while (selected.length < limit) {
      _SentenceCandidate? bestCandidate;
      var bestScore = double.negativeInfinity;

      for (final candidate in rankedCandidates) {
        if (selected
            .any((picked) => picked.originalIndex == candidate.originalIndex)) {
          continue;
        }

        final redundancyPenalty = selected.isEmpty
            ? 0.0
            : selected
                .map((picked) =>
                    _cosineSimilarity(candidate.embedding, picked.embedding))
                .reduce(math.max);
        final diversifiedScore =
            candidate.relevanceScore - (redundancyPenalty * 0.5);
        if (diversifiedScore > bestScore) {
          bestScore = diversifiedScore;
          bestCandidate = candidate;
        }
      }

      if (bestCandidate == null) {
        break;
      }

      selected.add(bestCandidate);
    }

    selected.sort(
        (left, right) => left.originalIndex.compareTo(right.originalIndex));
    return selected
        .map((candidate) => candidate.sentence)
        .toList(growable: false);
  }

  static double _baseScore({
    required String sentence,
    required List<double> embedding,
    required List<double> centroid,
    required int originalIndex,
    required int totalSentences,
  }) {
    final semanticScore = _cosineSimilarity(embedding, centroid);
    final positionBias = totalSentences <= 1
        ? 0.0
        : 1.0 - (originalIndex / (totalSentences - 1));
    final lengthBias = math.min(sentence.trim().length / 32.0, 1.0);
    return semanticScore + (positionBias * 0.06) + (lengthBias * 0.02);
  }

  static List<double> _buildCentroid(List<List<double>> embeddings) {
    if (embeddings.isEmpty) {
      return const [];
    }

    final dimensions = embeddings.first.length;
    final centroid = List<double>.filled(dimensions, 0.0);
    for (final embedding in embeddings) {
      final normalized = _normalize(embedding);
      for (var i = 0; i < dimensions; i++) {
        centroid[i] += normalized[i];
      }
    }

    for (var i = 0; i < centroid.length; i++) {
      centroid[i] /= embeddings.length;
    }
    return _normalize(centroid);
  }

  static List<double> _normalize(List<double> vector) {
    if (vector.isEmpty) {
      return const [];
    }

    var magnitude = 0.0;
    for (final value in vector) {
      magnitude += value * value;
    }
    magnitude = math.sqrt(magnitude);
    if (magnitude <= 1e-12) {
      return List<double>.filled(vector.length, 0.0, growable: false);
    }

    return vector.map((value) => value / magnitude).toList(growable: false);
  }

  static double _cosineSimilarity(List<double> left, List<double> right) {
    if (left.isEmpty || right.isEmpty || left.length != right.length) {
      return 0.0;
    }

    var dot = 0.0;
    for (var i = 0; i < left.length; i++) {
      dot += left[i] * right[i];
    }
    return dot;
  }
}

class _SentenceCandidate {
  const _SentenceCandidate({
    required this.sentence,
    required this.embedding,
    required this.originalIndex,
    this.relevanceScore = 0.0,
  });

  final String sentence;
  final List<double> embedding;
  final int originalIndex;
  final double relevanceScore;

  _SentenceCandidate copyWith({double? relevanceScore}) {
    return _SentenceCandidate(
      sentence: sentence,
      embedding: embedding,
      originalIndex: originalIndex,
      relevanceScore: relevanceScore ?? this.relevanceScore,
    );
  }
}
