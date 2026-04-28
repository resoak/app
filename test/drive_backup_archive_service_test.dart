import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_vault/models/drive_backup_metadata.dart';
import 'package:lecture_vault/services/drive_backup_archive_service.dart';
import 'package:path/path.dart' as p;

void main() {
  group('DriveBackupArchiveService', () {
    test('packages database, sqlite sidecars, metadata, and managed audio', () async {
      final documentsDir = await Directory.systemTemp.createTemp('drive_backup_docs_');
      final databaseDir = await Directory.systemTemp.createTemp('drive_backup_db_');
      final databaseFile = File(p.join(databaseDir.path, 'lecture_vault.db'));
      final walFile = File('${databaseFile.path}-wal');
      final shmFile = File('${databaseFile.path}-shm');
      final audioFile = File(p.join(documentsDir.path, 'media', 'audio', 'sample.m4a'));

      await databaseFile.writeAsString('db-main');
      await walFile.writeAsString('db-wal');
      await shmFile.writeAsString('db-shm');
      await audioFile.parent.create(recursive: true);
      await audioFile.writeAsBytes(Uint8List.fromList([1, 2, 3, 4]));

      final service = DriveBackupArchiveService(
        documentsDirectory: () async => documentsDir,
        databasePathResolver: () async => databaseFile.path,
        now: () => DateTime.utc(2026, 4, 25, 12, 30),
      );

      final bundle = await service.createBackupArchive();
      final archive = ZipDecoder().decodeBytes(bundle.bytes, verify: true);
      final names = archive.files.where((file) => file.isFile).map((file) => file.name).toList();

      expect(names, contains(DriveBackupMetadata.metadataEntryName));
      expect(names, contains('database/lecture_vault.db'));
      expect(names, contains('database/lecture_vault.db-wal'));
      expect(names, contains('database/lecture_vault.db-shm'));
      expect(names, contains('documents/media/audio/sample.m4a'));
      expect(bundle.metadata.databaseFileCount, 3);
      expect(bundle.metadata.audioFileCount, 1);
      expect(bundle.metadata.createdAt, DateTime.utc(2026, 4, 25, 12, 30));

      await documentsDir.delete(recursive: true);
      await databaseDir.delete(recursive: true);
    });

    test('restores packaged database and managed audio back to disk', () async {
      final sourceDocs = await Directory.systemTemp.createTemp('drive_backup_source_docs_');
      final sourceDbDir = await Directory.systemTemp.createTemp('drive_backup_source_db_');
      final sourceDb = File(p.join(sourceDbDir.path, 'lecture_vault.db'));
      final sourceAudio = File(p.join(sourceDocs.path, 'media', 'audio', 'restore.wav'));

      await sourceDb.writeAsString('source-db');
      await sourceAudio.parent.create(recursive: true);
      await sourceAudio.writeAsBytes(Uint8List.fromList([9, 8, 7]));

      final createService = DriveBackupArchiveService(
        documentsDirectory: () async => sourceDocs,
        databasePathResolver: () async => sourceDb.path,
        now: () => DateTime.utc(2026, 4, 25, 13, 0),
      );
      final bundle = await createService.createBackupArchive();

      final restoreDocs = await Directory.systemTemp.createTemp('drive_backup_restore_docs_');
      final restoreDbDir = await Directory.systemTemp.createTemp('drive_backup_restore_db_');
      final restoreDbPath = p.join(restoreDbDir.path, 'lecture_vault.db');

      final restoreService = DriveBackupArchiveService(
        documentsDirectory: () async => restoreDocs,
        databasePathResolver: () async => restoreDbPath,
        now: () => DateTime.utc(2026, 4, 25, 13, 5),
      );

      final metadata = await restoreService.restoreBackupArchive(bundle.bytes);
      final restoredDb = File(restoreDbPath);
      final restoredAudio = File(p.join(restoreDocs.path, 'media', 'audio', 'restore.wav'));

      expect(await restoredDb.readAsString(), 'source-db');
      expect(await restoredAudio.readAsBytes(), [9, 8, 7]);
      expect(metadata.audioFileCount, 1);

      await sourceDocs.delete(recursive: true);
      await sourceDbDir.delete(recursive: true);
      await restoreDocs.delete(recursive: true);
      await restoreDbDir.delete(recursive: true);
    });
  });
}
