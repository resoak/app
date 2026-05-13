import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
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
  Future<DriveBackupMetadata?> fetchLatestBackupMetadata(
      {bool promptIfNeeded = false}) async {
    return _runWithRetry(() async {
      debugPrint('GoogleDriveBackupService.fetchLatestBackupMetadata: start promptIfNeeded=$promptIfNeeded');
      final client = await _authClient.getAuthenticatedClient(
          promptIfNeeded: promptIfNeeded);
      debugPrint('GoogleDriveBackupService.fetchLatestBackupMetadata: authenticated client ready');
      final api = drive.DriveApi(client);
      debugPrint('GoogleDriveBackupService.fetchLatestBackupMetadata: listing metadata file');
      final metadataFile = await _findBackupFile(
          api, DriveBackupMetadata.metadataFileNameDefault);
      debugPrint('GoogleDriveBackupService.fetchLatestBackupMetadata: metadata file ${metadataFile?.id ?? 'null'}');
      if (metadataFile == null) {
        return null;
      }

      debugPrint('GoogleDriveBackupService.fetchLatestBackupMetadata: downloading metadata');
      final rawContent = await _downloadText(api, metadataFile.id!);
      debugPrint('GoogleDriveBackupService.fetchLatestBackupMetadata: decoding metadata');
      final metadata = DriveBackupMetadata.decode(rawContent);
      debugPrint('GoogleDriveBackupService.fetchLatestBackupMetadata: listing archive file');
      final archiveFile = await _findBackupFile(
          api, DriveBackupMetadata.archiveFileNameDefault);
      debugPrint('GoogleDriveBackupService.fetchLatestBackupMetadata: done');
      return metadata.copyWith(
        archiveFileId: archiveFile?.id ?? metadata.archiveFileId,
        archiveFileName: archiveFile?.name ?? metadata.archiveFileName,
      );
    });
  }

  @override
  Future<DriveBackupMetadata> uploadLatestBackup() async {
    debugPrint('GoogleDriveBackupService.uploadLatestBackup: start');
    debugPrint('GoogleDriveBackupService.uploadLatestBackup: creating archive');
    final bundle = await _archiveService.createBackupArchive();
    debugPrint('GoogleDriveBackupService.uploadLatestBackup: archive ready');

    return _runWithRetry(() async {
      debugPrint('GoogleDriveBackupService.uploadLatestBackup: requesting authenticated client');
      final client =
          await _authClient.getAuthenticatedClient(promptIfNeeded: true);
      debugPrint('GoogleDriveBackupService.uploadLatestBackup: authenticated client ready');
      final api = drive.DriveApi(client);

      debugPrint('GoogleDriveBackupService.uploadLatestBackup: uploading archive file');
      final archiveFile = await _createOrUpdateFile(
        api: api,
        name: DriveBackupMetadata.archiveFileNameDefault,
        mimeType: 'application/zip',
        bytes: bundle.bytes,
      );

      final metadata = bundle.metadata.copyWith(
        archiveFileId: archiveFile.id,
        archiveFileName:
            archiveFile.name ?? DriveBackupMetadata.archiveFileNameDefault,
      );

      debugPrint('GoogleDriveBackupService.uploadLatestBackup: uploading metadata file');
      await _createOrUpdateFile(
        api: api,
        name: DriveBackupMetadata.metadataFileNameDefault,
        mimeType: 'application/json',
        bytes: Uint8List.fromList(utf8.encode(metadata.encode())),
      );

      debugPrint('GoogleDriveBackupService.uploadLatestBackup: done');
      return metadata;
    });
  }

  @override
  Future<DriveBackupMetadata> restoreLatestBackup() async {
    debugPrint('GoogleDriveBackupService.restoreLatestBackup: start');
    return _runWithRetry(() async {
      debugPrint('GoogleDriveBackupService.restoreLatestBackup: requesting authenticated client');
      final client =
          await _authClient.getAuthenticatedClient(promptIfNeeded: true);
      debugPrint('GoogleDriveBackupService.restoreLatestBackup: authenticated client ready');
      final api = drive.DriveApi(client);

      debugPrint('GoogleDriveBackupService.restoreLatestBackup: fetching metadata');
      final metadata = await fetchLatestBackupMetadata(promptIfNeeded: true);
      debugPrint('GoogleDriveBackupService.restoreLatestBackup: metadata ${metadata?.archiveFileId ?? 'null'}');
      final archiveFile = metadata?.archiveFileId == null
          ? await _findBackupFile(
              api, DriveBackupMetadata.archiveFileNameDefault)
          : await api.files.get(
              metadata!.archiveFileId!,
              $fields: 'id,name,modifiedTime,size',
            ) as drive.File;

      if (archiveFile == null || archiveFile.id == null) {
        throw const DriveBackupException('Google Drive 上找不到可還原的備份檔。');
      }

      debugPrint('GoogleDriveBackupService.restoreLatestBackup: downloading archive bytes');
      final archiveBytes = await _downloadBytes(api, archiveFile.id!);
      debugPrint('GoogleDriveBackupService.restoreLatestBackup: closing db');
      await _dbService.close();
      debugPrint('GoogleDriveBackupService.restoreLatestBackup: restoring archive');
      final restoredMetadata =
          await _archiveService.restoreBackupArchive(archiveBytes);
      debugPrint('GoogleDriveBackupService.restoreLatestBackup: notifying mutation');
      _dbService.notifyExternalDataMutation();
      debugPrint('GoogleDriveBackupService.restoreLatestBackup: done');
      return restoredMetadata.copyWith(
        archiveFileId: archiveFile.id,
        archiveFileName:
            archiveFile.name ?? DriveBackupMetadata.archiveFileNameDefault,
      );
    });
  }

  Future<T> _runWithRetry<T>(Future<T> Function() action,
      {int maxRetries = 3}) async {
    int attempts = 0;
    while (true) {
      try {
        attempts++;
        return await action();
      } catch (e) {
        final isLastAttempt = attempts >= maxRetries;
        final retryable = _isRetryable(e);
        
        // 加入日誌以便在模擬高延遲或不穩定網路時觀察行為
        debugPrint('DriveBackupService: 嘗試第 $attempts 次失敗。可重試: $retryable, 錯誤: $e');
        
        if (isLastAttempt || !retryable) {
          rethrow;
        }
        
        // 指數退避策略：2s, 4s, 8s...
        final delaySeconds = math.pow(2, attempts).toInt();
        debugPrint('DriveBackupService: 將在 $delaySeconds 秒後進行下一次嘗試...');
        await Future.delayed(Duration(seconds: delaySeconds));
      }
    }
  }

  bool _isRetryable(Object e) {
    if (e is DriveBackupException) {
      // 網路連線錯誤通常是可重試的
      return e.userMessage.contains('網路') || e.userMessage.contains('連線');
    }
    final msg = e.toString().toLowerCase();
    return msg.contains('network') ||
        msg.contains('timeout') ||
        msg.contains('connection') ||
        msg.contains('500') ||
        msg.contains('503') ||
        msg.contains('504');
  }

  Future<drive.File> _createOrUpdateFile({
    required drive.DriveApi api,
    required String name,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    debugPrint('GoogleDriveBackupService._createOrUpdateFile: start name=$name');
    final existing = await _findBackupFile(api, name);
    debugPrint('GoogleDriveBackupService._createOrUpdateFile: existing=${existing?.id ?? 'null'}');
    
    // 建立基礎的 metadata，不要在此處設定 parents
    final fileMetadata = drive.File()
      ..name = name
      ..mimeType = mimeType
      ..appProperties = {
        'logicalKey': 'latestBackup',
        'backupFormatVersion':
            '${DriveBackupMetadata.currentBackupFormatVersion}',
      };
      
    final media = drive.Media(Stream<List<int>>.value(bytes), bytes.length,
        contentType: mimeType);

    if (existing?.id != null) {
      // 更新現有檔案：Google Drive API v3 不允許在 update 請求的 metadata 中包含 parents
      debugPrint('GoogleDriveBackupService._createOrUpdateFile: updating existing file');
      return await api.files.update(
        fileMetadata,
        existing!.id!,
        uploadMedia: media,
        $fields: 'id,name,modifiedTime,size',
      );
    }

    // 建立新檔案：必須指定 parents 為 appDataFolder
    fileMetadata.parents = const ['appDataFolder'];
    debugPrint('GoogleDriveBackupService._createOrUpdateFile: creating new file');
    return await api.files.create(
      fileMetadata,
      uploadMedia: media,
      $fields: 'id,name,modifiedTime,size',
    );
  }

  Future<drive.File?> _findBackupFile(drive.DriveApi api, String name) async {
    debugPrint('GoogleDriveBackupService._findBackupFile: start name=$name');
    final escapedName = name.replaceAll("'", r"\'");
    final response = await api.files.list(
      spaces: 'appDataFolder',
      pageSize: 10,
      q: "name = '$escapedName' and 'appDataFolder' in parents and trashed = false",
      $fields: 'files(id,name,modifiedTime,size)',
    );

    final files = response.files;
    if (files == null || files.isEmpty) {
      debugPrint('GoogleDriveBackupService._findBackupFile: none found');
      return null;
    }

    files.sort((left, right) {
      final leftTime =
          left.modifiedTime ?? DateTime.fromMillisecondsSinceEpoch(0);
      final rightTime =
          right.modifiedTime ?? DateTime.fromMillisecondsSinceEpoch(0);
      return rightTime.compareTo(leftTime);
    });
    debugPrint('GoogleDriveBackupService._findBackupFile: found ${files.first.id}');
    return files.first;
  }

  Future<String> _downloadText(drive.DriveApi api, String fileId) async {
    debugPrint('GoogleDriveBackupService._downloadText: start fileId=$fileId');
    final bytes = await _downloadBytes(api, fileId);
    debugPrint('GoogleDriveBackupService._downloadText: done');
    return utf8.decode(bytes);
  }

  Future<Uint8List> _downloadBytes(drive.DriveApi api, String fileId) async {
    debugPrint('GoogleDriveBackupService._downloadBytes: start fileId=$fileId');
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
    debugPrint('GoogleDriveBackupService._downloadBytes: done fileId=$fileId bytes=${chunks.length}');
    return Uint8List.fromList(chunks);
  }
}
