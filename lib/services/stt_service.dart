// lib/services/stt_service.dart

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

class SttService {
  sherpa.OnlineRecognizer? _recognizer;
  sherpa.OnlineStream? _stream;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  final _transcriptController = StreamController<String>.broadcast();
  Stream<String> get transcriptStream => _transcriptController.stream;

  String _fullTranscript = '';
  String get fullTranscript => _fullTranscript;

  Future<void> initialize() async {
    if (_isInitialized) return;

    sherpa.initBindings();

    final dir = await getApplicationDocumentsDirectory();
    final modelDir = '${dir.path}/sherpa_model';
    await Directory(modelDir).create(recursive: true);

    await _copyAsset('assets/models/stt/encoder.onnx', '$modelDir/encoder.onnx');
    await _copyAsset('assets/models/stt/decoder.onnx', '$modelDir/decoder.onnx');
    await _copyAsset('assets/models/stt/joiner.onnx', '$modelDir/joiner.onnx');
    await _copyAsset('assets/models/stt/tokens.txt', '$modelDir/tokens.txt');

    final transducer = sherpa.OnlineTransducerModelConfig(
      encoder: '$modelDir/encoder.onnx',
      decoder: '$modelDir/decoder.onnx',
      joiner: '$modelDir/joiner.onnx',
    );

    final modelConfig = sherpa.OnlineModelConfig(
      transducer: transducer,
      tokens: '$modelDir/tokens.txt',
      numThreads: 2,
      debug: false,
    );

    final config = sherpa.OnlineRecognizerConfig(
      model: modelConfig,
      enableEndpoint: true,
      rule1MinTrailingSilence: 2.4,
      rule2MinTrailingSilence: 0.8,
      rule3MinUtteranceLength: 20.0,
    );

    _recognizer = sherpa.OnlineRecognizer(config);
    _stream = _recognizer!.createStream();
    _isInitialized = true;
  }

  void acceptWaveform(List<double> samples, int sampleRate) {
    if (!_isInitialized || _stream == null || _recognizer == null) return;

    _stream!.acceptWaveform(
      samples: Float32List.fromList(samples),
      sampleRate: sampleRate,
    );
    _decode();
  }

  void _decode() {
    while (_recognizer!.isReady(_stream!)) {
      _recognizer!.decode(_stream!);
    }

    final result = _recognizer!.getResult(_stream!);
    final text = result.text.trim();

    if (text.isNotEmpty) {
      _transcriptController.add(text);
    }

    if (_recognizer!.isEndpoint(_stream!)) {
      if (text.isNotEmpty) {
        _fullTranscript += '$text。\n';
      }
      _recognizer!.reset(_stream!);
    }
  }

  Future<void> _copyAsset(String assetPath, String targetPath) async {
    final file = File(targetPath);
    if (await file.exists()) return;
    final data = await rootBundle.load(assetPath);
    await file.writeAsBytes(data.buffer.asUint8List());
  }

  void dispose() {
    _stream?.free();
    _recognizer?.free();
    _transcriptController.close();
  }
}