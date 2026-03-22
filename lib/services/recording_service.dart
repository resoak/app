import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:path/path.dart' as p;
import 'stt_service.dart';

class RecordingService {
  final SttService sttService;
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription? _audioStreamSub;
  String? _lastPath;
  RandomAccessFile? _raf;
  int _totalPcmBytes = 0;

  RecordingService({required this.sttService});

  Future<void> start() async {
    if (!await _recorder.hasPermission()) return;

    final dir = await getApplicationDocumentsDirectory();
    _lastPath = p.join(
      dir.path,
      'rec_${DateTime.now().millisecondsSinceEpoch}.wav',
    );
    _totalPcmBytes = 0;

    _raf = await File(_lastPath!).open(mode: FileMode.write);
    _raf!.writeFromSync(_buildWavHeader(0, 16000)); // 佔位 header

    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
    );

    List<int> sttBuffer = [];
    _audioStreamSub = stream.listen((data) {
      // 同步寫入，避免 async 造成 stop() 時資料遺失
      _raf?.writeFromSync(data);
      _totalPcmBytes += data.length;

      // 餵給 STT
      sttBuffer.addAll(data);
      if (sttBuffer.length >= 12800) {
        final int16Data = Int16List.view(Uint8List.fromList(sttBuffer).buffer);
        final samples = int16Data.map((e) => e / 32768.0).toList();
        sttService.acceptWaveform(samples, 16000);
        sttBuffer.clear();
      }
    });
  }

  Future<String?> stop() async {
    await _audioStreamSub?.cancel();
    await _recorder.stop();

    if (_raf == null || _lastPath == null) return null;

    // 回頭補寫正確的 WAV header
    _raf!.setPositionSync(0);
    _raf!.writeFromSync(_buildWavHeader(_totalPcmBytes, 16000));
    await _raf!.close();
    _raf = null;

    return _lastPath;
  }

  Uint8List _buildWavHeader(int dataBytes, int sampleRate) {
    final buffer = ByteData(44);

    _setString(buffer, 0, 'RIFF');
    buffer.setUint32(4, 36 + dataBytes, Endian.little);
    _setString(buffer, 8, 'WAVE');
    _setString(buffer, 12, 'fmt ');
    buffer.setUint32(16, 16, Endian.little);
    buffer.setUint16(20, 1, Endian.little);       // PCM
    buffer.setUint16(22, 1, Endian.little);       // mono
    buffer.setUint32(24, sampleRate, Endian.little);
    buffer.setUint32(28, sampleRate * 2, Endian.little); // byte rate
    buffer.setUint16(32, 2, Endian.little);       // block align
    buffer.setUint16(34, 16, Endian.little);      // bits per sample
    _setString(buffer, 36, 'data');
    buffer.setUint32(40, dataBytes, Endian.little);

    return buffer.buffer.asUint8List();
  }

  void _setString(ByteData buffer, int offset, String value) {
    for (int i = 0; i < value.length; i++) {
      buffer.setUint8(offset + i, value.codeUnitAt(i));
    }
  }
}