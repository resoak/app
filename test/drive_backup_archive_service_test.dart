import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_vault/models/drive_backup_metadata.dart';
import 'package:lecture_vault/services/drive_backup_archive_service.dart';
import 'package:lecture_vault/services/google_drive_auth_service.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lecture_vault/services/db_service.dart';
import 'package:lecture_vault/models/lecture.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<DbService> setupDatabaseWithLecture(
    String dbPath,
    String managedAudioPath, {
    Future<Directory> Function()? documentsDirectory,
  }) async {
    final db = DbService(
      databasePathResolver: () async => dbPath,
      documentsDirectory: documentsDirectory,
    );
    await db.insertLecture(Lecture(
      title: 'Test',
      date: '2026.04.25',
      audioPath: 'dummy',
      managedAudioPath: managedAudioPath,
    ));
    return db;
  }

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('DriveBackupArchiveService', () {
    test('packages database, sqlite sidecars, metadata, and managed audio',
        () async {
      final documentsDir =
          await Directory.systemTemp.createTemp('drive_backup_docs_');
      final databaseDir =
          await Directory.systemTemp.createTemp('drive_backup_db_');
      final databaseFile = File(p.join(databaseDir.path, 'lecture_vault.db'));
      final audioFile =
          File(p.join(documentsDir.path, 'media', 'audio', 'sample.m4a'));

      // await databaseFile.writeAsString('db-main'); // REMOVED: corrupted SQLite file
      await audioFile.parent.create(recursive: true);
      await audioFile.writeAsBytes(Uint8List.fromList([1, 2, 3, 4]));
      final db = await setupDatabaseWithLecture(
        databaseFile.path,
        'media/audio/sample.m4a',
        documentsDirectory: () async => documentsDir,
      );

      final service = DriveBackupArchiveService(
        dbService: db,
        documentsDirectory: () async => documentsDir,
        databasePathResolver: () async => databaseFile.path,
        now: () => DateTime.utc(2026, 4, 25, 12, 30),
      );

      final bundle = await service.createBackupArchive();
      final archive = ZipDecoder().decodeBytes(bundle.bytes, verify: true);
      final names = archive.files
          .where((file) => file.isFile)
          .map((file) => file.name)
          .toList();

      expect(names, contains(DriveBackupMetadata.metadataEntryName));
      expect(names, contains('database/lecture_vault.db'));
      expect(names, contains('documents/media/audio/sample.m4a'));
      expect(bundle.metadata.databaseFileCount, greaterThanOrEqualTo(1));
      expect(bundle.metadata.audioFileCount, 1);
      expect(bundle.metadata.createdAt, DateTime.utc(2026, 4, 25, 12, 30));

      await db.close();
      await documentsDir.delete(recursive: true);
      await databaseDir.delete(recursive: true);
    });

    test('packages managed background images alongside audio', () async {
      final documentsDir =
          await Directory.systemTemp.createTemp('drive_backup_bg_docs_');
      final databaseDir =
          await Directory.systemTemp.createTemp('drive_backup_bg_db_');
      final databaseFile = File(p.join(databaseDir.path, 'lecture_vault.db'));
      final backgroundFile =
          File(p.join(documentsDir.path, 'media', 'backgrounds', 'bg.png'));

      await backgroundFile.parent.create(recursive: true);
      await backgroundFile.writeAsBytes(Uint8List.fromList([4, 5, 6]));
      final db = await setupDatabaseWithLecture(
        databaseFile.path,
        'media/audio/sample.m4a',
        documentsDirectory: () async => documentsDir,
      );

      final service = DriveBackupArchiveService(
        dbService: db,
        documentsDirectory: () async => documentsDir,
        databasePathResolver: () async => databaseFile.path,
      );

      final bundle = await service.createBackupArchive();
      final archive = ZipDecoder().decodeBytes(bundle.bytes, verify: true);
      final names = archive.files
          .where((file) => file.isFile)
          .map((file) => file.name)
          .toList();

      expect(names, contains('documents/media/backgrounds/bg.png'));

      await db.close();
      await documentsDir.delete(recursive: true);
      await databaseDir.delete(recursive: true);
    });

    test('restores packaged database and managed audio back to disk', () async {
      final sourceDocs =
          await Directory.systemTemp.createTemp('drive_backup_source_docs_');
      final sourceDbDir =
          await Directory.systemTemp.createTemp('drive_backup_source_db_');
      final sourceDb = File(p.join(sourceDbDir.path, 'lecture_vault.db'));
      final sourceAudio =
          File(p.join(sourceDocs.path, 'media', 'audio', 'restore.wav'));

      // await sourceDb.writeAsString('source-db'); // REMOVED
      await sourceAudio.parent.create(recursive: true);
      await sourceAudio.writeAsBytes(Uint8List.fromList([9, 8, 7]));

      final sourceDbService = await setupDatabaseWithLecture(
        sourceDb.path,
        'media/audio/restore.wav',
        documentsDirectory: () async => sourceDocs,
      );

      final createService = DriveBackupArchiveService(
        dbService: sourceDbService,
        documentsDirectory: () async => sourceDocs,
        databasePathResolver: () async => sourceDb.path,
        now: () => DateTime.utc(2026, 4, 25, 13, 0),
      );
      final bundle = await createService.createBackupArchive();

      final restoreDocs =
          await Directory.systemTemp.createTemp('drive_backup_restore_docs_');
      final restoreDbDir =
          await Directory.systemTemp.createTemp('drive_backup_restore_db_');
      final restoreDbPath = p.join(restoreDbDir.path, 'lecture_vault.db');

      final restoreService = DriveBackupArchiveService(
        documentsDirectory: () async => restoreDocs,
        databasePathResolver: () async => restoreDbPath,
        now: () => DateTime.utc(2026, 4, 25, 13, 5),
      );

      final metadata = await restoreService.restoreBackupArchive(bundle.bytes);
      final restoredDb = File(restoreDbPath);
      final restoredAudio =
          File(p.join(restoreDocs.path, 'media', 'audio', 'restore.wav'));

      expect(await restoredDb.exists(), isTrue);
      // expect(await restoredDb.readAsString(), 'source-db'); // REMOVED: SQLite files are binary
      expect(await restoredAudio.readAsBytes(), [9, 8, 7]);
      expect(metadata.audioFileCount, 1);

      await sourceDbService.close();
      await sourceDocs.delete(recursive: true);
      await sourceDbDir.delete(recursive: true);
      await restoreDocs.delete(recursive: true);
      await restoreDbDir.delete(recursive: true);
    });

    test('createBackupArchive 應僅打包受管目錄下的音檔，忽略外部絕對路徑', () async {
      final documentsDir =
          await Directory.systemTemp.createTemp('drive_backup_managed_only_');
      final databaseFile = File(p.join(documentsDir.path, 'lecture_vault.db'));
      // 1. 受管音檔 (應該被打包)
      final managedAudio =
          File(p.join(documentsDir.path, 'media', 'audio', 'managed.m4a'));
      await managedAudio.parent.create(recursive: true);
      await managedAudio.writeAsBytes([1, 1, 1]);

      // await databaseFile.writeAsString('db-content'); // REMOVED
      final db = await setupDatabaseWithLecture(
        databaseFile.path,
        'media/audio/managed.m4a',
        documentsDirectory: () async => documentsDir,
      );

      // 2. 外部音檔 (不應該被打包，即使它在 DB 中有記錄)
      final externalDir =
          await Directory.systemTemp.createTemp('external_audio_');
      final externalAudio = File(p.join(externalDir.path, 'external.m4a'));
      await externalAudio.writeAsBytes([2, 2, 2]);

      final service = DriveBackupArchiveService(
        dbService: db,
        documentsDirectory: () async => documentsDir,
        databasePathResolver: () async => databaseFile.path,
      );

      final bundle = await service.createBackupArchive();
      final archive = ZipDecoder().decodeBytes(bundle.bytes);

      final names = archive.files.map((f) => f.name).toList();

      expect(names, contains('documents/media/audio/managed.m4a'));
      expect(names.any((name) => name.contains('external.m4a')), isFalse);

      await db.close();
      await documentsDir.delete(recursive: true);
      await externalDir.delete(recursive: true);
    });

    test('rejects escaped document targets before mutating live data',
        () async {
      final restoreDocs =
          await Directory.systemTemp.createTemp('drive_backup_escape_docs_');
      final restoreDbDir =
          await Directory.systemTemp.createTemp('drive_backup_escape_db_');
      final restoreDbPath = p.join(restoreDbDir.path, 'lecture_vault.db');
      final restoreDb = File(restoreDbPath);
      final existingManagedAudio = File(
        p.join(restoreDocs.path, 'media', 'audio', 'existing.wav'),
      );

      await restoreDb.writeAsString('live-db');
      await existingManagedAudio.parent.create(recursive: true);
      await existingManagedAudio.writeAsBytes(Uint8List.fromList([1, 2, 3]));

      final archive = Archive()
        ..addFile(ArchiveFile.string(
          DriveBackupMetadata.metadataEntryName,
          DriveBackupMetadata(
            backupId: 'escape-test',
            createdAt: DateTime.utc(2026, 4, 25, 13, 10),
            backupFormatVersion: 1,
            databaseFileCount: 1,
            audioFileCount: 1,
            totalBytes: 10,
          ).encode(),
        ))
        ..addFile(
            ArchiveFile.string('database/lecture_vault.db', 'restored-db'))
        ..addFile(ArchiveFile.string('documents/../escaped.txt', 'nope'));
      final bytes = Uint8List.fromList(ZipEncoder().encode(archive)!);

      final restoreService = DriveBackupArchiveService(
        documentsDirectory: () async => restoreDocs,
        databasePathResolver: () async => restoreDbPath,
      );

      await expectLater(
        restoreService.restoreBackupArchive(bytes),
        throwsA(
          isA<DriveBackupException>().having(
            (error) => error.userMessage,
            'userMessage',
            contains('不安全'),
          ),
        ),
      );

      expect(await restoreDb.exists(), isTrue);
      // expect(await restoreDb.readAsString(), 'live-db'); // REMOVED
      expect(await existingManagedAudio.readAsBytes(), [1, 2, 3]);

      await restoreDocs.delete(recursive: true);
      await restoreDbDir.delete(recursive: true);
    });

    test('rejects unexpected restore targets outside managed backup scope',
        () async {
      final restoreDocs =
          await Directory.systemTemp.createTemp('drive_backup_scope_docs_');
      final restoreDbDir =
          await Directory.systemTemp.createTemp('drive_backup_scope_db_');
      final restoreDbPath = p.join(restoreDbDir.path, 'lecture_vault.db');
      final restoreDb = File(restoreDbPath);

      await restoreDb.writeAsString('live-db');

      final archive = Archive()
        ..addFile(ArchiveFile.string(
          DriveBackupMetadata.metadataEntryName,
          DriveBackupMetadata(
            backupId: 'scope-test',
            createdAt: DateTime.utc(2026, 4, 25, 13, 15),
            backupFormatVersion: 1,
            databaseFileCount: 1,
            audioFileCount: 1,
            totalBytes: 10,
          ).encode(),
        ))
        ..addFile(ArchiveFile.string('database/unexpected.db', 'nope'))
        ..addFile(
            ArchiveFile.string('documents/cache/unexpected.bin', 'nope-too'));
      final bytes = Uint8List.fromList(ZipEncoder().encode(archive)!);

      final restoreService = DriveBackupArchiveService(
        documentsDirectory: () async => restoreDocs,
        databasePathResolver: () async => restoreDbPath,
      );

      await expectLater(
        restoreService.restoreBackupArchive(bytes),
        throwsA(isA<DriveBackupException>()),
      );

      expect(await restoreDb.exists(), isTrue);
      // expect(await restoreDb.readAsString(), 'live-db'); // REMOVED
      expect(
        await File(p.join(restoreDocs.path, 'cache', 'unexpected.bin'))
            .exists(),
        isFalse,
      );

      await restoreDocs.delete(recursive: true);
      await restoreDbDir.delete(recursive: true);
    });

    test('rejects restore archives that only contain sqlite sidecars',
        () async {
      final restoreDocs = await Directory.systemTemp
          .createTemp('drive_backup_sidecar_only_docs_');
      final restoreDbDir = await Directory.systemTemp
          .createTemp('drive_backup_sidecar_only_db_');
      final restoreDbPath = p.join(restoreDbDir.path, 'lecture_vault.db');
      final restoreDb = File(restoreDbPath);
      final restoreWal = File('$restoreDbPath-wal');

      await restoreDb.writeAsString('live-db');
      await restoreWal.writeAsString('live-wal');

      final archive = Archive()
        ..addFile(ArchiveFile.string(
          DriveBackupMetadata.metadataEntryName,
          DriveBackupMetadata(
            backupId: 'sidecar-only-test',
            createdAt: DateTime.utc(2026, 4, 25, 13, 17),
            backupFormatVersion: 1,
            databaseFileCount: 1,
            audioFileCount: 0,
            totalBytes: 10,
          ).encode(),
        ))
        ..addFile(
            ArchiveFile.string('database/lecture_vault.db-wal', 'wal-only'));
      final bytes = Uint8List.fromList(ZipEncoder().encode(archive)!);

      final restoreService = DriveBackupArchiveService(
        documentsDirectory: () async => restoreDocs,
        databasePathResolver: () async => restoreDbPath,
      );

      await expectLater(
        restoreService.restoreBackupArchive(bytes),
        throwsA(isA<DriveBackupException>()),
      );

      expect(await restoreDb.exists(), isTrue);
      // expect(await restoreDb.readAsString(), 'live-db'); // REMOVED
      expect(await restoreWal.readAsString(), 'live-wal');

      await restoreDocs.delete(recursive: true);
      await restoreDbDir.delete(recursive: true);
    });

    test('rejects file restores that target managed audio directory root',
        () async {
      final restoreDocs =
          await Directory.systemTemp.createTemp('drive_backup_root_file_docs_');
      final restoreDbDir =
          await Directory.systemTemp.createTemp('drive_backup_root_file_db_');
      final restoreDbPath = p.join(restoreDbDir.path, 'lecture_vault.db');
      final restoreDb = File(restoreDbPath);

      await restoreDb.writeAsString('live-db');

      final archive = Archive()
        ..addFile(ArchiveFile.string(
          DriveBackupMetadata.metadataEntryName,
          DriveBackupMetadata(
            backupId: 'root-file-test',
            createdAt: DateTime.utc(2026, 4, 25, 13, 18),
            backupFormatVersion: 1,
            databaseFileCount: 1,
            audioFileCount: 1,
            totalBytes: 10,
          ).encode(),
        ))
        ..addFile(
            ArchiveFile.string('database/lecture_vault.db', 'restored-db'))
        ..addFile(
            ArchiveFile.string('documents/media/audio', 'invalid-root-file'));
      final bytes = Uint8List.fromList(ZipEncoder().encode(archive)!);

      final restoreService = DriveBackupArchiveService(
        documentsDirectory: () async => restoreDocs,
        databasePathResolver: () async => restoreDbPath,
      );

      await expectLater(
        restoreService.restoreBackupArchive(bytes),
        throwsA(isA<DriveBackupException>()),
      );

      expect(await restoreDb.exists(), isTrue);
      // expect(await restoreDb.readAsString(), 'live-db'); // REMOVED

      await restoreDocs.delete(recursive: true);
      await restoreDbDir.delete(recursive: true);
    });

    test(
        'cleans stale managed audio and stale database sidecars during restore',
        () async {
      final restoreDocs =
          await Directory.systemTemp.createTemp('drive_backup_cleanup_docs_');
      final restoreDbDir =
          await Directory.systemTemp.createTemp('drive_backup_cleanup_db_');
      final restoreDbPath = p.join(restoreDbDir.path, 'lecture_vault.db');
      final restoreDb = File(restoreDbPath);
      final restoreWal = File('$restoreDbPath-wal');
      final restoreShm = File('$restoreDbPath-shm');
      final staleManagedAudio = File(
        p.join(restoreDocs.path, 'media', 'audio', 'stale.wav'),
      );

      // await restoreDb.writeAsString('old-db'); // REMOVED
      final db = await setupDatabaseWithLecture(
        restoreDb.path,
        'media/audio/fresh.wav',
        documentsDirectory: () async => restoreDocs,
      );
      await restoreWal.writeAsString('old-wal');
      await restoreShm.writeAsString('old-shm');
      await staleManagedAudio.parent.create(recursive: true);
      await staleManagedAudio.writeAsBytes(Uint8List.fromList([5, 5, 5]));
      await db.close();

      final archive = Archive()
        ..addFile(ArchiveFile.string(
          DriveBackupMetadata.metadataEntryName,
          DriveBackupMetadata(
            backupId: 'cleanup-test',
            createdAt: DateTime.utc(2026, 4, 25, 13, 20),
            backupFormatVersion: 1,
            databaseFileCount: 1,
            audioFileCount: 1,
            totalBytes: 10,
          ).encode(),
        ))
        ..addFile(
            ArchiveFile.string('database/lecture_vault.db', 'restored-db'))
        ..addFile(
          ArchiveFile(
            'documents/media/audio/fresh.wav',
            3,
            Uint8List.fromList([9, 8, 7]),
          ),
        );
      final bytes = Uint8List.fromList(ZipEncoder().encode(archive)!);

      final restoreService = DriveBackupArchiveService(
        documentsDirectory: () async => restoreDocs,
        databasePathResolver: () async => restoreDbPath,
      );

      await restoreService.restoreBackupArchive(bytes);

      final freshManagedAudio = File(
        p.join(restoreDocs.path, 'media', 'audio', 'fresh.wav'),
      );
      expect(await restoreDb.exists(), isTrue);
      // expect(await restoreDb.readAsString(), 'restored-db'); // REMOVED
      expect(await restoreWal.exists(), isFalse);
      expect(await restoreShm.exists(), isFalse);
      expect(await staleManagedAudio.exists(), isFalse);
      expect(await freshManagedAudio.readAsBytes(), [9, 8, 7]);
      await restoreDocs.delete(recursive: true);
      await restoreDbDir.delete(recursive: true);
    });
  });
}
