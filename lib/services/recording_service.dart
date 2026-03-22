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

  final List<double> _segmentBuffer = [];
  int _silenceFrames = 0;
  static const int _silenceThreshold = 50;
  static const double _silenceLevel = 0.01;
  static const int _minSegmentSamples = 24000; // 最少 1.5 秒

  RecordingService({required this.sttService});

  Future<void> start() async {
    if (!await _recorder.hasPermission()) return;

    final dir = await getApplicationDocumentsDirectory();
    _lastPath = p.join(
      dir.path,
      'rec_${DateTime.now().millisecondsSinceEpoch}.wav',
    );
    _totalPcmBytes = 0;
    _segmentBuffer.clear();
    _silenceFrames = 0;

    _raf = await File(_lastPath!).open(mode: FileMode.write);
    _raf!.writeFromSync(_buildWavHeader(0, 16000));

    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
    );

    _audioStreamSub = stream.listen((data) {
      _raf?.writeFromSync(data);
      _totalPcmBytes += data.length;

      final int16Data = Int16List.view(Uint8List.fromList(data).buffer);
      final samples = int16Data.map((e) => e / 32768.0).toList();

      _segmentBuffer.addAll(samples);

      final rms = _calcRms(samples);

      if (rms < _silenceLevel) {
        _silenceFrames++;
        if (_silenceFrames >= _silenceThreshold &&
            _segmentBuffer.length >= _minSegmentSamples) {
          final segment = List<double>.from(_segmentBuffer);
          _segmentBuffer.clear();
          _silenceFrames = 0;
          sttService.recognizeSegment(segment, 16000);
        }
      } else {
        _silenceFrames = 0;
      }
    });
  }

  double _calcRms(List<double> samples) {
    if (samples.isEmpty) return 0.0;
    double sum = 0;
    for (final s in samples) {
      sum += s * s;
    }
    return sum / samples.length;
  }

  Future<String?> stop() async {
    await _audioStreamSub?.cancel();
    await _recorder.stop();

    if (_segmentBuffer.length >= _minSegmentSamples) {
      await sttService.recognizeSegment(
        List<double>.from(_segmentBuffer),
        16000,
      );
    }
    _segmentBuffer.clear();

    if (_raf == null || _lastPath == null) return null;

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
    buffer.setUint16(20, 1, Endian.little);
    buffer.setUint16(22, 1, Endian.little);
    buffer.setUint32(24, sampleRate, Endian.little);
    buffer.setUint32(28, sampleRate * 2, Endian.little);
    buffer.setUint16(32, 2, Endian.little);
    buffer.setUint16(34, 16, Endian.little);
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