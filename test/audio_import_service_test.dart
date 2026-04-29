import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_vault/models/lecture.dart';
import 'package:lecture_vault/services/audio_import_service.dart';
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

    setUp(() async {
      tempDatabaseDir =
          await Directory.systemTemp.createTemp('audio_import_db_test_');
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
    });

    test('copies imported audio into managed storage and creates lecture row',
        () async {
      final tempDir =
          await Directory.systemTemp.createTemp('audio_import_test_');
      final sourceFile =
          File('${tempDir.path}${Platform.pathSeparator}source.mp3');
      await sourceFile.writeAsBytes(List<int>.generate(16, (index) => index));

      final service = AudioImportService(
        dbService: dbService,
        picker: _FakeAudioImportPicker(
          SelectedAudioImport(
              path: sourceFile.path, name: 'linear algebra.mp3'),
        ),
        documentsDirectory: () async => tempDir,
        random: Random(7),
      );

      final lecture = await service.pickAndImportLecture();

      expect(lecture, isNotNull);
      expect(lecture!.id, isNotNull);
      expect(lecture.title, equals('linear algebra'));
      expect(
          lecture.managedAudioPath,
          startsWith(
              'media${Platform.pathSeparator}audio${Platform.pathSeparator}imp_'));
      expect(lecture.managedAudioPath, endsWith('.mp3'));
      expect(lecture.audioPath, startsWith(tempDir.path));
      expect(lecture.audioPath, isNot(sourceFile.path));
      expect(await File(lecture.audioPath).exists(), isTrue);
      expect(await File(lecture.audioPath).readAsBytes(),
          await sourceFile.readAsBytes());
      expect(lecture.transcriptionStatus,
          equals(LectureProcessingStatus.processing));
      expect(lecture.summaryStatus, equals(LectureProcessingStatus.pending));

      final persistedLecture = await dbService.getLectureById(lecture.id!);
      expect(persistedLecture, isNotNull);
      expect(
          persistedLecture!.managedAudioPath, equals(lecture.managedAudioPath));

      await tempDir.delete(recursive: true);
    });

    test('returns null when picker is cancelled', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('audio_import_test_');
      final service = AudioImportService(
        dbService: dbService,
        picker: _FakeAudioImportPicker(null),
        documentsDirectory: () async => tempDir,
      );

      final lecture = await service.pickAndImportLecture();

      expect(lecture, isNull);
      expect(await dbService.getAllLectures(), isEmpty);

      await tempDir.delete(recursive: true);
    });
  });
}
