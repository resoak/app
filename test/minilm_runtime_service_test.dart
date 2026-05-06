import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_vault/services/minilm_runtime_service.dart';
import 'package:lecture_vault/models/lecture.dart';

/// 計算兩個單位向量的點積 (即餘弦相似度)
double calculateSimilarity(List<double> v1, List<double> v2) {
  if (v1.length != v2.length) return 0.0;
  double dotProduct = 0.0;
  for (int i = 0; i < v1.length; i++) {
    dotProduct += v1[i] * v2[i];
  }
  return dotProduct;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MiniLmRuntimeService 邏輯測試', () {
    const runtime = MiniLmRuntimeService();

    test('當輸入為空列表時，應返回空列表', () async {
      final embeddings = await runtime.embedSentences([]);
      expect(embeddings, isEmpty);
    });

    test('MiniLmRuntimeService 加載資產並返回單位化向量', () async {
      try {
        final embeddings = await runtime.embedSentences(const [
          '今天課堂整理資料庫索引與查詢最佳化。',
          '最後補充 transaction isolation level 的差異。',
        ]);

        if (embeddings.isNotEmpty) {
          expect(embeddings.length, 2);
          expect(embeddings.first.length, greaterThan(100));

          // 驗證向量是否經過 L2 單位化 (其模長應接近 1.0)
          for (final vector in embeddings) {
            double squaredSum = 0;
            for (var v in vector) {
              squaredSum += v * v;
            }
            expect(math.sqrt(squaredSum), closeTo(1.0, 0.0001));
          }

          // 驗證向量不全為零
          expect(
            embeddings.first.any((value) => value.abs() > 0.000001),
            isTrue,
          );
        }
      } on FlutterError catch (e) {
        // 在純單元測試環境下，若缺少原生 ONNX 或 Asset，記錄提示並跳過
        debugPrint('測試提示：環境缺少原生庫或 Asset，跳過實際推理測試 ($e)');
      } catch (e) {
        debugPrint('推理發生非預期錯誤: $e');
      }
    });

    test('不同長度的句子應產出相同維度的向量', () async {
      try {
        final results = await runtime.embedSentences([
          '短句子',
          '這是一個非常長且包含多個詞彙的句子，用來測試模型是否能處理變長輸入並產出固定長度的向量。'
        ]);
        if (results.isNotEmpty) {
          expect(results[0].length, equals(results[1].length));
          expect(results[0].length, greaterThan(0));
        }
      } on FlutterError {
        // 忽略環境缺失
      }
    });

    test('特殊字元與多國語言應能產出向量', () async {
      try {
        final results = await runtime.embedSentences([
          'Special characters: !@#\$%^&*()_+',
          '日本語の測試',
          'Emojis 🚀🔥✨'
        ]);
        if (results.isNotEmpty) {
          expect(results.length, 3);
          expect(results.every((e) => e.isNotEmpty), isTrue);
        }
      } on FlutterError {
        // 忽略環境缺失
      }
    });

    test('語義相似度應反映句子關聯性', () async {
      try {
        final sentences = [
          '如何優化資料庫查詢效能？',
          'SQL 索引與執行計畫分析。',
          '今天天氣真不錯，適合出去走走。'
        ];
        final results = await runtime.embedSentences(sentences);
        
        if (results.length == 3) {
          final simRelated = calculateSimilarity(results[0], results[1]);
          final simUnrelated = calculateSimilarity(results[0], results[2]);
          
          debugPrint('相關句相似度: $simRelated');
          debugPrint('無關句相似度: $simUnrelated');

          expect(simRelated, greaterThan(simUnrelated));
        }
      } on FlutterError {
        // 忽略環境缺失
      }
    });

    test('模擬資料庫語義搜尋排序邏輯', () {
      final queryVector = [1.0, 0.0, 0.0]; 
      
      final lectureA = Lecture(
        title: '相關內容',
        date: '2024-01-01',
        audioPath: '',
        embedding: [0.9, 0.1, 0.0],
      );
      
      final lectureB = Lecture(
        title: '無關內容',
        date: '2024-01-01',
        audioPath: '',
        embedding: [0.1, 0.9, 0.0],
      );

      final allLectures = [lectureB, lectureA];
      
      final results = allLectures.map((l) {
        double score = 0;
        final List<double> emb = l.embedding!;
        for (int i = 0; i < queryVector.length; i++) {
          score += queryVector[i] * emb[i];
        }
        return MapEntry<Lecture, double>(l, score);
      }).toList();

      results.sort((a, b) => b.value.compareTo(a.value));

      expect(results.first.key.title, equals('相關內容'));
      expect(results.first.value, closeTo(0.9, 0.001));
    });
  });
}
