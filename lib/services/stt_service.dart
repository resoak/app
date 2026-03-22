import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import 'package:path/path.dart' as p;

class SttService {
  static final SttService _instance = SttService._internal();
  factory SttService() => _instance;
  SttService._internal();

  sherpa.OnlineRecognizer? _recognizer;
  sherpa.OnlineStream? _stream;
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  String _committedText = "";
  String _lastCommittedSegment = "";
  String _lastEmittedText = "";
  String _fullTranscript = "";
  String get fullTranscript => _fullTranscript;

  final _transcriptController = StreamController<String>.broadcast();
  Stream<String> get transcriptStream => _transcriptController.stream;

  Future<void> initialize() async {
    if (_isInitialized) return;
    sherpa.initBindings();

    final dir = await getApplicationDocumentsDirectory();
    final modelDirPath = p.join(dir.path, 'stt_model');
    final modelDir = Directory(modelDirPath);
    if (!modelDir.existsSync()) modelDir.createSync(recursive: true);

    final files = ['encoder.onnx', 'decoder.onnx', 'joiner.onnx', 'tokens.txt'];
    for (var f in files) {
      final file = File(p.join(modelDirPath, f));
      if (!file.existsSync()) {
        final data = await rootBundle.load('assets/models/stt/$f');
        await file.writeAsBytes(data.buffer.asUint8List());
      }
    }

    final config = sherpa.OnlineRecognizerConfig(
      model: sherpa.OnlineModelConfig(
        transducer: sherpa.OnlineTransducerModelConfig(
          encoder: p.join(modelDirPath, 'encoder.onnx'),
          decoder: p.join(modelDirPath, 'decoder.onnx'),
          joiner: p.join(modelDirPath, 'joiner.onnx'),
        ),
        tokens: p.join(modelDirPath, 'tokens.txt'),
        numThreads: 4,
        modelType: 'zipformer',
      ),
      decodingMethod: 'modified_beam_search',
      maxActivePaths: 4,
      enableEndpoint: true,
      rule1MinTrailingSilence: 3.0,
      rule2MinTrailingSilence: 3.5,
      rule3MinUtteranceLength: 20.0,
    );

    _recognizer = sherpa.OnlineRecognizer(config);
    _stream = _recognizer!.createStream();
    _isInitialized = true;
  }

  void resetStream() {
    _stream?.free();
    _stream = _recognizer?.createStream();
    _committedText = "";
    _lastCommittedSegment = "";
    _lastEmittedText = "";
    _fullTranscript = "";
  }

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
    final currentText = result.text.trim();

    if (_recognizer!.isEndpoint(_stream!)) {
      if (currentText.isNotEmpty &&
          currentText != _lastCommittedSegment) {
        _lastCommittedSegment = currentText;
        _committedText +=
            (_committedText.isEmpty ? '' : ' ') + currentText;
        _fullTranscript = _committedText;
        _lastEmittedText = _fullTranscript;
        _transcriptController.add(_fullTranscript);
      }
      _recognizer!.reset(_stream!);
    } else if (currentText.isNotEmpty) {
      final display = _committedText.isEmpty
          ? currentText
          : '$_committedText $currentText';
      if (display != _lastEmittedText) {
        _lastEmittedText = display;
        _fullTranscript = display;
        _transcriptController.add(_fullTranscript);
      }
    }
  }

  void dispose() {
    _stream?.free();
    _recognizer?.free();
    _isInitialized = false;
  }
}