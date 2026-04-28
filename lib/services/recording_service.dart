import 'dart:async';
import 'dart:math' as math;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'package:record/record.dart';

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
  static const int _defaultSampleRate = 16000;
  static final String _managedAudioDirectory = p.join('media', 'audio');
  final RecorderClient _recorder;
  final Future<Directory> Function() _documentsDirectory;
  final ValueNotifier<double> _inputLevel = ValueNotifier<double>(0);
  StreamSubscription? _audioStreamSub;
  String? _lastPath;
  String? _lastManagedAudioPath;
  RandomAccessFile? _raf;
  int _totalPcmBytes = 0;
  Stopwatch? _streamClock;

  RecordingService({
    RecorderClient? recorder,
    Future<Directory> Function()? documentsDirectory,
  })  : _recorder = recorder ?? AudioRecorderClient(),
        _documentsDirectory =
            documentsDirectory ?? getApplicationDocumentsDirectory;

  @visibleForTesting
  static const RecordConfig recordingConfig = RecordConfig(
    encoder: AudioEncoder.pcm16bits,
    sampleRate: 16000,
    numChannels: 1,
    androidConfig: AndroidRecordConfig(
      audioSource: AndroidAudioSource.mic,
    ),
  );

  String? get lastManagedAudioPath => _lastManagedAudioPath;
  ValueListenable<double> get inputLevel => _inputLevel;

  Future<bool> start() async {
    if (!await _recorder.hasPermission()) return false;

    final dir = await _documentsDirectory();
    final managedAudioPath = p.join(
      _managedAudioDirectory,
      'rec_${DateTime.now().millisecondsSinceEpoch}.wav',
    );
    final path = p.join(dir.path, managedAudioPath);
    _lastPath = path;
    _lastManagedAudioPath = managedAudioPath;
    _totalPcmBytes = 0;
    _publishInputLevel(0);

    try {
      await File(path).parent.create(recursive: true);
      _raf = await File(path).open(mode: FileMode.write);
      _raf!.writeFromSync(_buildWavHeader(0, _defaultSampleRate)); // 佔位 header
      _streamClock = Stopwatch()..start();

      final stream = await _recorder.startStream(recordingConfig);

      _audioStreamSub = stream.listen((data) {
        // 同步寫入，避免 async 造成 stop() 時資料遺失
        _raf?.writeFromSync(data);
        _totalPcmBytes += data.length;
        _updateInputLevel(data);
      }, onError: (Object error, StackTrace stackTrace) {
        debugPrint('RecordingService audio stream error: $error');
        _publishInputLevel(0);
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
      _lastManagedAudioPath = null;
      _publishInputLevel(0);
      rethrow;
    }
  }

  Future<String?> stop() async {
    await _recorder.stop();
    await _audioStreamSub?.cancel();
    _audioStreamSub = null;
    _publishInputLevel(0);

    if (_raf == null || _lastPath == null) return null;

    // 回頭補寫正確的 WAV header
    final actualSampleRate = _estimateSampleRate();
    _raf!.setPositionSync(0);
    _raf!.writeFromSync(_buildWavHeader(_totalPcmBytes, actualSampleRate));
    await _raf!.close();
    _raf = null;
    _streamClock?.stop();
    _streamClock = null;

    return _lastPath;
  }

  void _updateInputLevel(Uint8List pcmBytes) {
    final rawLevel = calculateNormalizedLevel(pcmBytes);
    final liftedLevel = math.pow(rawLevel, 0.7).toDouble();
    final currentLevel = _inputLevel.value;
    final smoothedLevel = liftedLevel > currentLevel
        ? currentLevel + (liftedLevel - currentLevel) * 0.55
        : currentLevel * 0.82 + liftedLevel * 0.18;
    _publishInputLevel(smoothedLevel);
  }

  void _publishInputLevel(double level) {
    _inputLevel.value = level.clamp(0.0, 1.0);
  }

  @visibleForTesting
  static double calculateNormalizedLevel(Uint8List pcmBytes) {
    final sampleCount = pcmBytes.length ~/ 2;
    if (sampleCount == 0) return 0;

    final byteData = ByteData.sublistView(pcmBytes);
    var sumSquares = 0.0;

    for (var offset = 0; offset + 1 < pcmBytes.length; offset += 2) {
      final normalizedSample =
          byteData.getInt16(offset, Endian.little) / 32768.0;
      sumSquares += normalizedSample * normalizedSample;
    }

    final rms = math.sqrt(sumSquares / sampleCount);
    const noiseFloor = 0.015;
    if (rms <= noiseFloor) return 0;

    return ((rms - noiseFloor) / (1 - noiseFloor)).clamp(0.0, 1.0);
  }

  int _estimateSampleRate() {
    final elapsedMicros = _streamClock?.elapsedMicroseconds ?? 0;
    if (elapsedMicros <= 80000 || _totalPcmBytes <= 0) {
      return _defaultSampleRate;
    }

    final samples = _totalPcmBytes / 2;
    final estimated = (samples * 1000000 / elapsedMicros).round();
    const allowedRates = [8000, 16000, 22050, 32000, 44100, 48000];

    var best = allowedRates.first;
    var bestDiff = (estimated - best).abs();
    for (final rate in allowedRates.skip(1)) {
      final diff = (estimated - rate).abs();
      if (diff < bestDiff) {
        best = rate;
        bestDiff = diff;
      }
    }
    return best;
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
}
