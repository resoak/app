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
  });

  group('SttService resetStream', () {
    test('resetStream 後 fullTranscript 清空', () {
      final stt = SttService();
      stt.resetStream();
      expect(stt.fullTranscript, equals(''));
    });
  });

  group('SttService whisper model selection', () {
    test('預設選擇 base 模型', () {
      expect(
        SttService.selectWhisperModelForLanguage('en-US'),
        equals(WhisperModel.base),
      );
      expect(
        SttService.selectWhisperModelForLanguage('zh-TW'),
        equals(WhisperModel.base),
      );
    });

    test('未指定模型時維持 base，指定後使用該模型', () {
      expect(
        SttService.resolveWhisperModel(languageCode: 'zh-TW'),
        equals(WhisperModel.base),
      );
      expect(
        SttService.resolveWhisperModel(
          preferredModel: WhisperModel.medium,
          languageCode: 'zh-TW',
        ),
        equals(WhisperModel.medium),
      );
      expect(
        SttService(whisperModel: WhisperModel.small).activeWhisperModel,
        equals(WhisperModel.small),
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
}
