import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';

import '../models/lecture.dart';
import 'db_service.dart';
import 'summary_service.dart';
import 'stt_service.dart';

typedef SttServiceFactory = SttService Function(WhisperModel whisperModel);

class BackgroundTranscriptionService {
  BackgroundTranscriptionService({
    DbService? dbService,
    SummaryService? summaryService,
    SttServiceFactory? sttServiceFactory,
  })  : _dbService = dbService ?? DbService(),
        _summaryService = summaryService ?? const MiniLmSummaryService(),
        _sttServiceFactory = sttServiceFactory ??
            ((whisperModel) => SttService(whisperModel: whisperModel));

  final DbService _dbService;
  final SummaryService _summaryService;
  final SttServiceFactory _sttServiceFactory;

  Future<void> transcribeLecture(
    Lecture lecture, {
    WhisperModel whisperModel = WhisperModel.base,
  }) async {
    final sttService = _sttServiceFactory(whisperModel);
    final currentLecture = lecture.copyWith(
      transcriptionStatus: LectureProcessingStatus.processing,
      summaryStatus: LectureProcessingStatus.pending,
      summary: '',
    );

    try {
      if (currentLecture.id != null) {
        await _dbService.updateLecture(currentLecture);
      }

      final audioPath = await _dbService.resolveAudioPath(currentLecture);
      await sttService.transcribeFile(audioPath);
      final transcript = sttService.persistedTranscript;
      final transcribedLecture = currentLecture.copyWith(
        transcript: transcript,
        timeline: sttService.timeline,
        transcriptionStatus: LectureProcessingStatus.completed,
        summaryStatus: LectureProcessingStatus.processing,
      );

      await _dbService.updateLecture(transcribedLecture);

      try {
        final summary = await _summaryService.summarizeTranscript(transcript);

        await _dbService.updateLecture(
          transcribedLecture.copyWith(
            summary: summary,
            summaryStatus: LectureProcessingStatus.completed,
          ),
        );
      } catch (_) {
        await _dbService.updateLecture(
          transcribedLecture.copyWith(
            summary: '',
            summaryStatus: LectureProcessingStatus.failed,
          ),
        );
      }
    } catch (_) {
      await _dbService.updateLecture(
        currentLecture.copyWith(
          transcript: '',
          summary: '',
          transcriptionStatus: LectureProcessingStatus.failed,
          summaryStatus: LectureProcessingStatus.failed,
        ),
      );
      rethrow;
    } finally {
      sttService.dispose();
    }
  }
}
