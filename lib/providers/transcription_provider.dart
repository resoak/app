import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';

import '../models/lecture.dart';
import '../services/background_transcription_service.dart';

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

class TranscriptionNotifier extends Notifier<Map<int, TranscriptionState>> {
  final Map<int, Timer> _timers = {};
  bool _disposed = false;

  @override
  Map<int, TranscriptionState> build() {
    ref.onDispose(() {
      _disposed = true;
      for (final timer in _timers.values) {
        timer.cancel();
      }
      _timers.clear();
    });
    return {};
  }

  Future<void> transcribeLecture(
    Lecture lecture, {
    WhisperModel whisperModel = WhisperModel.base,
  }) async {
    if (lecture.id == null) return;
    final lectureId = lecture.id!;

    // Initialize state
    state = {
      ...state,
      lectureId: const TranscriptionState(
          status: TranscriptionStatus.transcribing, progress: 0.0),
    };

    // Calculate estimated total ticks
    // Assuming 10 ticks per second (every 100ms)
    // Assuming processing takes roughly 50% of the audio duration
    final estimatedDurationMs =
        (lecture.durationSeconds * 0.5 * 1000).clamp(2000, 300000);
    final totalTicks = estimatedDurationMs ~/ 100;
    int currentTick = 0;

    _timers[lectureId]?.cancel();
    _timers[lectureId] =
        Timer.periodic(const Duration(milliseconds: 100), (timer) {
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
      final service = BackgroundTranscriptionService();
      await service.transcribeLecture(
        lecture,
        whisperModel: whisperModel,
      );

      // Completed
      _timers[lectureId]?.cancel();
      _timers.remove(lectureId);

      if (!_disposed) {
        state = {
          ...state,
          lectureId: const TranscriptionState(
              status: TranscriptionStatus.completed, progress: 1.0),
        };

        // Remove from state after a brief delay so UI can show 100% momentarily
        Future.delayed(const Duration(seconds: 2), () {
          if (!_disposed) {
            final nextState = Map<int, TranscriptionState>.from(state);
            nextState.remove(lectureId);
            state = nextState;
          }
        });
      }
    } catch (_) {
      _timers[lectureId]?.cancel();
      _timers.remove(lectureId);
      if (!_disposed) {
        state = {
          ...state,
          lectureId: const TranscriptionState(
              status: TranscriptionStatus.error, progress: 0.0),
        };
      }
    }
  }
}

final transcriptionProvider =
    NotifierProvider<TranscriptionNotifier, Map<int, TranscriptionState>>(
  TranscriptionNotifier.new,
);
