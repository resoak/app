// test/stt_service_test.dart
//
// 測試範圍：不需要模型/音訊硬體的純邏輯部分
//   - fullTranscript 累積行為
//   - 初始化前呼叫 acceptWaveform 不 crash
//   - transcript stream 廣播行為
//
// 執行：flutter test test/stt_service_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_vault/services/stt_service.dart';

void main() {
  group('SttService 初始狀態', () {
    late SttService stt;

    setUp(() {
      stt = SttService();
    });

    tearDown(() {
      stt.dispose();
    });

    test('初始時 isInitialized 為 false', () {
      expect(stt.isInitialized, isFalse);
    });

    test('初始時 fullTranscript 為空字串', () {
      expect(stt.fullTranscript, equals(''));
    });

    test('初始化前呼叫 acceptWaveform 不會 crash', () {
      expect(
        () => stt.acceptWaveform([0.0, 0.1, 0.2], 16000),
        returnsNormally,
      );
    });

    test('transcriptStream 是 broadcast stream', () {
      expect(stt.transcriptStream.isBroadcast, isTrue);
    });

    test('可以多次 listen transcriptStream', () {
      // broadcast stream 允許多個 listener
      final sub1 = stt.transcriptStream.listen((_) {});
      final sub2 = stt.transcriptStream.listen((_) {});
      expect(sub1, isNotNull);
      expect(sub2, isNotNull);
      sub1.cancel();
      sub2.cancel();
    });
  });

  group('SttService dispose', () {
    test('dispose 後不 crash', () {
      final stt = SttService();
      expect(() => stt.dispose(), returnsNormally);
    });

    test('重複 dispose 不 crash', () {
      final stt = SttService();
      stt.dispose();
      expect(() => stt.dispose(), returnsNormally);
    });
  });
}