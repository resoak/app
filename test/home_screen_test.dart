import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_vault/providers/transcription_provider.dart';
import 'package:lecture_vault/screens/home_screen.dart';

void main() {
  group('transcriptionProgressBadgeLabel', () {
    test('does not show a fake 0 percent when live progress is unavailable',
        () {
      expect(transcriptionProgressBadgeLabel(null), '轉錄中…');
    });

    test('shows percent when live progress exists', () {
      const state = TranscriptionState(
        status: TranscriptionStatus.transcribing,
        progress: 0.42,
      );

      expect(transcriptionProgressBadgeLabel(state), '轉錄中 42%');
    });

    test('clamps progress percent to the valid UI range', () {
      const state = TranscriptionState(
        status: TranscriptionStatus.transcribing,
        progress: 1.2,
      );

      expect(transcriptionProgressBadgeLabel(state), '轉錄中 100%');
    });
  });
}
