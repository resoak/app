import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';

import '../models/lecture.dart';
import '../utils/transcript_post_process.dart';

class SttService {
  SttService();

  final WhisperController _whisperController = WhisperController();
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  WhisperModel _activeWhisperModel = WhisperModel.base;

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

  static String _bundledAssetForModel(WhisperModel model) {
    switch (model) {
      case WhisperModel.medium:
        return 'assets/models/whisper/ggml-medium.bin';
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
    if (file.existsSync()) return;

    final data = await rootBundle.load(_bundledAssetForModel(model));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
  }

  Future<void> _ensureModelReady() async {
    await _ensureBundledModelPresent(_activeWhisperModel);
    await _whisperController.initModel(_activeWhisperModel);
  }

  Future<void> initialize() async {
    if (_isInitialized) return;
    _activeWhisperModel = selectWhisperModelForLanguage(
        ui.PlatformDispatcher.instance.locale.languageCode);
    await _ensureModelReady();
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
    await initialize();
    _emitIfChanged('Transcribing...');

    final result = await _whisperController.transcribe(
      model: _activeWhisperModel,
      audioPath: audioPath,
      lang: _activeWhisperModel.name.endsWith('En') ? 'en' : 'zh',
      withTimestamps: true,
      splitOnWord: false,
      threads: 6,
      vadMode: WhisperVadMode.auto,
    );

    final response = result?.transcription;
    final text = TranscriptPostProcess.normalize(response?.text ?? '');
    final segments = response?.segments ?? const <WhisperTranscribeSegment>[];

    _committedText = text;
    _timeline
      ..clear()
      ..addAll(_mapWhisperTimeline(segments));
    _emitIfChanged(text);
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
