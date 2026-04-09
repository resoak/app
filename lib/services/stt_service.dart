import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../utils/transcript_post_process.dart';
import '../models/lecture.dart';

abstract class SttSink {
  void acceptWaveform(List<double> samples, int sampleRate);
  void finalizeStream();
}

class SttService implements SttSink {
  static final SttService _instance = SttService._internal();
  static final RegExp _cjkTokenPattern = RegExp(r'[\u4e00-\u9fff]');
  static final RegExp _latinTokenPattern = RegExp(r'[A-Za-z]');
  static const _modelFiles = [
    'encoder.onnx',
    'decoder.onnx',
    'joiner.onnx',
    'tokens.txt',
  ];
  static const _modelVersionFile = 'model_version.txt';
  factory SttService() => _instance;
  SttService._internal();

  sherpa.OnlineRecognizer? _recognizer;
  sherpa.OnlineStream? _stream;
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;
  bool _supportsCjk = false;
  bool get supportsCjk => _supportsCjk;
  bool _supportsLatin = false;
  bool get supportsLatin => _supportsLatin;

  String _committedText = '';
  String _lastCommittedSegment = '';
  String _lastEmittedText = '';
  String _fullTranscript = '';
  final List<LectureTimelineEntry> _timeline = [];
  final List<String> _committedTimelineTokens = [];
  String get fullTranscript => _fullTranscript;
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
    final normalized = languageCode.toLowerCase();
    if (normalized.startsWith('zh') && !_supportsCjk) {
      return '目前內建語音模型不支援中文，請改用英文或中英雙語 STT 模型。';
    }
    if (normalized.startsWith('en') && !_supportsLatin) {
      return '目前內建語音模型不支援英文，請改用中文或中英雙語 STT 模型。';
    }
    return null;
  }

  Future<void> _syncModelAssets(String modelDirPath) async {
    final bundledVersion =
        (await rootBundle.loadString('assets/models/stt/$_modelVersionFile'))
            .trim();
    final localVersionFile = File(p.join(modelDirPath, _modelVersionFile));
    final localVersion = localVersionFile.existsSync()
        ? localVersionFile.readAsStringSync().trim()
        : '';
    final shouldRefresh = localVersion != bundledVersion ||
        _modelFiles.any((f) => !File(p.join(modelDirPath, f)).existsSync());

    if (!shouldRefresh) return;

    for (final f in _modelFiles) {
      final data = await rootBundle.load('assets/models/stt/$f');
      await File(p.join(modelDirPath, f))
          .writeAsBytes(data.buffer.asUint8List());
    }
    await localVersionFile.writeAsString(bundledVersion);
  }

  Future<void> initialize() async {
    if (_isInitialized) return;
    sherpa.initBindings();

    final dir = await getApplicationDocumentsDirectory();
    final modelDirPath = p.join(dir.path, 'stt_model');
    final modelDir = Directory(modelDirPath);
    if (!modelDir.existsSync()) modelDir.createSync(recursive: true);

    await _syncModelAssets(modelDirPath);

    final tokensContent =
        await File(p.join(modelDirPath, 'tokens.txt')).readAsString();
    _supportsCjk = supportsCjkTokens(tokensContent);
    _supportsLatin = supportsLatinTokens(tokensContent);

    /// 與 [RecordingService] 的 16k PCM 一致。
    /// 目前內建模型是 sherpa-onnx 的中英雙語 streaming zipformer 模型，
    /// 這裡維持較保守的官方相容設定，避免 native 初始化失敗。
    final config = sherpa.OnlineRecognizerConfig(
      feat: const sherpa.FeatureConfig(sampleRate: 16000, featureDim: 80),
      model: sherpa.OnlineModelConfig(
        transducer: sherpa.OnlineTransducerModelConfig(
          encoder: p.join(modelDirPath, 'encoder.onnx'),
          decoder: p.join(modelDirPath, 'decoder.onnx'),
          joiner: p.join(modelDirPath, 'joiner.onnx'),
        ),
        tokens: p.join(modelDirPath, 'tokens.txt'),
        numThreads: 4,
        debug: kDebugMode,
      ),
      decodingMethod: 'greedy_search',
      maxActivePaths: 4,
      blankPenalty: 0,
      enableEndpoint: true,
      rule1MinTrailingSilence: 2.4,
      rule2MinTrailingSilence: 1.2,
      rule3MinUtteranceLength: 20.0,
    );

    _recognizer = sherpa.OnlineRecognizer(config);
    _stream = _recognizer!.createStream();
    _isInitialized = true;
  }

  void resetStream() {
    _stream?.free();
    _stream = _recognizer?.createStream();
    _committedText = '';
    _lastCommittedSegment = '';
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

  @override
  void acceptWaveform(List<double> samples, int sampleRate) {
    if (_stream == null || _recognizer == null) return;

    _stream!.acceptWaveform(
      samples: Float32List.fromList(samples),
      sampleRate: sampleRate,
    );

    while (_recognizer!.isReady(_stream!)) {
      _recognizer!.decode(_stream!);
    }

    final result = _recognizer!.getResult(_stream!);
    final raw = result.text.trim();
    if (raw.isEmpty) return;

    if (_recognizer!.isEndpoint(_stream!)) {
      final t = TranscriptPostProcess.normalize(raw);
      if (t.isNotEmpty && t != _lastCommittedSegment) {
        final previousCommitted = _committedText;
        final merged =
            TranscriptPostProcess.mergeTrailingOverlap(_committedText, t);
        if (merged != null) {
          _lastCommittedSegment = t;
          _committedText = merged;
          _appendTimelineEntry(result, previousCommitted, merged, t);
          _emitIfChanged(TranscriptPostProcess.normalize(_committedText));
        }
      }
      _recognizer!.reset(_stream!);
      return;
    }

    final display = TranscriptPostProcess.composePartial(_committedText, raw);
    _emitIfChanged(display);
  }

  /// 錄音結束時呼叫：告知串流已無更多音訊，把最後一段解碼完並合併進轉錄。
  @override
  void finalizeStream() {
    if (_stream == null || _recognizer == null) return;

    _stream!.inputFinished();
    while (_recognizer!.isReady(_stream!)) {
      _recognizer!.decode(_stream!);
    }

    final result = _recognizer!.getResult(_stream!);
    final t = TranscriptPostProcess.normalize(result.text.trim());
    if (t.isNotEmpty) {
      final previousCommitted = _committedText;
      final merged =
          TranscriptPostProcess.mergeTrailingOverlap(_committedText, t);
      if (merged != null) {
        _committedText = merged;
        _appendTimelineEntry(result, previousCommitted, merged, t);
        _emitIfChanged(TranscriptPostProcess.normalize(_committedText));
      }
    }
  }

  void _appendTimelineEntry(
    sherpa.OnlineRecognizerResult result,
    String previousCommitted,
    String mergedTranscript,
    String normalizedSegment,
  ) {
    final appendedText = _extractAppendedText(
      previousCommitted,
      mergedTranscript,
      normalizedSegment,
    );
    final entry = buildTimelineEntry(
      committedTokens: _committedTimelineTokens,
      incomingTokens: result.tokens,
      timestamps: result.timestamps,
      appendedText: appendedText,
      estimatedStartMs: _timeline.isEmpty ? 0 : _timeline.last.endMs,
      lastEndMs: _timeline.isEmpty ? 0 : _timeline.last.endMs,
    );
    if (entry == null) return;

    _timeline.add(entry.entry);

    if (entry.appendedTokens.isNotEmpty) {
      _committedTimelineTokens.addAll(entry.appendedTokens);
    }
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

  String _extractAppendedText(
    String previousCommitted,
    String mergedTranscript,
    String fallback,
  ) {
    final previous = previousCommitted.trim();
    final merged = mergedTranscript.trim();
    if (previous.isEmpty) return fallback.trim();
    if (merged.startsWith(previous)) {
      final appended = merged.substring(previous.length).trim();
      if (appended.isNotEmpty) return appended;
    }
    return fallback.trim();
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
    _stream?.free();
    _recognizer?.free();
    _stream = null;
    _recognizer = null;
    _isInitialized = false;
    _supportsCjk = false;
    _supportsLatin = false;
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
