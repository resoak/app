import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_vault/services/recording_service.dart';
import 'package:lecture_vault/services/stt_service.dart';
import 'package:record/record.dart';

class _FakeRecorderClient implements RecorderClient {
  _FakeRecorderClient({required this.hasPermissionResult});

  final bool hasPermissionResult;
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
    await controller.close();
    return null;
  }
}

class _FakeSttSink implements SttSink {
  final List<List<double>> acceptedWaveforms = [];
  bool finalized = false;

  @override
  void acceptWaveform(List<double> samples, int sampleRate) {
    acceptedWaveforms.add(samples);
  }

  @override
  void finalizeStream() {
    finalized = true;
  }
}

void main() {
  group('RecordingService', () {
    test('permission denied returns false without starting recorder', () async {
      final recorder = _FakeRecorderClient(hasPermissionResult: false);
      final stt = _FakeSttSink();
      final tempDir = await Directory.systemTemp.createTemp('recording_test_');

      final service = RecordingService(
        sttService: stt,
        recorder: recorder,
        documentsDirectory: () async => tempDir,
      );

      final started = await service.start();

      expect(started, isFalse);
      expect(recorder.startCalled, isFalse);

      await tempDir.delete(recursive: true);
    });

    test('stop writes wav file and flushes remaining PCM to STT', () async {
      final recorder = _FakeRecorderClient(hasPermissionResult: true);
      final stt = _FakeSttSink();
      final tempDir = await Directory.systemTemp.createTemp('recording_test_');

      final service = RecordingService(
        sttService: stt,
        recorder: recorder,
        documentsDirectory: () async => tempDir,
      );

      final started = await service.start();
      expect(started, isTrue);

      recorder.controller.add(Uint8List.fromList([0, 0, 255, 127]));
      await Future<void>.delayed(Duration.zero);

      final path = await service.stop();

      expect(recorder.stopCalled, isTrue);
      expect(stt.finalized, isTrue);
      expect(stt.acceptedWaveforms, hasLength(1));
      expect(stt.acceptedWaveforms.first, hasLength(2));
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

    test('odd trailing PCM byte does not crash stop', () async {
      final recorder = _FakeRecorderClient(hasPermissionResult: true);
      final stt = _FakeSttSink();
      final tempDir = await Directory.systemTemp.createTemp('recording_test_');

      final service = RecordingService(
        sttService: stt,
        recorder: recorder,
        documentsDirectory: () async => tempDir,
      );

      final started = await service.start();
      expect(started, isTrue);

      recorder.controller.add(Uint8List.fromList([0, 0, 255]));
      await Future<void>.delayed(Duration.zero);

      final path = await service.stop();

      expect(path, isNotNull);
      expect(stt.finalized, isTrue);
      expect(stt.acceptedWaveforms, hasLength(1));
      expect(stt.acceptedWaveforms.first, hasLength(1));

      final file = File(path!);
      if (await file.exists()) {
        await file.delete();
      }
      await tempDir.delete(recursive: true);
    });
  });
}
