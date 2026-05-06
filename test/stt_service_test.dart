import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_vault/services/stt_service.dart';
import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';
import 'package:whisper_ggml_plus/src/models/whisper_result.dart';

class _FakeWhisperController extends WhisperController {
  _FakeWhisperController({
    required this.modelPath,
    required this.transcribeResult,
  });

  final String modelPath;
  final TranscribeResult? transcribeResult;
  WhisperModel? lastModel;
  String? lastAudioPath;
  String? lastLang;
  bool? lastWithTimestamps;
  int? lastThreads;
  WhisperVadMode? lastVadMode;
  String? lastVadModelPath;
  int initModelCalls = 0;

  @override
  Future<String> getPath(WhisperModel model) async => modelPath;

  @override
  Future<void> initModel(WhisperModel model) async {
    initModelCalls++;
  }

  @override
  Future<TranscribeResult?> transcribe({
    required WhisperModel model,
    required String audioPath,
    String lang = 'en',
    bool diarize = false,
    bool withTimestamps = true,
    bool splitOnWord = false,
    bool convert = true,
    int threads = 6,
    bool isTranslate = false,
    bool speedUp = false,
    WhisperVadMode vadMode = WhisperVadMode.auto,
    String? vadModelPath,
  }) async {
    lastModel = model;
    lastAudioPath = audioPath;
    lastLang = lang;
    lastWithTimestamps = withTimestamps;
    lastThreads = threads;
    lastVadMode = vadMode;
    lastVadModelPath = vadModelPath;
    return transcribeResult;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
          preferredModel: WhisperModel.small,
          languageCode: 'zh-TW',
        ),
        equals(WhisperModel.small),
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

    test('transcribeFile 在 Android workaround 下傳入空的 vadModelPath', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('stt_service_test_');
      final audioFile =
          File('${tempDir.path}${Platform.pathSeparator}audio.wav');
      final modelFile =
          File('${tempDir.path}${Platform.pathSeparator}ggml-base.bin');

      await audioFile.writeAsBytes(const [1, 2, 3, 4]);
      await modelFile.writeAsBytes(const [5, 6, 7, 8]);

      final fakeController = _FakeWhisperController(
        modelPath: modelFile.path,
        transcribeResult: const TranscribeResult(
          time: Duration(milliseconds: 10),
          transcription: WhisperTranscribeResponse(
            type: 'transcribe',
            text: 'hello world',
            segments: null,
          ),
        ),
      );

      final stt = SttService(
        whisperModel: WhisperModel.base,
        whisperController: fakeController,
      );

      await stt.transcribeFile(audioFile.path);

      expect(fakeController.initModelCalls, 1);
      expect(fakeController.lastAudioPath, audioFile.path);
      expect(fakeController.lastLang, 'auto');
      expect(fakeController.lastWithTimestamps, isTrue);
      expect(fakeController.lastThreads, 6);
      expect(fakeController.lastVadMode, WhisperVadMode.disabled);
      expect(fakeController.lastVadModelPath, '');
      expect(stt.persistedTranscript, 'hello world');

      await tempDir.delete(recursive: true);
    });
  });
}
