import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';

import '../models/lecture.dart';
import '../utils/transcript_post_process.dart';

class SttService {
  SttService({
    WhisperModel? whisperModel,
    WhisperController? whisperController,
  })  : _whisperController = whisperController ?? WhisperController(),
        _preferredWhisperModel = whisperModel,
        _activeWhisperModel =
            _resolveBundledWhisperModel(whisperModel ?? WhisperModel.base);

  final WhisperController _whisperController;
  final WhisperModel? _preferredWhisperModel;
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  WhisperModel _activeWhisperModel;
  @visibleForTesting
  WhisperModel get activeWhisperModel => _activeWhisperModel;

  String _committedText = '';
  String _lastEmittedText = '';
  String _fullTranscript = '';
  final List<LectureTimelineEntry> _timeline = [];

  String get fullTranscript => _fullTranscript;
  String get committedTranscript =>
      TranscriptPostProcess.normalize(_committedText);
  String get persistedTranscript {
    final committed = committedTranscript;
    final full = TranscriptPostProcess.normalize(_fullTranscript);
    if (full.length > committed.length) return full;
    if (committed.isNotEmpty) return committed;
    return full;
  }

  List<LectureTimelineEntry> get timeline => List.unmodifiable(_timeline);

  final _transcriptController = StreamController<String>.broadcast();
  Stream<String> get transcriptStream => _transcriptController.stream;

  @visibleForTesting
  static WhisperModel selectWhisperModelForLanguage(String languageCode) {
    return WhisperModel.base;
  }

  static const Set<WhisperModel> _bundledWhisperModels = {
    WhisperModel.tiny,
    WhisperModel.tinyEn,
    WhisperModel.base,
    WhisperModel.baseEn,
    WhisperModel.small,
  };

  static WhisperModel _resolveBundledWhisperModel(WhisperModel model) {
    if (_bundledWhisperModels.contains(model)) {
      return model;
    }
    return WhisperModel.base;
  }

  @visibleForTesting
  static WhisperModel resolveWhisperModel({
    WhisperModel? preferredModel,
    String? languageCode,
  }) {
    if (preferredModel != null) {
      return _resolveBundledWhisperModel(preferredModel);
    }
    return _resolveBundledWhisperModel(
      selectWhisperModelForLanguage(languageCode ?? ''),
    );
  }

  static String _bundledAssetForModel(WhisperModel model) {
    switch (model) {
      case WhisperModel.small:
        return 'assets/models/whisper/ggml-small.bin';
      case WhisperModel.base:
        return 'assets/models/whisper/ggml-base.bin';
      case WhisperModel.baseEn:
        return 'assets/models/whisper/ggml-base.en.bin';
      case WhisperModel.tinyEn:
        return 'assets/models/whisper/ggml-tiny.en.bin';
      case WhisperModel.tiny:
        return 'assets/models/whisper/ggml-tiny.bin';
      default:
        throw UnsupportedError(
            'Bundled Whisper model not available: ${model.name}');
    }
  }

  Future<void> _ensureBundledModelPresent(WhisperModel model) async {
    final modelPath = await _whisperController.getPath(model);
    final file = File(modelPath);
    if (await file.exists()) return;

    final data = await rootBundle.load(_bundledAssetForModel(model));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
  }

  Future<void> _ensureModelReady() async {
    debugPrint('STT: Ensuring model present for: $_activeWhisperModel');
    await _ensureBundledModelPresent(_activeWhisperModel);
    debugPrint('STT: Model present, initializing...');
    await _whisperController.initModel(_activeWhisperModel);
    debugPrint('STT: Model initialized successfully');
  }

  Future<void> initialize() async {
    if (_isInitialized) return;
    debugPrint('STT: Initializing with model: $_activeWhisperModel');
    _activeWhisperModel = resolveWhisperModel(
      preferredModel: _preferredWhisperModel,
      languageCode: ui.PlatformDispatcher.instance.locale.languageCode,
    );
    debugPrint('STT: Resolved model: $_activeWhisperModel');
    await _ensureModelReady();
    debugPrint('STT: Model ready, isInitialized: true');
    _isInitialized = true;
  }

  void resetStream() {
    _committedText = '';
    _lastEmittedText = '';
    _fullTranscript = '';
    _timeline.clear();
  }

  void _emitIfChanged(String next) {
    if (next == _lastEmittedText) return;
    _lastEmittedText = next;
    _fullTranscript = next;
    _transcriptController.add(_fullTranscript);
  }

  @visibleForTesting
  void setTranscriptStateForTest({
    String committedText = '',
    String fullTranscript = '',
  }) {
    _committedText = committedText;
    _fullTranscript = fullTranscript;
  }

  Future<void> transcribeFile(String audioPath) async {
    final file = File(audioPath);
    if (!await file.exists()) {
      debugPrint('STT Error: Audio file does not exist at $audioPath');
      return;
    }

    await initialize();
    _emitIfChanged('正在語音轉文字...');

    // 根據模型名稱判定語系，非 En 模型則使用自動偵測或預設 zh
    final isEnglishOnly = _activeWhisperModel.name.contains('En');

    final result = await _whisperController.transcribe(
      model: _activeWhisperModel,
      audioPath: audioPath,
      lang: isEnglishOnly ? 'en' : 'auto',
      withTimestamps: true,
      threads: 6,
      vadMode: WhisperVadMode.disabled,
      // whisper_ggml_plus Android native 端目前無法處理顯式的 JSON null。
      // 關閉 VAD 時傳空字串，避免 vad_model_path=null 觸發 json.type_error.302。
      vadModelPath: '',
    );

    final response = result?.transcription;
    final rawText = response?.text ?? '';
    final text = TranscriptPostProcess.normalize(rawText);
    final segments = response?.segments ?? const <WhisperTranscribeSegment>[];

    if (text.isEmpty && rawText.isNotEmpty) {
      // 如果 normalize 完變空的，保留原始文字防止摘要失敗
      _committedText = rawText;
    } else {
      _committedText = text;
    }

    _timeline
      ..clear()
      ..addAll(_mapWhisperTimeline(segments));
    _emitIfChanged(_committedText);
  }

  List<LectureTimelineEntry> _mapWhisperTimeline(
    List<WhisperTranscribeSegment> segments,
  ) {
    return segments
        .map(
          (segment) => LectureTimelineEntry(
            text: TranscriptPostProcess.normalize(segment.text),
            startMs: segment.fromTs.inMilliseconds,
            endMs: segment.toTs.inMilliseconds <= segment.fromTs.inMilliseconds
                ? segment.fromTs.inMilliseconds + 1
                : segment.toTs.inMilliseconds,
            isEstimated: false,
          ),
        )
        .where((entry) => entry.text.isNotEmpty)
        .toList(growable: false);
  }

  void dispose() {
    _isInitialized = false;
  }
}
