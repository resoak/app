import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_vault/models/lecture.dart';
import 'package:lecture_vault/services/audio_import_service.dart';
import 'package:lecture_vault/services/audio_transcoding_service.dart';
import 'package:lecture_vault/services/db_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakeAudioImportPicker implements AudioImportPicker {
  _FakeAudioImportPicker(this.selection);

  final SelectedAudioImport? selection;

  @override
  Future<SelectedAudioImport?> pickAudioFile() async => selection;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('AudioImportService', () {
    late DbService dbService;
    late Directory tempDatabaseDir;
    late Directory tempDocumentsDir;

    setUp(() async {
      tempDatabaseDir =
          await Directory.systemTemp.createTemp('audio_import_db_test_');
      tempDocumentsDir =
          await Directory.systemTemp.createTemp('audio_import_docs_test_');
      final databasePath =
          '${tempDatabaseDir.path}${Platform.pathSeparator}lecture_vault.db';
      dbService = DbService(
        databasePathResolver: () async => databasePath,
      );
      await dbService.resetForTests();
    });

    tearDown(() async {
      await dbService.close();
      if (await tempDatabaseDir.exists()) {
        await tempDatabaseDir.delete(recursive: true);
      }
      if (await tempDocumentsDir.exists()) {
        await tempDocumentsDir.delete(recursive: true);
      }
    });

    test(
        'converts imported audio into managed wav storage and creates lecture row',
        () async {
      final tempDir =
          await Directory.systemTemp.createTemp('audio_import_test_');
      final sourceFile =
          File('${tempDir.path}${Platform.pathSeparator}source.mp3');
      await sourceFile.writeAsBytes(List<int>.generate(16, (index) => index));
      final convertedBytes = List<int>.generate(32, (index) => 255 - index);

      final service = AudioImportService(
        dbService: dbService,
        picker: _FakeAudioImportPicker(
          SelectedAudioImport(
              path: sourceFile.path, name: 'linear algebra.mp3'),
        ),
        documentsDirectoryProvider: () async => tempDocumentsDir,
        transcodingService: AudioTranscodingService(
          probeDuration: (_) async => 42,
          convertToWhisperWav: ({
            required String sourcePath,
            required String destinationPath,
          }) async {
            expect(sourcePath, sourceFile.path);
            final outputFile = File(destinationPath);
            await outputFile.parent.create(recursive: true);
            await outputFile.writeAsBytes(convertedBytes);
          },
        ),
      );

      final lecture = await service.pickAndImportLecture();

      expect(lecture, isNotNull);
      expect(lecture!.id, isNotNull);
      expect(lecture.title, equals('linear algebra'));
      expect(
          lecture.managedAudioPath,
          startsWith(
              'media${Platform.pathSeparator}audio${Platform.pathSeparator}imp_'));
      expect(lecture.managedAudioPath, endsWith('.wav'));
      expect(lecture.audioPath, startsWith(tempDocumentsDir.path));
      expect(lecture.audioPath, isNot(sourceFile.path));
      expect(await File(lecture.audioPath).exists(), isTrue);
      expect(await File(lecture.audioPath).readAsBytes(), convertedBytes);
      expect(
          lecture.transcriptionStatus, equals(LectureProcessingStatus.pending));
      expect(lecture.summaryStatus, equals(LectureProcessingStatus.pending));
      expect(lecture.durationSeconds, equals(42));

      final persistedLecture = await dbService.getLectureById(lecture.id!);
      expect(persistedLecture, isNotNull);
      expect(
          persistedLecture!.managedAudioPath, equals(lecture.managedAudioPath));

      await tempDir.delete(recursive: true);
    });

    test('surfaces conversion failures without creating a lecture row',
        () async {
      final tempDir =
          await Directory.systemTemp.createTemp('audio_import_failure_test_');
      final sourceFile =
          File('${tempDir.path}${Platform.pathSeparator}source.mp3');
      await sourceFile.writeAsBytes(List<int>.generate(16, (index) => index));

      final service = AudioImportService(
        dbService: dbService,
        picker: _FakeAudioImportPicker(
          SelectedAudioImport(path: sourceFile.path, name: 'failure.mp3'),
        ),
        documentsDirectoryProvider: () async => tempDocumentsDir,
        transcodingService: AudioTranscodingService(
          probeDuration: (_) async => 0,
          convertToWhisperWav: ({
            required String sourcePath,
            required String destinationPath,
          }) async {
            throw const AudioTranscodingException('轉檔失敗');
          },
        ),
      );

      await expectLater(
        service.pickAndImportLecture(),
        throwsA(
          isA<AudioTranscodingException>().having(
            (error) => error.message,
            'message',
            '轉檔失敗',
          ),
        ),
      );
      expect(await dbService.getAllLectures(), isEmpty);

      await tempDir.delete(recursive: true);
    });

    test('cleans converted wav when lecture insert fails', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('audio_import_insert_fail_');
      final sourceFile =
          File('${tempDir.path}${Platform.pathSeparator}source.mp3');
      await sourceFile.writeAsBytes(List<int>.generate(16, (index) => index));

      late String writtenDestinationPath;

      final service = AudioImportService(
        dbService: dbService,
        picker: _FakeAudioImportPicker(
          SelectedAudioImport(path: sourceFile.path, name: 'failure.mp3'),
        ),
        documentsDirectoryProvider: () async => tempDocumentsDir,
        transcodingService: AudioTranscodingService(
          probeDuration: (_) async => 3,
          convertToWhisperWav: ({
            required String sourcePath,
            required String destinationPath,
          }) async {
            writtenDestinationPath = destinationPath;
            final outputFile = File(destinationPath);
            await outputFile.parent.create(recursive: true);
            await outputFile.writeAsBytes(const [1, 2, 3, 4]);
          },
        ),
        lectureInserter: (_) async {
          throw StateError('db insert failed');
        },
      );

      await expectLater(
        service.pickAndImportLecture(),
        throwsA(isA<StateError>()),
      );
      expect(await File(writtenDestinationPath).exists(), isFalse);
      expect(await dbService.getAllLectures(), isEmpty);

      await tempDir.delete(recursive: true);
    });

    test('returns null when picker is cancelled', () async {
      final service = AudioImportService(
        dbService: dbService,
        picker: _FakeAudioImportPicker(null),
      );

      final lecture = await service.pickAndImportLecture();

      expect(lecture, isNull);
      expect(await dbService.getAllLectures(), isEmpty);
    });
  });
}
