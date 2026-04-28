import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive_io.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/drive_backup_metadata.dart';
import 'db_service.dart';
import 'google_auth_service.dart';

class DriveBackupException implements Exception {
  const DriveBackupException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PreparedDriveBackup {
  const PreparedDriveBackup({
    required this.archiveFile,
    required this.metadata,
  });

  final File archiveFile;
  final DriveBackupMetadata metadata;
}

class RestoredDriveBackup {
  const RestoredDriveBackup({
    required this.metadata,
    required this.archiveFile,
  });

  final DriveBackupMetadata metadata;
  final File archiveFile;
}

class DriveBackupService {
  DriveBackupService({
    DbService? dbService,
    GoogleAuthService? authService,
    Future<Directory> Function()? temporaryDirectory,
    Random? random,
  })  : _dbService = dbService ?? DbService(),
        _authService = authService ?? GoogleAuthService(),
        _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory,
        _random = random ?? Random.secure();

  static const String backupFileName =
      DriveBackupMetadata.archiveFileNameDefault;
  static const String _databaseEntryPath = 'database/lecture_vault.db';
  static const String _audioEntryRoot = 'media/audio';
  static const String _appPropertyBackupType = 'backupType';
  static const String _appPropertyCreatedAt = 'createdAt';
  static const String _appPropertyAudioFileCount = 'audioFileCount';
  static const String _appPropertyDatabaseFileCount = 'databaseFileCount';
  static const String _appPropertyFormatVersion = 'backupFormatVersion';
  static const String _appPropertyTotalBytes = 'totalBytes';
  static const String _backupTypeValue = 'lecture_vault_latest';

  final DbService _dbService;
  final GoogleAuthService _authService;
  final Future<Directory> Function() _temporaryDirectory;
  final Random _random;

  Future<PreparedDriveBackup> prepareBackupArchive() async {
    final tempDir = await _temporaryDirectory();
    await tempDir.create(recursive: true);

    final dbFile = await _dbService.getDatabaseFile();
    if (!await dbFile.exists()) {
      throw const DriveBackupException('找不到本機資料庫，無法建立備份。');
    }

    await _dbService.close();

    final archivePath = p.join(
      tempDir.path,
      'lecture_vault_backup_${DateTime.now().millisecondsSinceEpoch}_${_randomSuffix()}.zip',
    );
    final encoder = ZipFileEncoder()..create(archivePath);

    var audioFileCount = 0;
    var totalBytes = dbFile.lengthSync();

    await encoder.addFile(dbFile, _databaseEntryPath);

    final audioDirectory = await _dbService.getManagedAudioDirectory();
    if (await audioDirectory.exists()) {
      await for (final entity in audioDirectory.list(recursive: true)) {
        if (entity is! File) {
          continue;
        }

        final relativePath = p.relative(entity.path, from: audioDirectory.path);
        await encoder.addFile(
          entity,
          p.join(_audioEntryRoot, relativePath).replaceAll('\\', '/'),
        );
        audioFileCount += 1;
        totalBytes += await entity.length();
      }
    }

    final metadata = DriveBackupMetadata(
      backupId:
          'drv_${DateTime.now().microsecondsSinceEpoch}_${_randomSuffix()}',
      createdAt: DateTime.now().toUtc(),
      backupFormatVersion: DriveBackupMetadata.currentBackupFormatVersion,
      databaseFileCount: 1,
      audioFileCount: audioFileCount,
      totalBytes: totalBytes,
    );

    encoder.addArchiveFile(
      ArchiveFile.string(
        DriveBackupMetadata.metadataEntryName,
        metadata.encode(),
      ),
    );
    await encoder.close();

    return PreparedDriveBackup(
      archiveFile: File(archivePath),
      metadata: metadata,
    );
  }

  Future<DriveBackupMetadata?> fetchLatestBackupMetadata() async {
    final api = await _authService.getAuthorizedDriveApi();
    final response = await api.files.list(
      spaces: 'appDataFolder',
      q: "name = '$backupFileName' and trashed = false",
      $fields: 'files(id,name,modifiedTime,size,appProperties),nextPageToken',
      orderBy: 'modifiedTime desc',
      pageSize: 1,
    );

    final remoteFile =
        response.files?.isNotEmpty == true ? response.files!.first : null;
    if (remoteFile == null) {
      return null;
    }

    return _metadataFromDriveFile(remoteFile);
  }

  Future<DriveBackupMetadata> uploadLatestBackup() async {
    final prepared = await prepareBackupArchive();
    try {
      final api =
          await _authService.getAuthorizedDriveApi(interactiveIfNeeded: true);
      final existing = await api.files.list(
        spaces: 'appDataFolder',
        q: "name = '$backupFileName' and trashed = false",
        $fields: 'files(id,name,modifiedTime,size,appProperties)',
        orderBy: 'modifiedTime desc',
        pageSize: 1,
      );

      final metadata = drive.File()
        ..name = backupFileName
        ..parents = ['appDataFolder']
        ..appProperties = _buildDriveAppProperties(prepared.metadata);

      final media = drive.Media(
        prepared.archiveFile.openRead(),
        await prepared.archiveFile.length(),
      );

      final uploaded = existing.files?.isNotEmpty == true
          ? await api.files.update(
              metadata,
              existing.files!.first.id!,
              uploadMedia: media,
            )
          : await api.files.create(metadata, uploadMedia: media);

      return prepared.metadata.copyWith(archiveFileId: uploaded.id);
    } on GoogleAuthException catch (error) {
      throw DriveBackupException(error.message);
    } catch (error) {
      throw DriveBackupException('Google Drive 備份失敗：$error');
    } finally {
      if (await prepared.archiveFile.exists()) {
        await prepared.archiveFile.delete();
      }
    }
  }

