import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import 'package:path/path.dart' as p;
import 'package:flutter_open_chinese_convert/flutter_open_chinese_convert.dart';
import '../utils/text_rank.dart';

class SttService {
  static final SttService _instance = SttService._internal();
  factory SttService() => _instance;
  SttService._internal();

  sherpa.OfflineRecognizer? _recognizer;
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  String _fullTranscript = "";
  String get fullTranscript => _fullTranscript;

  final _transcriptController = StreamController<String>.broadcast();
  final _summaryController = StreamController<String>.broadcast();
  Stream<String> get transcriptStream => _transcriptController.stream;
  Stream<String> get summaryStream => _summaryController.stream;

  final List<String> _sentences = [];

  Future<void> initialize() async {
    if (_isInitialized) return;
    sherpa.initBindings();

    final dir = await getApplicationDocumentsDirectory();
    final modelDirPath = p.join(dir.path, 'stt_model');
    final modelDir = Directory(modelDirPath);
    if (!modelDir.existsSync()) modelDir.createSync(recursive: true);

    final files = ['model.int8.onnx', 'tokens.txt'];
    for (var f in files) {
      final file = File(p.join(modelDirPath, f));
      if (!file.existsSync()) {
        debugPrint('Copying $f from assets...');
        final data = await rootBundle.load('assets/models/stt/$f');
        await file.writeAsBytes(data.buffer.asUint8List());
        debugPrint('Copied $f');
      }
    }

    final config = sherpa.OfflineRecognizerConfig(
      model: sherpa.OfflineModelConfig(
        senseVoice: sherpa.OfflineSenseVoiceModelConfig(
          model: p.join(modelDirPath, 'model.int8.onnx'),
          language: 'auto',
          useInverseTextNormalization: true,
        ),
        tokens: p.join(modelDirPath, 'tokens.txt'),
        numThreads: 4,
        modelType: 'sense_voice',
      ),
    );

    _recognizer = sherpa.OfflineRecognizer(config);
    _isInitialized = true;
    debugPrint('SenseVoice initialized');
  }

  void resetStream() {
    _fullTranscript = "";
    _sentences.clear();
  }

  Future<void> recognizeSegment(List<double> samples, int sampleRate) async {
    if (_recognizer == null || samples.isEmpty) return;

    try {
      final stream = _recognizer!.createStream();
      stream.acceptWaveform(
        samples: Float32List.fromList(samples),
        sampleRate: sampleRate,
      );
      _recognizer!.decode(stream);
      final result = _recognizer!.getResult(stream);
      stream.free();

      final rawText = result.text.trim();
      debugPrint('SenseVoice raw: $rawText');

      // 簡體轉繁體（台灣標準）
      final text = await ChineseConverter.convert(rawText, S2TWp());
      debugPrint('SenseVoice traditional: $text');

      // 過濾垃圾結果
      final hasChinese = RegExp(r'[\u4e00-\u9fff]').hasMatch(text);
      final hasEnoughWords = text.split(' ').length >= 3;

      if (text.isNotEmpty && (hasChinese || hasEnoughWords)) {
        _fullTranscript += (_fullTranscript.isEmpty ? '' : ' ') + text;
        _transcriptController.add(_fullTranscript);
        _sentences.add(text);
        _updateSummary();
      } else {
        debugPrint('Filtered out noise: $text');
      }
    } catch (e) {
      debugPrint('SenseVoice error: $e');
    }
  }

  void _updateSummary() {
    final sentences = List<String>.from(_sentences);
    Future(() async {
      try {
        final keyPoints = await TextRank.extractKeyPoints(
          sentences,
          topN: 5,
        );
        if (keyPoints.isNotEmpty) {
          final summary = keyPoints
              .asMap()
              .entries
              .map((e) => '• ${e.value}')
              .join('\n');
          _summaryController.add(summary);
        }
      } catch (e) {
        debugPrint('TextRank error: $e');
      }
    });
  }

  void dispose() {
    _recognizer?.free();
    _isInitialized = false;
  }
}