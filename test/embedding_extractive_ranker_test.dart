import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_vault/utils/embedding_extractive_ranker.dart';

void main() {
  group('EmbeddingExtractiveRanker', () {
    test('selects centroid-relevant sentences and preserves transcript order',
        () {
      const sentences = [
        '資料庫索引可以提升查詢效率。',
        '如果索引設計不當也會增加寫入成本。',
        '今天最後介紹 B-Tree 的節點分裂流程。',
      ];
      final keyPoints = EmbeddingExtractiveRanker.selectKeyPoints(
        sentences: sentences,
        embeddings: const [
          [1.0, 0.0, 0.0],
          [0.97, 0.03, 0.0],
          [0.0, 0.0, 1.0],
        ],
        maxKeyPoints: 2,
      );

      expect(keyPoints.length, 2);
      expect(keyPoints.first, '資料庫索引可以提升查詢效率。');

      final selectedIndexes = keyPoints
          .map((sentence) => sentences.indexOf(sentence))
          .toList(growable: false);
      final sortedIndexes = selectedIndexes.toList()..sort();
      expect(selectedIndexes, equals(sortedIndexes));
    });

    test('reduces duplicate picks when top embeddings are too similar', () {
      final keyPoints = EmbeddingExtractiveRanker.selectKeyPoints(
        sentences: const [
          '老師先說明快取的命中率。',
          '老師再次重複快取的命中率很重要。',
          '接著轉到 page replacement 的策略。',
        ],
        embeddings: const [
          [1.0, 0.0],
          [0.99, 0.01],
          [0.2, 0.8],
        ],
        maxKeyPoints: 2,
      );

      expect(keyPoints.length, 2);
      expect(keyPoints, contains('老師先說明快取的命中率。'));
      expect(keyPoints, contains('接著轉到 page replacement 的策略。'));
    });
  });
}