  Future<DriveBackupMetadata> restoreLatestBackup() async {
    try {
      final api =
          await _authService.getAuthorizedDriveApi(interactiveIfNeeded: true);
      final response = await api.files.list(
        spaces: 'appDataFolder',
        q: "name = '$backupFileName' and trashed = false",
        $fields: 'files(id,name,modifiedTime,size,appProperties)',
        orderBy: 'modifiedTime desc',
        pageSize: 1,
      );
      final remoteFile =
          response.files?.isNotEmpty == true ? response.files!.first : null;
      if (remoteFile?.id == null) {
        throw const DriveBackupException('Google Drive 上找不到可還原的備份。');
      }

      final mediaResponse = await api.files.get(
        remoteFile!.id!,
        downloadOptions: drive.DownloadOptions.fullMedia,
      );
      if (mediaResponse is! drive.Media) {
        throw const DriveBackupException('無法下載 Google Drive 備份檔。');
      }

      final tempDir = await _temporaryDirectory();
      await tempDir.create(recursive: true);
      final archiveFile = File(
        p.join(tempDir.path, 'lecture_vault_restore_${_randomSuffix()}.zip'),
      );
      final sink = archiveFile.openWrite();
      await mediaResponse.stream.pipe(sink);
      await sink.close();

      final restored = await restoreFromArchive(archiveFile);
      final remoteMetadata = _metadataFromDriveFile(remoteFile);
      return restored.metadata.copyWith(
        archiveFileId: remoteFile.id,
        createdAt: remoteMetadata?.createdAt ?? restored.metadata.createdAt,
      );
    } on GoogleAuthException catch (error) {
      throw DriveBackupException(error.message);
    } catch (error) {
      if (error is DriveBackupException) {
        rethrow;
      }
      throw DriveBackupException('Google Drive 還原失敗：$error');
    }
  }

  Future<RestoredDriveBackup> restoreFromArchive(File archiveFile) async {
    if (!await archiveFile.exists()) {
      throw const DriveBackupException('找不到要還原的備份壓縮檔。');
    }

    await _dbService.close();

    final input = InputFileStream(archiveFile.path);
    final archive = ZipDecoder().decodeBuffer(input);
    input.closeSync();

    final dbFile = await _dbService.getDatabaseFile();
    await dbFile.parent.create(recursive: true);

    final audioDirectory = await _dbService.getManagedAudioDirectory();
    if (await audioDirectory.exists()) {
      await audioDirectory.delete(recursive: true);
    }
    await audioDirectory.create(recursive: true);

    DriveBackupMetadata? metadata;

    for (final archiveEntry in archive.files) {
      if (!archiveEntry.isFile) {
        continue;
      }

      final entryName = archiveEntry.name.replaceAll('\\', '/');
      final content = archiveEntry.content;
      final bytes = content is List<int>
          ? content
          : utf8.encode(content?.toString() ?? '');

      if (entryName == DriveBackupMetadata.metadataEntryName) {
        metadata = DriveBackupMetadata.decode(utf8.decode(bytes));
        continue;
      }

      if (entryName == _databaseEntryPath) {
        await dbFile.writeAsBytes(bytes, flush: true);
        continue;
      }

      if (entryName.startsWith('$_audioEntryRoot/')) {
        final relativePath = entryName.substring(_audioEntryRoot.length + 1);
        final outputFile = File(p.join(audioDirectory.path, relativePath));
        await outputFile.parent.create(recursive: true);
        await outputFile.writeAsBytes(bytes, flush: true);
      }
    }

    if (metadata == null) {
      throw const DriveBackupException('備份檔缺少 metadata.json，無法還原。');
    }

    return RestoredDriveBackup(metadata: metadata, archiveFile: archiveFile);
  }

  Map<String, String> _buildDriveAppProperties(DriveBackupMetadata metadata) {
    return {
      _appPropertyBackupType: _backupTypeValue,
      _appPropertyCreatedAt: metadata.createdAt.toUtc().toIso8601String(),
      _appPropertyAudioFileCount: metadata.audioFileCount.toString(),
      _appPropertyDatabaseFileCount: metadata.databaseFileCount.toString(),
      _appPropertyFormatVersion: metadata.backupFormatVersion.toString(),
      _appPropertyTotalBytes: metadata.totalBytes.toString(),
    };
  }

  DriveBackupMetadata? _metadataFromDriveFile(drive.File file) {
    final properties = file.appProperties;
    if (properties == null ||
        properties[_appPropertyBackupType] != _backupTypeValue) {
      return null;
    }

    return DriveBackupMetadata(
      backupId: file.id ?? '',
      createdAt:
          DateTime.tryParse(properties[_appPropertyCreatedAt] ?? '')?.toUtc() ??
              file.modifiedTime?.toUtc() ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      backupFormatVersion:
          int.tryParse(properties[_appPropertyFormatVersion] ?? '') ??
              DriveBackupMetadata.currentBackupFormatVersion,
      databaseFileCount:
          int.tryParse(properties[_appPropertyDatabaseFileCount] ?? '') ?? 0,
      audioFileCount:
          int.tryParse(properties[_appPropertyAudioFileCount] ?? '') ?? 0,
      totalBytes: int.tryParse(properties[_appPropertyTotalBytes] ?? '') ??
          int.tryParse(file.size ?? '') ??
          0,
      archiveFileId: file.id,
      archiveFileName: file.name ?? backupFileName,
    );
  }

  String _randomSuffix() =>
      _random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0');
}
