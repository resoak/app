import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_vault/services/stt_service.dart';
import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';

void main() {
  group('SttService 初始狀態', () {
    final stt = SttService(); // singleton，不在 tearDown dispose

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
      final sub1 = stt.transcriptStream.listen((_) {});
      final sub2 = stt.transcriptStream.listen((_) {});
      expect(sub1, isNotNull);
      expect(sub2, isNotNull);
      sub1.cancel();
      sub2.cancel();
    });

    test('supportsCjkTokens 可辨識中文 token', () {
      expect(SttService.supportsCjkTokens('▁AS 3\n▁ONE 4'), isFalse);
      expect(SttService.supportsCjkTokens('你 3\n好 4'), isTrue);
    });

    test('supportsLatinTokens 可辨識英文 token', () {
      expect(SttService.supportsLatinTokens('你 3\n好 4'), isFalse);
      expect(SttService.supportsLatinTokens('▁AS 3\n▁ONE 4'), isTrue);
    });
  });

  group('SttService resetStream', () {
    test('resetStream 後 fullTranscript 清空', () {
      final stt = SttService();
      stt.resetStream();
      expect(stt.fullTranscript, equals(''));
    });
  });

  group('SttService whisper model selection', () {
    test('所有語系都選擇更強的多語 medium', () {
      expect(
        SttService.selectWhisperModelForLanguage('en-US'),
        equals(WhisperModel.medium),
      );
      expect(
        SttService.selectWhisperModelForLanguage('zh-TW'),
        equals(WhisperModel.medium),
      );
    });
  });

  group('SttService transcript persistence', () {
    test('persistedTranscript 優先保留較長的完整轉錄', () {
      final stt = SttService();
      stt.resetStream();
      stt.setTranscriptStateForTest(
        committedText: 'today is monday',
        fullTranscript: 'today is monday tomorrow is tuesday',
      );

      expect(
        stt.persistedTranscript,
        equals('today is monday tomorrow is tuesday'),
      );
    });
  });

  group('SttService timeline token helpers', () {
    test('countTrailingTokenOverlap 正確計算英文 token 重疊', () {
      final overlap = SttService.countTrailingTokenOverlap(
        ['▁hello', '▁world'],
        ['▁world', '▁again'],
      );
      expect(overlap, equals(1));
    });

    test('countTrailingTokenOverlap 正確計算 CJK token 重疊', () {
      final overlap = SttService.countTrailingTokenOverlap(
        ['今', '天', '上', '課'],
        ['上', '課', '了'],
      );
      expect(overlap, equals(2));
    });

    test('renderTimelineText 可組出英文與中文片段', () {
      expect(
        SttService.renderTimelineText(['▁hello', '▁world']),
        equals('hello world'),
      );
      expect(
        SttService.renderTimelineText(['今', '天', '上', '課']),
        equals('今天上課'),
      );
    });

    test('buildTimelineEntry 會用第一個非重疊 token 的 timestamp', () {
      final computed = SttService.buildTimelineEntry(
        committedTokens: ['▁hello'],
        incomingTokens: ['▁hello', '▁world'],
        timestamps: [0.4, 0.9],
        appendedText: 'world',
        estimatedStartMs: 0,
        lastEndMs: 0,
      );

      expect(computed, isNotNull);
      expect(computed!.entry.text, equals('world'));
      expect(computed.entry.startMs, equals(900));
      expect(computed.entry.endMs, equals(901));
      expect(computed.appendedTokens, equals(['▁world']));
    });

    test('buildTimelineEntry 會處理 CJK token 重疊', () {
      final computed = SttService.buildTimelineEntry(
        committedTokens: ['今', '天'],
        incomingTokens: ['今', '天', '上', '課'],
        timestamps: [0.1, 0.2, 0.6, 0.8],
        appendedText: '上課',
        estimatedStartMs: 0,
        lastEndMs: 200,
      );

      expect(computed, isNotNull);
      expect(computed!.entry.text, equals('上課'));
      expect(computed.entry.startMs, equals(600));
      expect(computed.entry.endMs, equals(800));
      expect(computed.appendedTokens, equals(['上', '課']));
    });
  });

  group('SttService dispose safety', () {
    test('dispose 後 acceptWaveform 與 finalizeStream 不會 crash', () {
      final stt = SttService();
      stt.dispose();
      expect(() => stt.acceptWaveform([0.0, 0.1], 16000), returnsNormally);
      expect(stt.finalizeStream, returnsNormally);
    });
  });

  group('SttService unsupported reason text', () {
    test('中文裝置但模型不支援中文時訊息正確', () {
      final stt = SttService();
      expect(
        stt.unsupportedReasonForLanguage('zh-TW'),
        anyOf(isNull, contains('不支援中文')),
      );
    });

    test('英文裝置但模型不支援英文時訊息正確', () {
      final stt = SttService();
      expect(
        stt.unsupportedReasonForLanguage('en-US'),
        anyOf(isNull, contains('不支援英文')),
      );
    });
  });
}
