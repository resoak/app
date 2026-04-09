import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_vault/utils/paragraph_summary.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ParagraphSummary.fromTranscript', () {
    test('空轉錄', () async {
      expect(
        await ParagraphSummary.fromTranscript(''),
        contains('無法產生摘要'),
      );
    });

    test('短文直接當摘要並補句號', () async {
      expect(await ParagraphSummary.fromTranscript('今天講述分頁機制'), endsWith('。'));
    });

    test('多句選句合併為一段', () async {
      final t = List.generate(
        8,
        (i) => '這是第${i + 1}句關於作業系統與記憶體管理的重要說明內容。',
      ).join('');
      final out = await ParagraphSummary.fromTranscript(t);
      expect(out, contains('。'));
      expect(out.length, lessThanOrEqualTo(500));
    });
  });
}
