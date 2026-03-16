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

  // 供測試檔讀取狀態
  bool get isInitialized => _isInitialized;
  
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
      decodingMethod: 'greedy_search',
      enableEndpoint: true,
      rule2MinTrailingSilence: 2.0,
    );

    _recognizer = sherpa.OnlineRecognizer(config);
    _stream = _recognizer!.createStream();
    _isInitialized = true;
  }

  void resetStream() {
    _stream?.free();
    _stream = _recognizer?.createStream();
    _fullTranscript = "";
  }

  void acceptWaveform(List<double> samples, int sampleRate) {
    if (_stream == null) return;
    _stream!.acceptWaveform(samples: Float32List.fromList(samples), sampleRate: sampleRate);
    while (_recognizer!.isReady(_stream!)) {
      _recognizer!.decode(_stream!);
    }
    final result = _recognizer!.getResult(_stream!);
    if (result.text.isNotEmpty) {
      _fullTranscript = result.text;
      _transcriptController.add(_fullTranscript);
    }
    if (_recognizer!.isEndpoint(_stream!)) _recognizer!.reset(_stream!);
  }

  // 補上 dispose 方法解決測試檔 Error
  void dispose() {
    _stream?.free();
    _recognizer?.free();
    _isInitialized = false;
  }
}