import 'package:flutter/foundation.dart';

import 'text_rank.dart';

abstract final class ParagraphSummary {
  static const int _maxChars = 480;

  /// 由課程轉錄產生單一段落文字。
  static Future<String> fromTranscript(String raw) async {
    final t = raw.trim();
    if (t.isEmpty) {
      return '本次錄音未取得可辨識文字，無法產生摘要。';
    }
    if (t.length <= 100) {
      return _ensureClosingPeriod(t);
    }

    var sents = TextRank.splitSentences(t);
    if (sents.isEmpty) {
      sents = t
          .split(RegExp(r'[，,、；;]+'))
          .map((s) => s.trim())
          .where((s) => s.length > 4)
          .toList();
    }
    if (sents.isEmpty) {
      return t.length > _maxChars ? '${t.substring(0, _maxChars).trim()}…' : t;
    }

    if (sents.length <= 3) {
      return _cap(_joinAsParagraph(sents));
    }

    try {
      final chosen =
          await TextRank.extractKeyPoints(sents, topN: 4, windowSize: 24);
      if (chosen.isNotEmpty) {
        return _cap(_joinAsParagraph(chosen));
      }
    } catch (error) {
      debugPrint('ParagraphSummary fallback to heuristic scoring: $error');
    }

    final scored = <MapEntry<int, double>>[];
    for (var i = 0; i < sents.length; i++) {
      var score = sents[i].length * 0.12;
      if (i == 0) score += 28;
      if (i == sents.length - 1) score += 14;
      if (sents[i].length > 36) score += 10;
      scored.add(MapEntry(i, score));
    }
    scored.sort((a, b) => b.value.compareTo(a.value));
    final pick = scored.take(4).map((e) => e.key).toList()..sort();
    final chosen = pick.map((i) => sents[i]).toList();
    return _cap(_joinAsParagraph(chosen));
  }

  static String _joinAsParagraph(List<String> parts) {
    final out = StringBuffer();
    for (final p0 in parts) {
      var p = p0.trim();
      if (p.isEmpty) continue;
      p = p.replaceAll(RegExp(r'[。．.!?！？…]+\s*$'), '');
      if (p.isEmpty) continue;
      out.write(p);
      out.write('。');
    }
    var s = out.toString().trim();
    s = s.replaceAll(RegExp(r'。{2,}'), '。');
    return s;
  }

  static String _ensureClosingPeriod(String s) {
    final t = s.trim();
    if (t.isEmpty) return t;
    if (RegExp(r'[。．.!?！？…]$').hasMatch(t)) return t;
    return '$t。';
  }

  static String _cap(String s) {
    if (s.length <= _maxChars) return s;
    return '${s.substring(0, _maxChars).trimRight()}…';
  }
}
