import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
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
        _documentsDirectory =
            documentsDirectory ?? getApplicationDocumentsDirectory,
        _databasePathResolver = databasePathResolver,
        _now = now ?? DateTime.now;

  static const String _databaseDirectoryName = 'database';
  static const String _documentsDirectoryName = 'documents';
  static const String _managedAudioDirectory = 'media/audio';
  static const String _managedBackgroundDirectory = 'media/backgrounds';
  static const Set<String> _allowedDatabaseFileNames = {
    DbService.databaseName,
    '${DbService.databaseName}-wal',
    '${DbService.databaseName}-shm',
  };

  final DbService _dbService;
  final Future<Directory> Function() _documentsDirectory;
  final Future<String> Function()? _databasePathResolver;
  final DateTime Function() _now;

  Future<DriveBackupArchiveBundle> createBackupArchive() async {
    final documentsDirectory = await _documentsDirectory();
    final databasePath =
        await (_databasePathResolver?.call() ?? _dbService.getDatabasePath());

    // 1. 獲取資料庫中所有合法的管理音檔路徑，用於交叉比對
    final validManagedPaths = (await _dbService.getManagedAudioPaths())
        .map(_normalizeAppRelativePath)
        .toSet();

    final archive = Archive();
    final fileEntries = <_BackupFileEntry>[];

    // 2. 收集資料庫實體檔案
    fileEntries.addAll(await _collectDatabaseEntries(databasePath));

    // 3. 收集物理音檔並過濾孤兒檔案 (Orphan Files)
    final allPhysicalAudioEntries =
        await _collectManagedAudioEntries(documentsDirectory);
    final allPhysicalBackgroundEntries =
        await _collectManagedBackgroundEntries(documentsDirectory);
    final List<_BackupFileEntry> filteredAudioEntries = [];

    for (final entry in allPhysicalAudioEntries) {
      // 從備份路徑還原出 App 內的相對路徑進行比對
      // 備份路徑格式為: documents/media/audio/xxx.wav
      final relativeInApp =
          p.posix.relative(entry.archivePath, from: _documentsDirectoryName);

      if (validManagedPaths
          .contains(_normalizeAppRelativePath(relativeInApp))) {
        filteredAudioEntries.add(entry);
      } else {
        // [自動清理] 發現資料庫中不存在的孤兒檔案，直接刪除以節省空間
        try {
          final orphanFile =
              File(p.join(documentsDirectory.path, relativeInApp));
          if (await orphanFile.exists()) {
            await orphanFile.delete();
            debugPrint('DriveBackup: 已清理孤兒音檔: $relativeInApp');
          }
        } catch (e) {
          debugPrint('DriveBackup: 無法清理孤兒檔案: $e');
        }
      }
    }

    fileEntries.addAll(filteredAudioEntries);
    fileEntries.addAll(allPhysicalBackgroundEntries);

    if (fileEntries
        .where((entry) => entry.archivePath.startsWith(_databaseDirectoryName))
        .isEmpty) {
      throw const DriveBackupException('找不到可備份的資料庫檔案。');
    }

    final totalBytes =
        fileEntries.fold<int>(0, (sum, entry) => sum + entry.bytes.length);
    final audioExtensions = {
      '.wav',
      '.mp3',
      '.m4a',
      '.aac',
      '.flac',
      '.ogg',
      '.opus',
      '.webm'
    };

    final metadata = DriveBackupMetadata(
      backupId: _now().toUtc().toIso8601String(),
      createdAt: _now().toUtc(),
      backupFormatVersion: DriveBackupMetadata.currentBackupFormatVersion,
      databaseFileCount: fileEntries
          .where(
              (entry) => entry.archivePath.startsWith(_databaseDirectoryName))
          .length,
      audioFileCount: filteredAudioEntries.where((entry) {
        final ext = p.extension(entry.archivePath).toLowerCase();
        return audioExtensions.contains(ext);
      }).length,
      totalBytes: totalBytes,
    );

    archive.addFile(
      ArchiveFile.string(
        DriveBackupMetadata.metadataEntryName,
        const JsonEncoder.withIndent('  ').convert(metadata.toJson()),
      ),
    );

    for (final entry in fileEntries) {
      archive.addFile(
          ArchiveFile(entry.archivePath, entry.bytes.length, entry.bytes));
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
    final databasePath =
        await (_databasePathResolver?.call() ?? _dbService.getDatabasePath());
    final databaseDirectory = Directory(p.dirname(databasePath));
    final restorePlan = <_RestoreFileEntry>[];

    DriveBackupMetadata? metadata;
    var restoredMainDatabase = false;

    for (final file in decoded) {
      if (!file.isFile) {
        continue;
      }

      final entryName = file.name;
      final content = _readArchiveFile(file);

      if (entryName == DriveBackupMetadata.metadataEntryName) {
        metadata = DriveBackupMetadata.decode(utf8.decode(content));
        continue;
      }

      if (entryName.startsWith('$_databaseDirectoryName/')) {
        restorePlan.add(
          _buildDatabaseRestoreEntry(
            entryName: entryName,
            content: content,
            databaseDirectory: databaseDirectory,
          ),
        );
        if (entryName == '$_databaseDirectoryName/${DbService.databaseName}') {
          restoredMainDatabase = true;
        }
        continue;
      }

      if (entryName.startsWith('$_documentsDirectoryName/')) {
        restorePlan.add(
          _buildDocumentRestoreEntry(
            entryName: entryName,
            content: content,
            documentsDirectory: documentsDirectory,
          ),
        );
      }
    }

    if (!restoredMainDatabase) {
      throw const DriveBackupException('備份檔缺少資料庫內容，無法還原。');
    }

    await _clearExistingDatabaseFiles(databasePath);
    await _clearManagedAudioDirectory(documentsDirectory);
    await _clearManagedBackgroundDirectory(documentsDirectory);

    for (final entry in restorePlan) {
      await entry.targetFile.parent.create(recursive: true);
      await entry.targetFile.writeAsBytes(entry.bytes, flush: true);
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

  Future<List<_BackupFileEntry>> _collectDatabaseEntries(
      String databasePath) async {
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

  String _normalizeAppRelativePath(String path) {
    return p.posix.normalize(path.trim().replaceAll('\\', '/'));
  }

  Future<List<_BackupFileEntry>> _collectManagedAudioEntries(
      Directory documentsDirectory) async {
    final managedDirectory =
        Directory(p.join(documentsDirectory.path, _managedAudioDirectory));
    if (!await managedDirectory.exists()) {
      return const [];
    }

    final entries = <_BackupFileEntry>[];
    await for (final entity
        in managedDirectory.list(recursive: true, followLinks: false)) {
      if (entity is! File) {
        continue;
      }

      final relativePath =
          p.relative(entity.path, from: documentsDirectory.path);
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

  Future<List<_BackupFileEntry>> _collectManagedBackgroundEntries(
      Directory documentsDirectory) async {
    final managedDirectory =
        Directory(p.join(documentsDirectory.path, _managedBackgroundDirectory));
    if (!await managedDirectory.exists()) {
      return const [];
    }

    final entries = <_BackupFileEntry>[];
    await for (final entity
        in managedDirectory.list(recursive: true, followLinks: false)) {
      if (entity is! File) {
        continue;
      }

      final relativePath =
          p.relative(entity.path, from: documentsDirectory.path);
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

  _RestoreFileEntry _buildDatabaseRestoreEntry({
    required String entryName,
    required Uint8List content,
    required Directory databaseDirectory,
  }) {
    final relativePath = entryName.substring('$_databaseDirectoryName/'.length);
    final normalizedRelativePath = p.posix.normalize(relativePath);
    if (relativePath != normalizedRelativePath ||
        !_isSafeRelativeArchivePath(normalizedRelativePath) ||
        p.posix.basename(normalizedRelativePath) != normalizedRelativePath ||
        !_allowedDatabaseFileNames.contains(normalizedRelativePath)) {
      throw DriveBackupException('備份檔包含不安全的資料庫路徑：$entryName');
    }

    return _RestoreFileEntry(
      targetFile: File(p.join(databaseDirectory.path, normalizedRelativePath)),
      bytes: content,
    );
  }

  _RestoreFileEntry _buildDocumentRestoreEntry({
    required String entryName,
    required Uint8List content,
    required Directory documentsDirectory,
  }) {
    final relativePath =
        entryName.substring('$_documentsDirectoryName/'.length);
    final normalizedRelativePath = p.posix.normalize(relativePath);
    if (relativePath != normalizedRelativePath ||
        !_isSafeRelativeArchivePath(normalizedRelativePath) ||
        !(normalizedRelativePath.startsWith('$_managedAudioDirectory/') ||
            normalizedRelativePath
                .startsWith('$_managedBackgroundDirectory/'))) {
      throw DriveBackupException('備份檔包含不安全的文件路徑：$entryName');
    }

    final targetPath = p.normalize(
      p.join(documentsDirectory.path,
          p.joinAll(p.posix.split(normalizedRelativePath))),
    );
    if (!_isPathWithinRoot(
        rootPath: documentsDirectory.path, candidatePath: targetPath)) {
      throw DriveBackupException('備份檔包含超出文件目錄的路徑：$entryName');
    }

    return _RestoreFileEntry(
      targetFile: File(targetPath),
      bytes: content,
    );
  }

  bool _isSafeRelativeArchivePath(String path) {
    return path.isNotEmpty &&
        path != '.' &&
        !p.posix.isAbsolute(path) &&
        !path.startsWith('../');
  }

  bool _isPathWithinRoot({
    required String rootPath,
    required String candidatePath,
  }) {
    final relativePath = p.relative(candidatePath, from: rootPath);
    return relativePath != '..' && !relativePath.startsWith('..${p.separator}');
  }

  Future<void> _clearExistingDatabaseFiles(String databasePath) async {
    final databaseFiles = <String>[
      databasePath,
      '$databasePath-wal',
      '$databasePath-shm',
    ];

    for (final path in databaseFiles) {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  Future<void> _clearManagedAudioDirectory(Directory documentsDirectory) async {
    final managedAudioDirectory = Directory(
      p.join(documentsDirectory.path, _managedAudioDirectory),
    );
    if (await managedAudioDirectory.exists()) {
      await managedAudioDirectory.delete(recursive: true);
    }
  }

  Future<void> _clearManagedBackgroundDirectory(
      Directory documentsDirectory) async {
    final managedBackgroundDirectory = Directory(
      p.join(documentsDirectory.path, _managedBackgroundDirectory),
    );
    if (await managedBackgroundDirectory.exists()) {
      await managedBackgroundDirectory.delete(recursive: true);
    }
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

class _RestoreFileEntry {
  const _RestoreFileEntry({
    required this.targetFile,
    required this.bytes,
  });

  final File targetFile;
  final Uint8List bytes;
}
