import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_vault/models/drive_backup_metadata.dart';
import 'package:lecture_vault/models/lecture.dart';
import 'package:lecture_vault/services/db_service.dart';
import 'package:lecture_vault/services/drive_backup_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('DriveBackupService local archive', () {
    late Directory tempDocumentsDir;
    late Directory tempBackupDir;
    late Directory tempDatabaseDir;
    late DbService dbService;
    late DriveBackupService backupService;

    setUp(() async {
      tempDocumentsDir =
          await Directory.systemTemp.createTemp('lecture_vault_docs');
      tempBackupDir =
          await Directory.systemTemp.createTemp('lecture_vault_backup');
      tempDatabaseDir =
          await Directory.systemTemp.createTemp('lecture_vault_db');
      final databasePath =
          '${tempDatabaseDir.path}${Platform.pathSeparator}lecture_vault.db';
      dbService = DbService(
        documentsDirectory: () async => tempDocumentsDir,
        databasePathResolver: () async => databasePath,
      );
      await dbService.resetForTests();
      await dbService.insertLecture(
        Lecture(
          title: '備份測試',
          date: '2026.04.25',
          audioPath: '/legacy/audio.wav',
          managedAudioPath: 'media/audio/test.wav',
          transcript: '逐字稿',
          summary: '摘要',
          tag: '一般',
        ),
      );

      final audioDir = await dbService.getManagedAudioDirectory();
      await audioDir.create(recursive: true);
      await File('${audioDir.path}${Platform.pathSeparator}test.wav')
          .writeAsBytes(const [1, 2, 3, 4, 5], flush: true);

      backupService = DriveBackupService(
        dbService: dbService,
        temporaryDirectory: () async => tempBackupDir,
        random: Random(1),
      );
    });

    tearDown(() async {
      await dbService.close();
      if (await tempDocumentsDir.exists()) {
        await tempDocumentsDir.delete(recursive: true);
      }
      if (await tempBackupDir.exists()) {
        await tempBackupDir.delete(recursive: true);
      }
      if (await tempDatabaseDir.exists()) {
        await tempDatabaseDir.delete(recursive: true);
      }
    });

    test('prepareBackupArchive packages database and audio files', () async {
      final prepared = await backupService.prepareBackupArchive();

      expect(await prepared.archiveFile.exists(), isTrue);
      expect(prepared.metadata.databaseFileCount, 1);
      expect(prepared.metadata.audioFileCount, 1);
      expect(prepared.metadata.totalBytes, greaterThan(0));
    });

    test('restoreFromArchive restores files and metadata', () async {
      final prepared = await backupService.prepareBackupArchive();

      final dbFile = await dbService.getDatabaseFile();
      final audioDir = await dbService.getManagedAudioDirectory();
      await dbFile.writeAsString('corrupted', flush: true);
      await File('${audioDir.path}${Platform.pathSeparator}test.wav')
          .writeAsBytes(const [9, 9], flush: true);

      final restored =
          await backupService.restoreFromArchive(prepared.archiveFile);

      expect(restored.metadata.backupFormatVersion,
          DriveBackupMetadata.currentBackupFormatVersion);
      expect(await dbFile.length(), greaterThan(20));
      expect(
        await File('${audioDir.path}${Platform.pathSeparator}test.wav')
            .readAsBytes(),
        equals(const [1, 2, 3, 4, 5]),
      );
    });
  });
}
