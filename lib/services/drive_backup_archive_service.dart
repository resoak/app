import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/drive_backup_metadata.dart';
import 'db_service.dart';
import 'google_drive_auth_service.dart';

class DriveBackupArchiveBundle {
  const DriveBackupArchiveBundle({
    required this.bytes,
    required this.metadata,
  });

  final Uint8List bytes;
  final DriveBackupMetadata metadata;
}

class DriveBackupArchiveService {
  DriveBackupArchiveService({
    DbService? dbService,
    Future<Directory> Function()? documentsDirectory,
    Future<String> Function()? databasePathResolver,
    DateTime Function()? now,
  })  : _dbService = dbService ?? DbService(),
        _documentsDirectory = documentsDirectory ?? getApplicationDocumentsDirectory,
        _databasePathResolver = databasePathResolver,
        _now = now ?? DateTime.now;

  static const String _databaseDirectoryName = 'database';
  static const String _documentsDirectoryName = 'documents';
  static const String _managedAudioDirectory = 'media/audio';

  final DbService _dbService;
  final Future<Directory> Function() _documentsDirectory;
  final Future<String> Function()? _databasePathResolver;
  final DateTime Function() _now;

  Future<DriveBackupArchiveBundle> createBackupArchive() async {
    final documentsDirectory = await _documentsDirectory();
    final databasePath = await (_databasePathResolver?.call() ?? _dbService.getDatabasePath());
    final archive = Archive();
    final fileEntries = <_BackupFileEntry>[];

    fileEntries.addAll(await _collectDatabaseEntries(databasePath));
    fileEntries.addAll(await _collectManagedAudioEntries(documentsDirectory));

    if (fileEntries.where((entry) => entry.archivePath.startsWith(_databaseDirectoryName)).isEmpty) {
      throw const DriveBackupException('找不到可備份的資料庫檔案。');
    }

    final totalBytes = fileEntries.fold<int>(0, (sum, entry) => sum + entry.bytes.length);
    final metadata = DriveBackupMetadata(
      backupId: _now().toUtc().toIso8601String(),
      createdAt: _now().toUtc(),
      backupFormatVersion: DriveBackupMetadata.currentBackupFormatVersion,
      databaseFileCount: fileEntries
          .where((entry) => entry.archivePath.startsWith(_databaseDirectoryName))
          .length,
      audioFileCount: fileEntries
          .where((entry) => entry.archivePath.startsWith('$_documentsDirectoryName/$_managedAudioDirectory'))
          .length,
      totalBytes: totalBytes,
    );

    archive.addFile(
      ArchiveFile.string(
        DriveBackupMetadata.metadataEntryName,
        const JsonEncoder.withIndent('  ').convert(metadata.toJson()),
      ),
    );

    for (final entry in fileEntries) {
      archive.addFile(ArchiveFile(entry.archivePath, entry.bytes.length, entry.bytes));
    }

    final encoder = ZipEncoder();
    final encoded = encoder.encode(archive);
    if (encoded == null) {
      throw const DriveBackupException('無法建立本機備份封存檔。');
    }

    return DriveBackupArchiveBundle(
      bytes: Uint8List.fromList(encoded),
      metadata: metadata,
    );
  }

  Future<DriveBackupMetadata> restoreBackupArchive(Uint8List bytes) async {
    final decoded = ZipDecoder().decodeBytes(bytes, verify: true);
    final documentsDirectory = await _documentsDirectory();
    final databasePath = await (_databasePathResolver?.call() ?? _dbService.getDatabasePath());
    final databaseDirectory = Directory(p.dirname(databasePath));

    DriveBackupMetadata? metadata;
    var restoredDatabase = false;

    for (final file in decoded) {
      if (!file.isFile) {
        continue;
      }

      final entryName = p.posix.normalize(file.name);
      final content = _readArchiveFile(file);

      if (entryName == DriveBackupMetadata.metadataEntryName) {
        metadata = DriveBackupMetadata.decode(utf8.decode(content));
        continue;
      }

      if (entryName.startsWith('$_databaseDirectoryName/')) {
        final targetName = p.posix.basename(entryName);
        final targetFile = File(p.join(databaseDirectory.path, targetName));
        await targetFile.parent.create(recursive: true);
        await targetFile.writeAsBytes(content, flush: true);
        restoredDatabase = true;
        continue;
      }

      if (entryName.startsWith('$_documentsDirectoryName/')) {
        final relativeTargetPath = entryName.substring('$_documentsDirectoryName/'.length);
        final targetFile = File(p.join(documentsDirectory.path, p.normalize(relativeTargetPath)));
        await targetFile.parent.create(recursive: true);
        await targetFile.writeAsBytes(content, flush: true);
      }
    }

    if (!restoredDatabase) {
      throw const DriveBackupException('備份檔缺少資料庫內容，無法還原。');
    }

    return metadata ??
        DriveBackupMetadata(
          backupId: _now().toUtc().toIso8601String(),
          createdAt: _now().toUtc(),
          backupFormatVersion: DriveBackupMetadata.currentBackupFormatVersion,
          databaseFileCount: 1,
          audioFileCount: 0,
          totalBytes: bytes.length,
        );
  }

  Future<List<_BackupFileEntry>> _collectDatabaseEntries(String databasePath) async {
    final paths = <String>[
      databasePath,
      '$databasePath-wal',
      '$databasePath-shm',
    ];

    final entries = <_BackupFileEntry>[];
    for (final path in paths) {
      final file = File(path);
      if (!await file.exists()) {
        continue;
      }

      entries.add(
        _BackupFileEntry(
          archivePath: p.posix.join(_databaseDirectoryName, p.basename(path)),
          bytes: await file.readAsBytes(),
        ),
      );
    }
    return entries;
  }

  Future<List<_BackupFileEntry>> _collectManagedAudioEntries(Directory documentsDirectory) async {
    final managedDirectory = Directory(p.join(documentsDirectory.path, _managedAudioDirectory));
    if (!await managedDirectory.exists()) {
      return const [];
    }

    final entries = <_BackupFileEntry>[];
    await for (final entity in managedDirectory.list(recursive: true, followLinks: false)) {
      if (entity is! File) {
        continue;
      }

      final relativePath = p.relative(entity.path, from: documentsDirectory.path);
      entries.add(
        _BackupFileEntry(
          archivePath: p.posix.joinAll([
            _documentsDirectoryName,
            ...p.split(relativePath),
          ]),
          bytes: await entity.readAsBytes(),
        ),
      );
    }

    return entries;
  }

  Uint8List _readArchiveFile(ArchiveFile file) {
    final content = file.content;
    if (content is Uint8List) {
      return content;
    }
    if (content is List<int>) {
      return Uint8List.fromList(content);
    }
    throw const DriveBackupException('備份檔內容格式無法讀取。');
  }
}

class _BackupFileEntry {
  const _BackupFileEntry({
    required this.archivePath,
    required this.bytes,
  });

  final String archivePath;
  final Uint8List bytes;
}
