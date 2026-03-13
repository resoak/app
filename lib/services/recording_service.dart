import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'stt_service.dart';

class RecordingService {
  final _recorder = AudioRecorder();
  final SttService sttService;

  bool _isRecording = false;
  bool get isRecording => _isRecording;

  String? _currentFilePath;
  String? get currentFilePath => _currentFilePath;

  final _durationController = StreamController<int>.broadcast();
  Stream<int> get durationStream => _durationController.stream;
  Timer? _timer;
  int _seconds = 0;
  int get seconds => _seconds;

  RecordingService({required this.sttService});

  Future<void> start() async {
    if (_isRecording) return;

    try {
      // 1. 確認錄音權限
      if (!await _recorder.hasPermission()) {
        throw Exception('未獲得麥克風權限');
      }

      // 2. 設定存檔路徑 (用於回放)
      final dir = await getApplicationDocumentsDirectory();
      final fileName = 'lecture_${DateTime.now().millisecondsSinceEpoch}.m4a';
      _currentFilePath = '${dir.path}/$fileName';

      // 3. 啟動錄音串流 (PCM 16-bit, 16kHz, Mono)
      // 注意：某些版本的 record 套件在 startStream 時不會同時存檔到路徑
      // 若需要同時存檔，建議使用 start() 到路徑，或手動寫入檔案
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );

      // 4. 監聽串流並轉換格式給 STT
      stream.listen((Uint8List data) {
        _handleAudioData(data);
      });

      _isRecording = true;
      _seconds = 0;
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        _seconds++;
        _durationController.add(_seconds);
      });

      debugPrint('[Recording] 錄音開始: $_currentFilePath');
    } catch (e) {
      debugPrint('[Recording] 啟動失敗: $e');
      rethrow;
    }
  }

  /// 高效轉換 PCM Uint8List 為 Float32List (-1.0 ~ 1.0)
  void _handleAudioData(Uint8List data) {
    if (data.isEmpty) return;

    // 使用 ByteData 處理小端序 (Little Endian) 轉換，效能較佳
    final byteData = ByteData.sublistView(data);
    final int sampleCount = data.length ~/ 2;
    final samples = Float64List(sampleCount); // 使用 Float64List 或 List<double>

    for (int i = 0; i < sampleCount; i++) {
      // PCM 16bit 是有號整數 (Int16)
      final int pcmSample = byteData.getInt16(i * 2, Endian.little);
      // 正規化至 -1.0 到 1.0
      samples[i] = pcmSample / 32768.0;
    }

    // 將處理後的樣本送往 STT 服務
    sttService.acceptWaveform(samples.toList(), 16000);
  }

  Future<void> stop() async {
    if (!_isRecording) return;
    _timer?.cancel();
    
    // 停止錄音並取得檔案路徑
    final path = await _recorder.stop();
    if (path != null) {
      _currentFilePath = path;
    }
    
    _isRecording = false;
    debugPrint('[Recording] 錄音停止，檔案儲存於: $_currentFilePath');
  }

  Future<void> dispose() async {
    await stop();
    _durationController.close();
    _recorder.dispose();
  }
}