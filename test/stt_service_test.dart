import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_vault/services/stt_service.dart';

void main() {
  group('SttService 初始狀態', () {
    final stt = SttService();

    test('初始時 isInitialized 為 false', () {
      expect(stt.isInitialized, isFalse);
    });

    test('初始時 fullTranscript 為空字串', () {
      expect(stt.fullTranscript, equals(''));
    });

    test('transcriptStream 是 broadcast stream', () {
      expect(stt.transcriptStream.isBroadcast, isTrue);
    });

    test('summaryStream 是 broadcast stream', () {
      expect(stt.summaryStream.isBroadcast, isTrue);
    });

    test('可以多次 listen transcriptStream', () {
      final sub1 = stt.transcriptStream.listen((_) {});
      final sub2 = stt.transcriptStream.listen((_) {});
      expect(sub1, isNotNull);
      expect(sub2, isNotNull);
      sub1.cancel();
      sub2.cancel();
    });

    test('初始化前呼叫 recognizeSegment 不會 crash', () async {
      await expectLater(
        () => stt.recognizeSegment([0.0, 0.1, 0.2], 16000),
        returnsNormally,
      );
    });
  });

  group('SttService resetStream', () {
    test('resetStream 後 fullTranscript 清空', () {
      final stt = SttService();
      stt.resetStream();
      expect(stt.fullTranscript, equals(''));
    });
  });
}