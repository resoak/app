// test/text_rank_test.dart
//
// 注意：TextRank.extractKeyPoints 需要 EmbeddingService（ONNX model）
// 所以這裡測試不依賴模型的部分：splitSentences 和 _pageRank 邏輯
//
// 執行：flutter test test/text_rank_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_vault/utils/text_rank.dart';

void main() {
  group('TextRank.splitSentences()', () {
    test('空字串回傳空列表', () {
      final result = TextRank.splitSentences('');
      expect(result, isEmpty);
    });

    test('用句號切割', () {
      final result = TextRank.splitSentences(
          '這是第一句完整的話。這是第二句完整的話。這是第三句完整的話。');
      expect(result.length, equals(3));
    });

    test('用問號切割', () {
      final result = TextRank.splitSentences('你今天過得怎麼樣？今天過得很不錯。');
      expect(result.length, equals(2));
    });

    test('用換行切割', () {
      final result = TextRank.splitSentences('這是第一行內容\n這是第二行內容\n這是第三行內容');
      expect(result.length, equals(3));
    });

    test('過短的句子（<=5字）被過濾掉', () {
      final result = TextRank.splitSentences('短句。這是一個比較長的完整句子。');
      expect(result.any((s) => s == '短句'), isFalse);
    });

    test('去除空白', () {
      final result = TextRank.splitSentences('  第一句話。  第二句話。  ');
      for (final s in result) {
        expect(s.trim(), equals(s));
      }
    });

    test('中英混合', () {
      final result = TextRank.splitSentences(
          'Flutter is a UI framework. 它可以跨平台開發應用程式。');
      expect(result.length, greaterThan(0));
    });
  });

  group('TextRank.extractKeyPoints() - 不需要模型的邊界條件', () {
    test('空列表輸入回傳空列表', () async {
      final result = await TextRank.extractKeyPoints([], topN: 3);
      expect(result, isEmpty);
    });

    test('句子數少於 topN 時全部回傳', () async {
      // 不呼叫 embed，因為句子數 <= topN 會直接回傳
      final sentences = ['第一句話很重要', '第二句話也重要'];
      final result = await TextRank.extractKeyPoints(sentences, topN: 5);
      expect(result, equals(sentences));
    });
  });
}