/// 轉錄後處理：減輕串流 ASR 常見的「字元打結」、句尾重疊重複送出等問題。
abstract final class TranscriptPostProcess {
  /// 正規化空白並套用重複字元壓縮。
  static String normalize(String raw) {
    var s = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    s = collapseAbnormalRepeats(s);
    return s.trim();
  }

  /// 過長的「同一字元」連續出現（模型打結）壓到較短長度。
  /// - CJK：連續 4 個以上相同字 → 保留 1 個（「好好」等 2～3 個不動）
  /// - 其他字元：連續 5 個以上 → 保留 1 個
  static String collapseAbnormalRepeats(String input) {
    if (input.isEmpty) return input;
    var s = input.replaceAllMapped(
      RegExp(r'([\u4e00-\u9fff])\1{3,}'),
      (m) => m[1]!,
    );
    s = s.replaceAllMapped(
      RegExp(r'(.)\1{4,}'),
      (m) => m[1]!,
    );
    return s;
  }

  /// 將新片段接在已提交文字後，若邊界有前後綴重疊（串流分段造成）則合併。
  /// 若新內容已完全被既有結尾涵蓋則回傳 null（無需更新）。
  static String? mergeTrailingOverlap(String committed, String segment) {
    final c = committed.trim();
    final s = segment.trim();
    if (s.isEmpty) return null;
    if (c.isEmpty) return s;
    if (c.endsWith(s)) return null;

    final maxK = s.length < c.length ? s.length : c.length;
    for (var k = maxK; k > 0; k--) {
      if (k > c.length) continue;
      if (c.substring(c.length - k) == s.substring(0, k)) {
        final tail = s.substring(k).trim();
        if (tail.isEmpty) return null;
        return '$c $tail';
      }
    }
    return '$c $s';
  }

  /// 即時顯示用：committed + 進行中片段，並對整段做輕量正規化。
  static String composePartial(String committed, String inProgress) {
    final a = committed.trim();
    final b = inProgress.trim();
    if (b.isEmpty) return normalize(a);
    if (a.isEmpty) return normalize(b);
    final merged = mergeTrailingOverlap(a, b);
    return normalize(merged ?? '$a $b');
  }
}
