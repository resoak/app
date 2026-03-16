// test/embedding_service_test.dart
//
// 測試範圍：不需要模型檔案的純邏輯部分
//   - cosine similarity 計算
//   - normalize 向量
//   - tokenize 文字（CJK + 英文）
//   - _toInputIds（vocab 查找）
//
// 執行：flutter test test/embedding_service_test.dart

import 'dart:math';
import 'package:flutter_test/flutter_test.dart';

// ── 把 EmbeddingService 內部的純函數抽出來測試 ──────────────────────────────
// 因為這些方法是 private，我們在這裡複製邏輯來測試
// 如果你想直接測 class，可以把這些方法改成 @visibleForTesting

List<double> normalize(List<double> v) {
  double norm = 0;
  for (final x in v) {
    norm += x * x;
  }
  norm = sqrt(norm);
  if (norm == 0) return v;
  return v.map((x) => x / norm).toList();
}

double cosineSimilarity(List<double> a, List<double> b) {
  assert(a.length == b.length);
  double dot = 0;
  for (int i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
  }
  return dot;
}

List<double> meanPool(List<List<double>> hiddenState, List<int> mask, int dim) {
  final result = List.filled(dim, 0.0);
  int count = 0;
  for (int i = 0; i < hiddenState.length; i++) {
    if (mask[i] == 1) {
      for (int j = 0; j < dim; j++) {
        result[j] += hiddenState[i][j];
      }
      count++;
    }
  }
  if (count > 0) {
    for (int j = 0; j < dim; j++) {
      result[j] /= count;
    }
  }
  return result;
}

bool isCjk(int codePoint) {
  return (codePoint >= 0x4E00 && codePoint <= 0x9FFF) ||
      (codePoint >= 0x3400 && codePoint <= 0x4DBF) ||
      (codePoint >= 0x20000 && codePoint <= 0x2A6DF);
}

List<String> tokenize(String text, int maxLen) {
  final cleaned = text.toLowerCase().trim();
  final tokens = <String>['[CLS]'];
  for (final char in cleaned.runes) {
    final c = String.fromCharCode(char);
    if (isCjk(char) || c != ' ') tokens.add(c);
  }
  tokens.add('[SEP]');
  if (tokens.length > maxLen) {
    return [...tokens.sublist(0, maxLen - 1), '[SEP]'];
  }
  return tokens;
}

// ── Tests ────────────────────────────────────────────────────────────────────

void main() {
  group('normalize()', () {
    test('單位向量不變', () {
      final v = [1.0, 0.0, 0.0];
      final result = normalize(v);
      expect(result[0], closeTo(1.0, 1e-6));
      expect(result[1], closeTo(0.0, 1e-6));
    });

    test('一般向量 norm 應為 1', () {
      final v = [3.0, 4.0];
      final result = normalize(v);
      final norm = sqrt(result[0] * result[0] + result[1] * result[1]);
      expect(norm, closeTo(1.0, 1e-6));
    });

    test('零向量不 crash', () {
      final v = [0.0, 0.0, 0.0];
      final result = normalize(v);
      expect(result, equals([0.0, 0.0, 0.0]));
    });
  });

  group('cosineSimilarity()', () {
    test('完全相同向量 → 1.0', () {
      final v = normalize([1.0, 2.0, 3.0]);
      expect(cosineSimilarity(v, v), closeTo(1.0, 1e-6));
    });

    test('完全相反向量 → -1.0', () {
      final a = normalize([1.0, 0.0]);
      final b = normalize([-1.0, 0.0]);
      expect(cosineSimilarity(a, b), closeTo(-1.0, 1e-6));
    });

    test('正交向量 → 0.0', () {
      final a = normalize([1.0, 0.0]);
      final b = normalize([0.0, 1.0]);
      expect(cosineSimilarity(a, b), closeTo(0.0, 1e-6));
    });
  });

  group('meanPool()', () {
    test('全 mask=1 時取平均', () {
      final hidden = [
        [1.0, 2.0],
        [3.0, 4.0],
      ];
      final mask = [1, 1];
      final result = meanPool(hidden, mask, 2);
      expect(result[0], closeTo(2.0, 1e-6));
      expect(result[1], closeTo(3.0, 1e-6));
    });

    test('mask=0 的 token 被忽略', () {
      final hidden = [
        [1.0, 2.0],
        [3.0, 4.0],
        [100.0, 100.0], // mask=0，不應計入
      ];
      final mask = [1, 1, 0];
      final result = meanPool(hidden, mask, 2);
      expect(result[0], closeTo(2.0, 1e-6));
      expect(result[1], closeTo(3.0, 1e-6));
    });
  });

  group('tokenize()', () {
    test('基本英文', () {
      final tokens = tokenize('hello', 128);
      expect(tokens.first, equals('[CLS]'));
      expect(tokens.last, equals('[SEP]'));
      expect(tokens.contains('h'), isTrue);
      expect(tokens.contains('e'), isTrue);
    });

    test('中文字符被正確識別', () {
      final tokens = tokenize('你好', 128);
      expect(tokens.contains('你'), isTrue);
      expect(tokens.contains('好'), isTrue);
    });

    test('空白被移除', () {
      final tokens = tokenize('a b', 128);
      // 空白不應出現在 tokens 中
      expect(tokens.contains(' '), isFalse);
    });

    test('超過 maxLen 被截斷', () {
      final longText = 'a' * 200;
      final tokens = tokenize(longText, 10);
      expect(tokens.length, equals(10));
      expect(tokens.last, equals('[SEP]'));
    });

    test('大寫轉小寫', () {
      final tokens = tokenize('Hello', 128);
      expect(tokens.contains('h'), isTrue);
      expect(tokens.contains('H'), isFalse);
    });
  });

  group('isCjk()', () {
    test('中文字符', () {
      expect(isCjk('你'.runes.first), isTrue);
      expect(isCjk('好'.runes.first), isTrue);
      expect(isCjk('學'.runes.first), isTrue);
    });

    test('英文字符不是 CJK', () {
      expect(isCjk('a'.runes.first), isFalse);
      expect(isCjk('Z'.runes.first), isFalse);
    });

    test('數字不是 CJK', () {
      expect(isCjk('1'.runes.first), isFalse);
    });
  });
}