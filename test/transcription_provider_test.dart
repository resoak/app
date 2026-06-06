import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_vault/models/app_settings.dart';
import 'package:lecture_vault/models/lecture.dart';
import 'package:lecture_vault/providers/app_settings_provider.dart';
import 'package:lecture_vault/providers/transcription_provider.dart';
import 'package:lecture_vault/services/summary_service.dart';
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

    test('duplicate start does not reset active progress to zero', () async {
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
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(transcriptionProvider.notifier);
      final lecture = Lecture(
        id: 3,
        title: 'Duplicate Start Test',
        date: DateTime.utc(2026, 6, 6).toIso8601String(),
        audioPath: '/tmp/duplicate.wav',
        durationSeconds: 10,
      );

      final firstRun = notifier.transcribeLecture(lecture);
      await Future<void>.delayed(const Duration(milliseconds: 300));

      final progressBeforeDuplicate =
          container.read(transcriptionProvider)[3]?.progress;
      expect(progressBeforeDuplicate, isNotNull);
      expect(progressBeforeDuplicate, greaterThan(0));

      await notifier.transcribeLecture(lecture);

      final activeState = container.read(transcriptionProvider)[3];
      expect(activeState?.status, TranscriptionStatus.transcribing);
      expect(activeState?.progress, progressBeforeDuplicate);
      expect(completions, hasLength(1));

      completions.first.complete();
      await firstRun;
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

    test('selectedSummaryServiceProvider defaults to extractive flow',
        () async {
      const extractive = _NamedSummaryService('extractive');
      const androidLocalLlm = _NamedSummaryService('android');

      final container = ProviderContainer(
        overrides: [
          appSettingsProvider.overrideWith(
            () => _StaticAppSettingsNotifier(AppSettings.defaults()),
          ),
          extractiveSummaryServiceProvider.overrideWithValue(extractive),
          androidLocalLlmSummaryServiceProvider.overrideWithValue(
            androidLocalLlm,
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(appSettingsProvider.future);

      final summary = await container
          .read(selectedSummaryServiceProvider)
          .summarizeTranscript('demo');
      expect(summary, 'extractive');
    });

    test(
        'selectedSummaryServiceProvider switches to Android local LLM when requested',
        () async {
      const extractive = _NamedSummaryService('extractive');
      const androidLocalLlm = _NamedSummaryService('android');

      final container = ProviderContainer(
        overrides: [
          appSettingsProvider.overrideWith(
            () => _StaticAppSettingsNotifier(
              AppSettings.defaults().copyWith(
                summaryMethod: AppSummaryMethod.androidLocalLlm,
              ),
            ),
          ),
          extractiveSummaryServiceProvider.overrideWithValue(extractive),
          androidLocalLlmSummaryServiceProvider.overrideWithValue(
            androidLocalLlm,
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(appSettingsProvider.future);

      final summary = await container
          .read(selectedSummaryServiceProvider)
          .summarizeTranscript('demo');
      expect(summary, 'android');
    });
  });
}

class _NamedSummaryService implements SummaryService {
  const _NamedSummaryService(this.name);

  final String name;

  @override
  Future<String> summarizeTranscript(String transcript) async => name;
}

class _StaticAppSettingsNotifier extends AppSettingsNotifier {
  _StaticAppSettingsNotifier(this._settings);

  final AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;
}
