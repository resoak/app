import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';

import '../models/lecture.dart';
import '../utils/transcript_post_process.dart';

abstract class SttSink {
  void acceptWaveform(List<double> samples, int sampleRate);
  void finalizeStream();
}

class SttService implements SttSink {
  static final RegExp _cjkTokenPattern = RegExp(r'[\u4e00-\u9fff]');
  static final RegExp _latinTokenPattern = RegExp(r'[A-Za-z]');
  SttService();

  final WhisperController _whisperController = WhisperController();
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;
  final bool _supportsCjk = true;
  bool get supportsCjk => _supportsCjk;
  final bool _supportsLatin = true;
  bool get supportsLatin => _supportsLatin;
  WhisperModel _activeWhisperModel = WhisperModel.base;

  String _committedText = '';
  String _lastEmittedText = '';
  String _fullTranscript = '';
  final List<LectureTimelineEntry> _timeline = [];
  final List<String> _committedTimelineTokens = [];
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

  static bool supportsCjkTokens(String tokensContent) {
    return _cjkTokenPattern.hasMatch(tokensContent);
  }

  static bool supportsLatinTokens(String tokensContent) {
    return _latinTokenPattern.hasMatch(tokensContent);
  }

  String? unsupportedReasonForLanguage(String languageCode) {
    return null;
  }

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
    _committedTimelineTokens.clear();
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

  @override
  void acceptWaveform(List<double> samples, int sampleRate) {
    // Batch Whisper backend: live PCM chunks are intentionally ignored.
  }

  @override
  void finalizeStream() {}

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

  @visibleForTesting
  static TimelineEntryComputation? buildTimelineEntry({
    required List<String> committedTokens,
    required List<String> incomingTokens,
    required List<double> timestamps,
    required String appendedText,
    required int estimatedStartMs,
    required int lastEndMs,
  }) {
    final currentTokens = normalizeTimelineTokens(incomingTokens);
    final overlapCount = countTrailingTokenOverlap(
      committedTokens,
      currentTokens,
    );
    final appendedTokens =
        currentTokens.skip(overlapCount).toList(growable: false);

    final timelineText = appendedText.isNotEmpty
        ? appendedText
        : renderTimelineText(appendedTokens);
    if (timelineText.isEmpty) return null;

    final startIndex = overlapCount;
    final startMs = timestamps.isEmpty || startIndex >= timestamps.length
        ? estimatedStartMs
        : (timestamps[startIndex] * 1000).round();
    final rawEndMs =
        timestamps.isEmpty ? startMs : (timestamps.last * 1000).round();
    final safeStartMs = startMs < lastEndMs ? lastEndMs : startMs;
    final safeEndMs = rawEndMs <= safeStartMs ? safeStartMs + 1 : rawEndMs;

    return TimelineEntryComputation(
      entry: LectureTimelineEntry(
        text: timelineText,
        startMs: safeStartMs,
        endMs: safeEndMs,
        isEstimated: timestamps.isEmpty,
      ),
      appendedTokens: appendedTokens,
    );
  }

  @visibleForTesting
  static List<String> normalizeTimelineTokens(List<String> tokens) {
    return tokens
        .map((token) => token.trim())
        .where((token) => token.isNotEmpty)
        .toList(growable: false);
  }

  @visibleForTesting
  static int countTrailingTokenOverlap(
    List<String> committed,
    List<String> incoming,
  ) {
    if (committed.isEmpty || incoming.isEmpty) return 0;

    final maxOverlap =
        committed.length < incoming.length ? committed.length : incoming.length;
    for (int k = maxOverlap; k > 0; k--) {
      var matches = true;
      for (int i = 0; i < k; i++) {
        if (committed[committed.length - k + i] != incoming[i]) {
          matches = false;
          break;
        }
      }
      if (matches) return k;
    }
    return 0;
  }

  @visibleForTesting
  static String renderTimelineText(List<String> tokens) {
    if (tokens.isEmpty) return '';
    final out = StringBuffer();
    var needsSpace = false;
    for (final rawToken in tokens) {
      final token = rawToken.trim();
      if (token.isEmpty) continue;

      if (token.startsWith('▁')) {
        final word = token.substring(1);
        if (word.isEmpty) continue;
        if (out.isNotEmpty) out.write(' ');
        out.write(word);
        needsSpace = false;
        continue;
      }

      final isAsciiWord = RegExp(r'^[A-Za-z0-9]+$').hasMatch(token);
      if (out.isNotEmpty && needsSpace && isAsciiWord) {
        out.write(' ');
      }
      out.write(token);
      needsSpace = isAsciiWord;
    }
    return out.toString().trim();
  }

  void dispose() {
    _isInitialized = false;
    _committedTimelineTokens.clear();
  }
}

class TimelineEntryComputation {
  const TimelineEntryComputation({
    required this.entry,
    required this.appendedTokens,
  });

  final LectureTimelineEntry entry;
  final List<String> appendedTokens;
}
