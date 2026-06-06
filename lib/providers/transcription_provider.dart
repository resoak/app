import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';

import '../models/app_settings.dart';
import '../models/lecture.dart';
import '../services/background_transcription_service.dart';
import '../services/summary_service.dart';
import 'app_settings_provider.dart';
import 'drive_backup_provider.dart';

typedef BackgroundLectureTranscriber = Future<void> Function(
  Lecture lecture, {
  WhisperModel whisperModel,
});

enum TranscriptionStatus { transcribing, completed, error }

class TranscriptionState {
  final TranscriptionStatus status;
  final double progress;

  const TranscriptionState({
    required this.status,
    this.progress = 0.0,
  });

  TranscriptionState copyWith({
    TranscriptionStatus? status,
    double? progress,
  }) {
    return TranscriptionState(
      status: status ?? this.status,
      progress: progress ?? this.progress,
    );
  }
}

final backgroundLectureTranscriberProvider =
    Provider<BackgroundLectureTranscriber>((ref) {
  final summaryService = ref.watch(selectedSummaryServiceProvider);
  return (lecture, {whisperModel = WhisperModel.tiny}) async {
    return BackgroundTranscriptionService(
      summaryService: summaryService,
    ).transcribeLecture(
      lecture,
      whisperModel: whisperModel,
    );
  };
});

final extractiveSummaryServiceProvider = Provider<SummaryService>((ref) {
  return const MiniLmSummaryService();
});

final androidLocalLlmSummaryServiceProvider = Provider<SummaryService>((ref) {
  return AndroidLocalLlmSummaryService();
});

final selectedSummaryServiceProvider = Provider<SummaryService>((ref) {
  final settings =
      ref.watch(appSettingsProvider).asData?.value ?? AppSettings.defaults();

  switch (settings.summaryMethod) {
    case AppSummaryMethod.extractive:
      return ref.read(extractiveSummaryServiceProvider);
    case AppSummaryMethod.androidLocalLlm:
      return ref.read(androidLocalLlmSummaryServiceProvider);
  }
});

final transcriptionCleanupDelayProvider = Provider<Duration>((ref) {
  return const Duration(seconds: 2);
});

const _progressUpdateInterval = Duration(milliseconds: 250);

class TranscriptionNotifier extends Notifier<Map<int, TranscriptionState>> {
  final Map<int, Timer> _progressTimers = {};
  final Map<int, Timer> _cleanupTimers = {};
  bool _disposed = false;
  int _activeTranscriptionCount = 0;

  BackgroundLectureTranscriber get _transcriber =>
      ref.read(backgroundLectureTranscriberProvider);

  Duration get _cleanupDelay => ref.read(transcriptionCleanupDelayProvider);

  @override
  Map<int, TranscriptionState> build() {
    ref.onDispose(() {
      _disposed = true;
      for (final timer in _progressTimers.values) {
        timer.cancel();
      }
      for (final timer in _cleanupTimers.values) {
        timer.cancel();
      }
      _progressTimers.clear();
      _cleanupTimers.clear();
      if (_activeTranscriptionCount > 0) {
        WakelockPlus.disable();
      }
    });
    return {};
  }

  Future<void> transcribeLecture(
    Lecture lecture, {
    WhisperModel whisperModel = WhisperModel.base,
  }) async {
    if (lecture.id == null) return;
    final lectureId = lecture.id!;

    final existingState = state[lectureId];
    if (existingState?.status == TranscriptionStatus.transcribing) {
      return;
    }

    _cleanupTimers.remove(lectureId)?.cancel();

    // Initialize state
    state = {
      ...state,
      lectureId: const TranscriptionState(
          status: TranscriptionStatus.transcribing, progress: 0.0),
    };

    _activeTranscriptionCount++;
    if (_activeTranscriptionCount == 1) {
      WakelockPlus.enable();
    }

    // Calculate estimated total ticks.
    // Assuming processing takes roughly 50% of the audio duration
    final estimatedDurationMs =
        (lecture.durationSeconds * 0.5 * 1000).clamp(2000, 300000);
    final totalTicks =
        estimatedDurationMs ~/ _progressUpdateInterval.inMilliseconds;
    int currentTick = 0;

    _progressTimers[lectureId]?.cancel();
    _progressTimers[lectureId] =
        Timer.periodic(_progressUpdateInterval, (timer) {
      if (_disposed) {
        timer.cancel();
        return;
      }

      currentTick++;
      double newProgress = currentTick / totalTicks;

      // Artificial cap at 95% while natively transcribing
      if (newProgress >= 0.95) {
        newProgress =
            0.95 + (newProgress - 0.95) * 0.01; // Extremely slow creeping
        if (newProgress > 0.99) newProgress = 0.99;
      }

      final currentState = state[lectureId];
      if (currentState != null &&
          currentState.status == TranscriptionStatus.transcribing) {
        state = {
          ...state,
          lectureId: currentState.copyWith(progress: newProgress),
        };
      } else {
        timer.cancel();
      }
    });

    try {
      await _transcriber(
        lecture,
        whisperModel: whisperModel,
      );

      // Completed
      _progressTimers[lectureId]?.cancel();
      _progressTimers.remove(lectureId);

      if (!_disposed) {
        state = {
          ...state,
          lectureId: const TranscriptionState(
              status: TranscriptionStatus.completed, progress: 1.0),
        };

        // Remove from state after a brief delay so UI can show 100% momentarily
        _cleanupTimers[lectureId]?.cancel();
        _cleanupTimers[lectureId] = Timer(_cleanupDelay, () {
          _cleanupTimers.remove(lectureId);
          if (!_disposed) {
            final currentState = state[lectureId];
            if (currentState?.status != TranscriptionStatus.completed) {
              return;
            }
            final nextState = Map<int, TranscriptionState>.from(state);
            nextState.remove(lectureId);
            state = nextState;

            // 轉錄與摘要完成後，嘗試觸發 Google Drive 備份
            _triggerAutoBackup();
          }
        });
      }
    } catch (e) {
      debugPrint('Transcription error for lecture $lectureId: $e');
      _progressTimers[lectureId]?.cancel();
      _progressTimers.remove(lectureId);
      if (!_disposed) {
        state = {
          ...state,
          lectureId: const TranscriptionState(
              status: TranscriptionStatus.error, progress: 0.0),
        };
      }
    } finally {
      _activeTranscriptionCount--;
      if (_activeTranscriptionCount <= 0) {
        _activeTranscriptionCount = 0;
        WakelockPlus.disable();
      }
    }
  }

  void _triggerAutoBackup() {
    final backupController = ref.read(driveBackupControllerProvider.notifier);
    final backupState = ref.read(driveBackupControllerProvider);

    // 只有在使用者已登入 Google Drive 的情況下才自動備份
    if (backupState.asData?.value.account.isSignedIn == true) {
      debugPrint('Triggering auto backup after transcription...');
      unawaited(() async {
        try {
          await backupController.createBackup();
        } catch (e) {
          debugPrint('Auto backup failed: $e');
        }
      }());
    }
  }
}

final transcriptionProvider =
    NotifierProvider<TranscriptionNotifier, Map<int, TranscriptionState>>(
  TranscriptionNotifier.new,
);
