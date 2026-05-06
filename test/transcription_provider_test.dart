import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_vault/models/lecture.dart';
import 'package:lecture_vault/providers/transcription_provider.dart';
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

class _FakeWakelockPlatform extends WakelockPlusPlatformInterface {
  bool enabledState = false;

  @override
  bool get isMock => true;

  @override
  Future<void> toggle({required bool enable}) async {
    enabledState = enable;
  }

  @override
  Future<bool> get enabled async => enabledState;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late WakelockPlusPlatformInterface originalWakelockPlatform;

  setUp(() {
    originalWakelockPlatform = WakelockPlusPlatformInterface.instance;
    WakelockPlusPlatformInterface.instance = _FakeWakelockPlatform();
  });

  tearDown(() {
    WakelockPlusPlatformInterface.instance = originalWakelockPlatform;
  });

  group('TranscriptionNotifier', () {
    test('stale delayed cleanup does not remove newer transcription state',
        () async {
      final completions = <Completer<void>>[];
      Future<void> fakeTranscriber(
        Lecture lecture, {
        dynamic whisperModel,
      }) {
        final completer = Completer<void>();
        completions.add(completer);
        return completer.future;
      }

      final container = ProviderContainer(
        overrides: [
          backgroundLectureTranscriberProvider
              .overrideWithValue(fakeTranscriber),
          transcriptionCleanupDelayProvider.overrideWithValue(
            const Duration(milliseconds: 20),
          ),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(transcriptionProvider.notifier);
      final lecture = Lecture(
        id: 1,
        title: 'Race Test',
        date: DateTime.utc(2026, 4, 25).toIso8601String(),
        audioPath: '/tmp/race.wav',
        durationSeconds: 10,
      );

      final firstRun = notifier.transcribeLecture(lecture);
      expect(
        container.read(transcriptionProvider)[1]?.status,
        TranscriptionStatus.transcribing,
      );

      completions.first.complete();
      await firstRun;
      expect(
        container.read(transcriptionProvider)[1]?.status,
        TranscriptionStatus.completed,
      );

      final secondRun = notifier.transcribeLecture(lecture);
      expect(
        container.read(transcriptionProvider)[1]?.status,
        TranscriptionStatus.transcribing,
      );

      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(
        container.read(transcriptionProvider)[1]?.status,
        TranscriptionStatus.transcribing,
      );

      completions[1].complete();
      await secondRun;
      expect(
        container.read(transcriptionProvider)[1]?.status,
        TranscriptionStatus.completed,
      );

      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(container.read(transcriptionProvider).containsKey(1), isFalse);
    });

    test('failed transcription keeps error state and does not mark completed',
        () async {
      Future<void> failingTranscriber(
        Lecture lecture, {
        dynamic whisperModel,
      }) async {
        throw StateError('plugin failed');
      }

      final container = ProviderContainer(
        overrides: [
          backgroundLectureTranscriberProvider
              .overrideWithValue(failingTranscriber),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(transcriptionProvider.notifier);
      final lecture = Lecture(
        id: 2,
        title: 'Failure Test',
        date: DateTime.utc(2026, 5, 3).toIso8601String(),
        audioPath: '/tmp/failure.wav',
        durationSeconds: 10,
      );

      await notifier.transcribeLecture(lecture);

      expect(
        container.read(transcriptionProvider)[2]?.status,
        TranscriptionStatus.error,
      );
      expect(
        container.read(transcriptionProvider)[2]?.progress,
        0.0,
      );
    });
  });
}
