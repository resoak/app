import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';

import '../models/lecture.dart';
import '../utils/paragraph_summary.dart';
import 'db_service.dart';
import 'stt_service.dart';

class BackgroundTranscriptionService {
  BackgroundTranscriptionService({DbService? dbService})
      : _dbService = dbService ?? DbService();

  final DbService _dbService;

  Future<void> transcribeLecture(
    Lecture lecture, {
    WhisperModel whisperModel = WhisperModel.base,
  }) async {
    final sttService = SttService(whisperModel: whisperModel);

    try {
      await sttService.transcribeFile(lecture.audioPath);
      final transcript = sttService.persistedTranscript;
      final summary = await ParagraphSummary.fromTranscript(transcript);

      await _dbService.updateLecture(
        lecture.copyWith(
          transcript: transcript,
          summary: summary,
          timeline: sttService.timeline,
        ),
      );
    } catch (_) {
      await _dbService.updateLecture(
        lecture.copyWith(summary: '背景轉錄失敗，請稍後再試。'),
      );
    } finally {
      sttService.dispose();
    }
  }
}
