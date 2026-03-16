import '../services/embedding_service.dart';

class TextRank {
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
    final embService = EmbeddingService();
    
    if (!embService.isInitialized) {
      await embService.initialize();
    }

    final embeddings = <List<double>>[];

    for (final s in workSet) {
      final emb = embService.embed(s);
      embeddings.add(emb);
    }

    final matrix = List.generate(n, (i) {
      return List.generate(n, (j) {
        if (i == j) return 0.0;
        final sim = EmbeddingService.cosineSimilarity(embeddings[i], embeddings[j]);
        return sim < 0 ? 0.0 : sim;
      });
    });

    final scores = _pageRank(matrix);

    final indexed = List.generate(n, (i) => MapEntry(i, scores[i]));
    indexed.sort((a, b) => b.value.compareTo(a.value));
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
}