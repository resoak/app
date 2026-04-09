import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'package:record/record.dart';

import 'stt_service.dart';

abstract class RecorderClient {
  Future<bool> hasPermission();
  Future<Stream<Uint8List>> startStream(RecordConfig config);
  Future<String?> stop();
}

class AudioRecorderClient implements RecorderClient {
  AudioRecorderClient([AudioRecorder? recorder])
      : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<Stream<Uint8List>> startStream(RecordConfig config) =>
      _recorder.startStream(config);

  @override
  Future<String?> stop() => _recorder.stop();
}

class RecordingService {
  final SttSink sttService;
  final RecorderClient _recorder;
  final Future<Directory> Function() _documentsDirectory;
  StreamSubscription? _audioStreamSub;
  String? _lastPath;
  RandomAccessFile? _raf;
  int _totalPcmBytes = 0;
  final List<int> _sttBuffer = [];

  RecordingService({
    required this.sttService,
    RecorderClient? recorder,
    Future<Directory> Function()? documentsDirectory,
  })  : _recorder = recorder ?? AudioRecorderClient(),
        _documentsDirectory =
            documentsDirectory ?? getApplicationDocumentsDirectory;

  Future<bool> start() async {
    if (!await _recorder.hasPermission()) return false;

    final dir = await _documentsDirectory();
    final path = p.join(
      dir.path,
      'rec_${DateTime.now().millisecondsSinceEpoch}.wav',
    );
    _lastPath = path;
    _totalPcmBytes = 0;
    _sttBuffer.clear();

    try {
      _raf = await File(path).open(mode: FileMode.write);
      _raf!.writeFromSync(_buildWavHeader(0, 16000)); // 佔位 header

      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );

      _audioStreamSub = stream.listen((data) {
        // 同步寫入，避免 async 造成 stop() 時資料遺失
        _raf?.writeFromSync(data);
        _totalPcmBytes += data.length;

        // 餵給 STT
        _sttBuffer.addAll(data);
        _flushSttBuffer();
      });

      return true;
    } catch (_) {
      await _audioStreamSub?.cancel();
      _audioStreamSub = null;
      await _raf?.close();
      _raf = null;
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
      _lastPath = null;
      rethrow;
    }
  }

  Future<String?> stop() async {
    await _audioStreamSub?.cancel();

    _flushSttBuffer(force: true);
    sttService.finalizeStream();

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
    buffer.setUint16(20, 1, Endian.little); // PCM
    buffer.setUint16(22, 1, Endian.little); // mono
    buffer.setUint32(24, sampleRate, Endian.little);
    buffer.setUint32(28, sampleRate * 2, Endian.little); // byte rate
    buffer.setUint16(32, 2, Endian.little); // block align
    buffer.setUint16(34, 16, Endian.little); // bits per sample
    _setString(buffer, 36, 'data');
    buffer.setUint32(40, dataBytes, Endian.little);

    return buffer.buffer.asUint8List();
  }

  void _setString(ByteData buffer, int offset, String value) {
    for (int i = 0; i < value.length; i++) {
      buffer.setUint8(offset + i, value.codeUnitAt(i));
    }
  }

  void _flushSttBuffer({bool force = false}) {
    var bytesToProcess = _sttBuffer.length - (_sttBuffer.length % 2);
    if (!force && bytesToProcess < 12800) return;
    if (bytesToProcess == 0) return;

    final pcmBytes = Uint8List.fromList(_sttBuffer.sublist(0, bytesToProcess));
    final int16Data = Int16List.view(pcmBytes.buffer);
    final samples = int16Data.map((e) => e / 32768.0).toList(growable: false);
    sttService.acceptWaveform(samples, 16000);
    _sttBuffer.removeRange(0, bytesToProcess);

    if (force && _sttBuffer.isNotEmpty) {
      debugPrint('RecordingService dropped trailing partial PCM byte.');
      _sttBuffer.clear();
    }
  }
}
