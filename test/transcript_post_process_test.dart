import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_vault/utils/transcript_post_process.dart';

void main() {
  group('TranscriptPostProcess', () {
    test('collapseAbnormalRepeats 壓縮中文長重複', () {
      expect(
        TranscriptPostProcess.collapseAbnormalRepeats('的的的的的'),
        '的',
      );
      expect(TranscriptPostProcess.collapseAbnormalRepeats('好好'), '好好');
    });

    test('mergeTrailingOverlap 合併句尾重疊', () {
      expect(
        TranscriptPostProcess.mergeTrailingOverlap('你好今天', '今天天氣'),
        '你好今天 天氣',
      );
      expect(
        TranscriptPostProcess.mergeTrailingOverlap('你好今天', '你好今天'),
        isNull,
      );
    });

    test('composePartial 組合已提交與進行中', () {
      expect(
        TranscriptPostProcess.composePartial('第一章', '章節重點'),
        '第一章 節重點',
      );
    });

    test('mergeTrailingOverlap 英文以單字邊界合併', () {
      expect(
        TranscriptPostProcess.mergeTrailingOverlap(
          'today is monday',
          'monday tomorrow is tuesday',
        ),
        'today is monday tomorrow is tuesday',
      );
    });

    test('composePartial 英文不做字元級切字合併', () {
      expect(
        TranscriptPostProcess.composePartial(
          'today is monday',
          'day tomorrow is tuesday',
        ),
        'today is monday day tomorrow is tuesday',
      );
    });
  });
}
