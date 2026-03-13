import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

class SttService {
  sherpa.OnlineRecognizer? _recognizer;
  sherpa.OnlineStream? _stream;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  // 逐字稿串流
  final _transcriptController = StreamController<String>.broadcast();
  Stream<String> get transcriptStream => _transcriptController.stream;

  // 初始化進度串流 (0.0 ~ 1.0)
  final _initProgressController = StreamController<double>.broadcast();
  Stream<double> get initProgressStream => _initProgressController.stream;

  String _fullTranscript = '';
  String get fullTranscript => _fullTranscript;
  String _currentSentence = '';

  /// 強制全域載入 Native Library (解決 OrtGetApiBase 符號找不到的問題)
  Future<void> _forceLoadGlobalLibs() async {
    if (!Platform.isAndroid) return;

    try {
      // RTLD_NOW = 0x00002, RTLD_GLOBAL = 0x00100
      const int rtldFlags = 0x00100 | 0x00002;

      // Android 系統層級的動態連結器
      final libdl = DynamicLibrary.open('libdl.so');
      
      // 查找 dlopen 函式
      final dlopenPtr = libdl.lookup<NativeFunction<Pointer Function(Pointer<Utf8>, Int32)>>('dlopen');
      final dlopen = dlopenPtr.asFunction<Pointer Function(Pointer<Utf8>, int)>();

      // 先載入 libonnxruntime.so 並設定為全域可見
      final libName = 'libonnxruntime.so'.toNativeUtf8();
      final handle = dlopen(libName, rtldFlags);
      
      if (handle == nullptr) {
        debugPrint('===> [Native] 警告: 無法預載入 libonnxruntime.so，嘗試直接打開');
        DynamicLibrary.open('libonnxruntime.so');
      } else {
        debugPrint('===> [Native] libonnxruntime.so 符號已成功全域開放 (RTLD_GLOBAL)');
      }
      malloc.free(libName);

      // 接著載入 sherpa 的 C API
      DynamicLibrary.open('libsherpa-onnx-c-api.so');
      debugPrint('===> [Native] libsherpa-onnx-c-api.so 已就緒');
    } catch (e) {
      debugPrint('===> [Native] Native 連結過程發生錯誤: $e');
    }
  }

  Future<void> initialize() async {
    if (_isInitialized) {
      _initProgressController.add(1.0);
      return;
    }

    try {
      // 1. 處理 Android 原生函式庫連結 (針對 S24 等新機型)
      await _forceLoadGlobalLibs();

      // 2. 初始化套件繫結
      sherpa.initBindings();

      // 3. 準備模型存放目錄
      final dir = await getApplicationDocumentsDirectory();
      final modelDir = '${dir.path}/sherpa_model';
      await Directory(modelDir).create(recursive: true);

      final modelFiles = [
        'encoder.onnx',
        'decoder.onnx',
        'joiner.onnx',
        'tokens.txt',
      ];

      // 4. 複製 Asset 檔案到 App 私有目錄
      for (int i = 0; i < modelFiles.length; i++) {
        double progress = i / modelFiles.length;
        _initProgressController.add(progress);
        
        await _copyAsset(
          'assets/models/stt/${modelFiles[i]}', 
          '$modelDir/${modelFiles[i]}'
        );
      }
      
      _initProgressController.add(0.9); 

      // 5. 設定語音辨識引擎參數 (針對 S24 性能優化)
      final transducer = sherpa.OnlineTransducerModelConfig(
        encoder: '$modelDir/encoder.onnx',
        decoder: '$modelDir/decoder.onnx',
        joiner: '$modelDir/joiner.onnx',
      );

      final modelConfig = sherpa.OnlineModelConfig(
        transducer: transducer,
        tokens: '$modelDir/tokens.txt',
        numThreads: 4, // S24 建議 4 執行緒，達到功耗與速度平衡
        debug: false,
      );

      final config = sherpa.OnlineRecognizerConfig(
        model: modelConfig,
        enableEndpoint: true,
        rule1MinTrailingSilence: 2.4, // 靜止 2.4 秒視為句尾
        rule2MinTrailingSilence: 1.2,
        rule3MinUtteranceLength: 30.0,
      );

      _recognizer = sherpa.OnlineRecognizer(config);
      _stream = _recognizer!.createStream();
      
      _isInitialized = true;
      _initProgressController.add(1.0);
      debugPrint('[STT] 服務啟動成功');
    } catch (e) {
      debugPrint('[STT] 初始化失敗: $e');
      _initProgressController.addError(e);
      rethrow;
    }
  }

  void acceptWaveform(List<double> samples, int sampleRate) {
    if (!_isInitialized || _stream == null || _recognizer == null) return;
    try {
      _stream!.acceptWaveform(
        samples: Float32List.fromList(samples),
        sampleRate: sampleRate,
      );
      _decode();
    } catch (e) {
      debugPrint('[STT] 串流處理錯誤: $e');
    }
  }

  void _decode() {
    while (_recognizer!.isReady(_stream!)) {
      _recognizer!.decode(_stream!);
    }
    
    final result = _recognizer!.getResult(_stream!);
    final text = result.text.trim();
    
    // 即時更新畫面上顯示的內容
    if (text.isNotEmpty && text != _currentSentence) {
      _currentSentence = text;
      _transcriptController.add(_fullTranscript + _currentSentence);
    }

    // 檢測到語句結束 (斷句)
    if (_recognizer!.isEndpoint(_stream!)) {
      if (_currentSentence.isNotEmpty) {
        _fullTranscript += '$_currentSentence。\n';
        _currentSentence = ''; 
      }
      _recognizer!.reset(_stream!);
    }
  }

  Future<void> _copyAsset(String assetPath, String targetPath) async {
    final file = File(targetPath);
    // 簡單檢查檔案是否存在且大小不為 0，避免重複複製
    if (await file.exists() && await file.length() > 0) return;

    try {
      final data = await rootBundle.load(assetPath);
      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      await file.writeAsBytes(bytes, flush: true);
      debugPrint('[Asset] 成功複製: $assetPath');
    } catch (e) {
      if (await file.exists()) await file.delete();
      throw Exception('檔案複製失敗: $assetPath, 錯誤: $e');
    }
  }

  void dispose() {
    _stream?.free();
    _recognizer?.free();
    _transcriptController.close();
    _initProgressController.close();
    debugPrint('[STT] 資源已釋放');
  }
}