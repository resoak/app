import 'dart:convert';
import 'dart:typed_data';

import 'package:googleapis/drive/v3.dart' as drive;

import '../models/drive_backup_metadata.dart';
import 'db_service.dart';
import 'drive_backup_archive_service.dart';
import 'google_drive_auth_service.dart';

abstract interface class DriveBackupGateway {
  Future<DriveBackupMetadata?> fetchLatestBackupMetadata({bool promptIfNeeded});

  Future<DriveBackupMetadata> uploadLatestBackup();

  Future<DriveBackupMetadata> restoreLatestBackup();
}

class GoogleDriveBackupService implements DriveBackupGateway {
  GoogleDriveBackupService({
    GoogleDriveAuthClient? authClient,
    DriveBackupArchiveService? archiveService,
    DbService? dbService,
  })  : _authClient = authClient ?? GoogleDriveAuthService(),
        _archiveService = archiveService ?? DriveBackupArchiveService(),
        _dbService = dbService ?? DbService();

  final GoogleDriveAuthClient _authClient;
  final DriveBackupArchiveService _archiveService;
  final DbService _dbService;

  @override
  Future<DriveBackupMetadata?> fetchLatestBackupMetadata({bool promptIfNeeded = false}) async {
    final client = await _authClient.getAuthenticatedClient(promptIfNeeded: promptIfNeeded);
    final api = drive.DriveApi(client);
    final metadataFile = await _findBackupFile(api, DriveBackupMetadata.metadataFileNameDefault);
    if (metadataFile == null) {
      return null;
    }

    final rawContent = await _downloadText(api, metadataFile.id!);
    final metadata = DriveBackupMetadata.decode(rawContent);
    final archiveFile = await _findBackupFile(api, DriveBackupMetadata.archiveFileNameDefault);
    return metadata.copyWith(
      archiveFileId: archiveFile?.id ?? metadata.archiveFileId,
      archiveFileName: archiveFile?.name ?? metadata.archiveFileName,
    );
  }

  @override
  Future<DriveBackupMetadata> uploadLatestBackup() async {
    final client = await _authClient.getAuthenticatedClient(promptIfNeeded: true);
    final api = drive.DriveApi(client);
    final bundle = await _archiveService.createBackupArchive();

    final archiveFile = await _createOrUpdateFile(
      api: api,
      name: DriveBackupMetadata.archiveFileNameDefault,
      mimeType: 'application/zip',
      bytes: bundle.bytes,
    );

    final metadata = bundle.metadata.copyWith(
      archiveFileId: archiveFile.id,
      archiveFileName: archiveFile.name ?? DriveBackupMetadata.archiveFileNameDefault,
    );

    await _createOrUpdateFile(
      api: api,
      name: DriveBackupMetadata.metadataFileNameDefault,
      mimeType: 'application/json',
      bytes: Uint8List.fromList(utf8.encode(metadata.encode())),
    );

    return metadata;
  }

  @override
  Future<DriveBackupMetadata> restoreLatestBackup() async {
    final client = await _authClient.getAuthenticatedClient(promptIfNeeded: true);
    final api = drive.DriveApi(client);

    final metadata = await fetchLatestBackupMetadata(promptIfNeeded: true);
    final archiveFile = metadata?.archiveFileId == null
        ? await _findBackupFile(api, DriveBackupMetadata.archiveFileNameDefault)
        : await api.files.get(
            metadata!.archiveFileId!,
            $fields: 'id,name,modifiedTime,size',
          ) as drive.File;

    if (archiveFile == null || archiveFile.id == null) {
      throw const DriveBackupException('Google Drive 上找不到可還原的備份檔。');
    }

    final archiveBytes = await _downloadBytes(api, archiveFile.id!);
    await _dbService.close();
    final restoredMetadata = await _archiveService.restoreBackupArchive(archiveBytes);
    return restoredMetadata.copyWith(
      archiveFileId: archiveFile.id,
      archiveFileName: archiveFile.name ?? DriveBackupMetadata.archiveFileNameDefault,
    );
  }

  Future<drive.File> _createOrUpdateFile({
    required drive.DriveApi api,
    required String name,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    final existing = await _findBackupFile(api, name);
    final file = drive.File()
      ..name = name
      ..parents = const ['appDataFolder']
      ..mimeType = mimeType
      ..appProperties = {
        'logicalKey': 'latestBackup',
        'backupFormatVersion':
            '${DriveBackupMetadata.currentBackupFormatVersion}',
      };
    final media = drive.Media(Stream<List<int>>.value(bytes), bytes.length, contentType: mimeType);

    if (existing?.id != null) {
      return await api.files.update(
        file,
        existing!.id!,
        uploadMedia: media,
        $fields: 'id,name,modifiedTime,size',
      );
    }

    return await api.files.create(
      file,
      uploadMedia: media,
      $fields: 'id,name,modifiedTime,size',
    );
  }

  Future<drive.File?> _findBackupFile(drive.DriveApi api, String name) async {
    final escapedName = name.replaceAll("'", r"\'");
    final response = await api.files.list(
      spaces: 'appDataFolder',
      pageSize: 10,
      q: "name = '$escapedName' and 'appDataFolder' in parents and trashed = false",
      $fields: 'files(id,name,modifiedTime,size)',
    );

    final files = response.files;
    if (files == null || files.isEmpty) {
      return null;
    }

    files.sort((left, right) {
      final leftTime = left.modifiedTime ?? DateTime.fromMillisecondsSinceEpoch(0);
      final rightTime = right.modifiedTime ?? DateTime.fromMillisecondsSinceEpoch(0);
      return rightTime.compareTo(leftTime);
    });
    return files.first;
  }

  Future<String> _downloadText(drive.DriveApi api, String fileId) async {
    final bytes = await _downloadBytes(api, fileId);
    return utf8.decode(bytes);
  }

  Future<Uint8List> _downloadBytes(drive.DriveApi api, String fileId) async {
    final response = await api.files.get(
      fileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
    );

    if (response is! drive.Media) {
      throw const DriveBackupException('Google Drive 回傳了無法辨識的備份內容。');
    }

    final chunks = <int>[];
    await for (final chunk in response.stream) {
      chunks.addAll(chunk);
    }
    return Uint8List.fromList(chunks);
  }
}
