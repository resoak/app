// lib/services/recording_service.dart
//
// 處理麥克風錄音，將 PCM 資料送給 SttService
// 同時儲存完整音訊檔案供之後回放

import 'dart:async';
import 'dart:typed_data';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'stt_service.dart';

class RecordingService {
  final _recorder = AudioRecorder();
  final SttService sttService;

  bool _isRecording = false;
  bool get isRecording => _isRecording;

  String? _currentFilePath;
  String? get currentFilePath => _currentFilePath;

  // 計時器
  final _durationController = StreamController<int>.broadcast();
  Stream<int> get durationStream => _durationController.stream;
  Timer? _timer;
  int _seconds = 0;
  int get seconds => _seconds;

  RecordingService({required this.sttService});

  Future<void> start() async {
    if (_isRecording) return;

    // 確認有錄音權限
    if (!await _recorder.hasPermission()) return;

    final dir = await getApplicationDocumentsDirectory();
    final fileName = 'lecture_${DateTime.now().millisecondsSinceEpoch}.m4a';
    _currentFilePath = '${dir.path}/$fileName';

    // 啟動串流（PCM 格式，16kHz mono，送給 STT）
    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
    );

    stream.listen((Uint8List data) {
      // 將 bytes 轉成 List<double>（-1.0 ~ 1.0）
      final samples = <double>[];
      for (int i = 0; i < data.length - 1; i += 2) {
        final sample = data[i] | (data[i + 1] << 8);
        final signed = sample >= 32768 ? sample - 65536 : sample;
        samples.add(signed / 32768.0);
      }
      sttService.acceptWaveform(samples, 16000);
    });

    _isRecording = true;
    _seconds = 0;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _seconds++;
      _durationController.add(_seconds);
    });
  }

  Future<void> stop() async {
    if (!_isRecording) return;
    _timer?.cancel();
    await _recorder.stop();
    _isRecording = false;
  }

  Future<void> dispose() async {
    await stop();
    _durationController.close();
    _recorder.dispose();
  }
}
