import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_vault/utils/text_rank.dart';

void main() {
  group('TextRank.splitSentences()', () {
    test('空字串回傳空列表', () {
      final result = TextRank.splitSentences('');
      expect(result, isEmpty);
    });

    test('用句號切割', () {
      final result = TextRank.splitSentences('這是第一句完整的話。這是第二句完整的話。這是第三句完整的話。');
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
      final result =
          TextRank.splitSentences('Flutter is a UI framework. 它可以跨平台開發應用程式。');
      expect(result.length, greaterThan(0));
    });

    test('長篇無標點中文會切成多個摘要候選片段', () {
      const transcript =
          '今天老師先講快取記憶體的設計原理接著分析命中率如何影響整體效能然後比較直接對映與組合對映的取捨最後再說明寫回策略與一致性問題'
          '並且補充實務上如何觀察瓶頸與調整參數讓系統更穩定';

      final result = TextRank.splitSentences(transcript);

      expect(result.length, greaterThanOrEqualTo(2));
      expect(result.every((segment) => segment.length >= 6), isTrue);
    });

    test('長篇無標點英文會依空白切成多個摘要候選片段', () {
      const transcript =
          'today the lecture explains cache memory design principles and then compares mapping strategies for direct mapped cache and set associative cache '
          'while also discussing write back policy cache coherence debugging steps and practical tuning ideas for performance bottlenecks in production systems';

      final result = TextRank.splitSentences(transcript);

      expect(result.length, greaterThanOrEqualTo(2));
      expect(result.join(' '), contains('cache memory design principles'));
    });

    test('短篇無標點內容仍保留單一片段', () {
      final result = TextRank.splitSentences('今天講述分頁機制與快取');

      expect(result, hasLength(1));
      expect(result.single, '今天講述分頁機制與快取');
    });
  });

  group('TextRank.extractKeyPoints()', () {
    test('空列表輸入回傳空列表', () async {
      final result = await TextRank.extractKeyPoints([], topN: 3);
      expect(result, isEmpty);
    });

    test('句子數少於 topN 時全部回傳', () async {
      final sentences = ['第一句話很重要', '第二句話也重要'];
      final result = await TextRank.extractKeyPoints(sentences, topN: 5);
      expect(result, equals(sentences));
    });

    test('會挑出重複主題較明顯的句子', () async {
      final sentences = [
        '今天老師先介紹作業系統的記憶體管理觀念。',
        '接著說明記憶體分頁如何降低外部碎片問題。',
        '下課前再次整理分頁表與記憶體配置的重點。',
        '最後提醒大家下週要交作業。',
      ];

      final result = await TextRank.extractKeyPoints(sentences, topN: 2);

      expect(result, hasLength(2));
      expect(result.join(''), contains('記憶體'));
    });
  });
}
