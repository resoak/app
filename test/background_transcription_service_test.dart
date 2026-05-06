import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_vault/models/lecture.dart';
import 'package:lecture_vault/services/background_transcription_service.dart';
import 'package:lecture_vault/services/db_service.dart';
import 'package:lecture_vault/services/minilm_runtime_service.dart';
import 'package:lecture_vault/services/summary_service.dart';
import 'package:lecture_vault/services/stt_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';

class _NoopSummaryService implements SummaryService {
  const _NoopSummaryService();

  @override
  Future<String> summarizeTranscript(String transcript) async => 'unused';
}

class _NoopEmbeddingRuntime implements SentenceEmbeddingRuntime {
  const _NoopEmbeddingRuntime();

  @override
  Future<List<List<double>>> embedSentences(List<String> sentences) async =>
      const [];
}

class _ThrowingSttService extends SttService {
  _ThrowingSttService(this.error) : super(whisperModel: WhisperModel.base);

  final Object error;
  bool disposed = false;

  @override
  Future<void> transcribeFile(String audioPath) async {
    throw error;
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test(
      'BackgroundTranscriptionService rethrows transcription failures after marking lecture failed',
      () async {
    final tempDocsDir =
        await Directory.systemTemp.createTemp('background_transcription_docs_');
    final tempDbDir =
        await Directory.systemTemp.createTemp('background_transcription_db_');
    final audioDir = Directory(
      '${tempDocsDir.path}${Platform.pathSeparator}media${Platform.pathSeparator}audio',
    );
    await audioDir.create(recursive: true);
    final audioFile =
        File('${audioDir.path}${Platform.pathSeparator}audio.wav');
    await audioFile.writeAsBytes(const [1, 2, 3, 4]);

    final dbService = DbService(
      documentsDirectory: () async => tempDocsDir,
      databasePathResolver: () async =>
          '${tempDbDir.path}${Platform.pathSeparator}lecture_vault.db',
    );
    await dbService.resetForTests();

    final sttService = _ThrowingSttService(StateError('plugin failed'));
    final service = BackgroundTranscriptionService(
      dbService: dbService,
      summaryService: const _NoopSummaryService(),
      embeddingService: const _NoopEmbeddingRuntime(),
      sttServiceFactory: (_) => sttService,
    );

    final insertedLecture = Lecture(
      title: 'Transcription Failure',
      date: DateTime.utc(2026, 5, 3).toIso8601String(),
      audioPath: audioFile.path,
      managedAudioPath: 'media/audio/audio.wav',
      durationSeconds: 10,
    );
    final lectureId = await dbService.insertLecture(insertedLecture);
    final lecture = insertedLecture.copyWith(id: lectureId);

    await expectLater(
      service.transcribeLecture(lecture),
      throwsA(isA<StateError>()),
    );

    final persisted = await dbService.getLectureById(lectureId);
    expect(persisted, isNotNull);
    expect(persisted!.transcriptionStatus, LectureProcessingStatus.failed);
    expect(persisted.summaryStatus, LectureProcessingStatus.failed);
    expect(persisted.summary, contains('plugin failed'));
    expect(sttService.disposed, isTrue);

    await dbService.close();
    await tempDocsDir.delete(recursive: true);
    await tempDbDir.delete(recursive: true);
  });
}
