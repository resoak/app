import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_vault/services/recording_service.dart';
import 'package:record/record.dart';

class _FakeRecorderClient implements RecorderClient {
  _FakeRecorderClient({
    required this.hasPermissionResult,
    this.bytesEmittedOnStop,
  });

  final bool hasPermissionResult;
  final Uint8List? bytesEmittedOnStop;
  final StreamController<Uint8List> controller = StreamController<Uint8List>();
  bool startCalled = false;
  bool stopCalled = false;

  @override
  Future<bool> hasPermission() async => hasPermissionResult;

  @override
  Future<Stream<Uint8List>> startStream(RecordConfig config) async {
    startCalled = true;
    return controller.stream;
  }

  @override
  Future<String?> stop() async {
    stopCalled = true;
    if (bytesEmittedOnStop != null) {
      controller.add(bytesEmittedOnStop!);
      await Future<void>.delayed(Duration.zero);
    }
    await controller.close();
    return null;
  }
}

Uint8List _pcm16Samples(List<int> samples) {
  final data = ByteData(samples.length * 2);
  for (var i = 0; i < samples.length; i++) {
    data.setInt16(i * 2, samples[i], Endian.little);
  }
  return data.buffer.asUint8List();
}

void main() {
  group('RecordingService', () {
    test('uses mic Android recorder config', () {
      expect(RecordingService.recordingConfig.encoder, AudioEncoder.pcm16bits);
      expect(RecordingService.recordingConfig.sampleRate, 16000);
      expect(RecordingService.recordingConfig.numChannels, 1);
      expect(
        RecordingService.recordingConfig.androidConfig.audioSource,
        AndroidAudioSource.mic,
      );
    });

    test('permission denied returns false without starting recorder', () async {
      final recorder = _FakeRecorderClient(hasPermissionResult: false);
      final tempDir = await Directory.systemTemp.createTemp('recording_test_');

      final service = RecordingService(
        recorder: recorder,
        documentsDirectory: () async => tempDir,
      );

      final started = await service.start();

      expect(started, isFalse);
      expect(recorder.startCalled, isFalse);

      await tempDir.delete(recursive: true);
    });

    test('calculates normalized PCM level from wav source stream data', () {
      expect(
        RecordingService.calculateNormalizedLevel(_pcm16Samples([0, 0, 0, 0])),
        0,
      );

      final quiet = RecordingService.calculateNormalizedLevel(
        _pcm16Samples([500, -500, 750, -750]),
      );
      final loud = RecordingService.calculateNormalizedLevel(
        _pcm16Samples([12000, -12000, 16000, -16000]),
      );

      expect(quiet, greaterThan(0));
      expect(loud, greaterThan(quiet));
      expect(loud, inInclusiveRange(0, 1));
    });

    test('publishes live input level from recorded PCM and resets on stop',
        () async {
      final recorder = _FakeRecorderClient(hasPermissionResult: true);
      final tempDir = await Directory.systemTemp.createTemp('recording_test_');

      final service = RecordingService(
        recorder: recorder,
        documentsDirectory: () async => tempDir,
      );

      final started = await service.start();
      expect(started, isTrue);
      expect(service.inputLevel.value, 0);

      recorder.controller.add(_pcm16Samples([9000, -9000, 12000, -12000]));
      await Future<void>.delayed(Duration.zero);

      expect(service.inputLevel.value, greaterThan(0));

      final path = await service.stop();

      expect(path, isNotNull);
      expect(service.inputLevel.value, 0);

      final file = File(path!);
      if (await file.exists()) {
        await file.delete();
      }
      await tempDir.delete(recursive: true);
    });

    test('stop writes wav file and flushes remaining PCM to STT', () async {
      final recorder = _FakeRecorderClient(hasPermissionResult: true);
      final tempDir = await Directory.systemTemp.createTemp('recording_test_');

      final service = RecordingService(
        recorder: recorder,
        documentsDirectory: () async => tempDir,
      );

      final started = await service.start();
      expect(started, isTrue);

      recorder.controller.add(Uint8List.fromList([0, 0, 255, 127]));
      await Future<void>.delayed(Duration.zero);

      final path = await service.stop();

      expect(recorder.stopCalled, isTrue);

      expect(path, isNotNull);

      final file = File(path!);
      expect(await file.exists(), isTrue);

      final bytes = await file.readAsBytes();
      expect(String.fromCharCodes(bytes.sublist(0, 4)), equals('RIFF'));
      expect(String.fromCharCodes(bytes.sublist(8, 12)), equals('WAVE'));
      expect(bytes.length, equals(48));

      await file.delete();
      await tempDir.delete(recursive: true);
    });

    test('stop keeps final PCM emitted during recorder stop', () async {
      final recorder = _FakeRecorderClient(
        hasPermissionResult: true,
        bytesEmittedOnStop: Uint8List.fromList([0, 0, 255, 127]),
      );
      final tempDir = await Directory.systemTemp.createTemp('recording_test_');

      final service = RecordingService(
        recorder: recorder,
        documentsDirectory: () async => tempDir,
      );

      final started = await service.start();
      expect(started, isTrue);

      final path = await service.stop();

      expect(recorder.stopCalled, isTrue);

      expect(path, isNotNull);

      final file = File(path!);
      expect(await file.exists(), isTrue);
      final bytes = await file.readAsBytes();
      expect(bytes.length, equals(48));

      await file.delete();
      await tempDir.delete(recursive: true);
    });

    test('writes a supported sample rate into wav header', () async {
      final recorder = _FakeRecorderClient(hasPermissionResult: true);
      final tempDir = await Directory.systemTemp.createTemp('recording_test_');

      final service = RecordingService(
        recorder: recorder,
        documentsDirectory: () async => tempDir,
      );

      final started = await service.start();
      expect(started, isTrue);

      recorder.controller.add(Uint8List(8820));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      recorder.controller.add(Uint8List(8820));
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final path = await service.stop();
      expect(path, isNotNull);

      final bytes = await File(path!).readAsBytes();
      final wavRate = ByteData.sublistView(bytes).getUint32(24, Endian.little);
      expect(
          const [8000, 16000, 22050, 32000, 44100, 48000], contains(wavRate));

      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
      await tempDir.delete(recursive: true);
    });
  });
}
