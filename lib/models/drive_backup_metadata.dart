import 'dart:convert';

class DriveBackupMetadata {
  const DriveBackupMetadata({
    required this.backupId,
    required this.createdAt,
    required this.backupFormatVersion,
    required this.databaseFileCount,
    required this.audioFileCount,
    required this.totalBytes,
    this.archiveFileId,
    this.archiveFileName = 'lecture_vault_latest_backup.zip',
  });

  static const int currentBackupFormatVersion = 1;
  static const String metadataEntryName = 'metadata.json';
  static const String archiveFileNameDefault =
      'lecture_vault_latest_backup.zip';
  static const String metadataFileNameDefault =
      'lecture_vault_latest_backup.metadata.json';

  final String backupId;
  final DateTime createdAt;
  final int backupFormatVersion;
  final int databaseFileCount;
  final int audioFileCount;
  final int totalBytes;
  final String? archiveFileId;
  final String archiveFileName;

  DriveBackupMetadata copyWith({
    String? backupId,
    DateTime? createdAt,
    int? backupFormatVersion,
    int? databaseFileCount,
    int? audioFileCount,
    int? totalBytes,
    String? archiveFileId,
    bool clearArchiveFileId = false,
    String? archiveFileName,
  }) {
    return DriveBackupMetadata(
      backupId: backupId ?? this.backupId,
      createdAt: createdAt ?? this.createdAt,
      backupFormatVersion: backupFormatVersion ?? this.backupFormatVersion,
      databaseFileCount: databaseFileCount ?? this.databaseFileCount,
      audioFileCount: audioFileCount ?? this.audioFileCount,
      totalBytes: totalBytes ?? this.totalBytes,
      archiveFileId:
          clearArchiveFileId ? null : (archiveFileId ?? this.archiveFileId),
      archiveFileName: archiveFileName ?? this.archiveFileName,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'backupId': backupId,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'backupFormatVersion': backupFormatVersion,
      'databaseFileCount': databaseFileCount,
      'audioFileCount': audioFileCount,
      'totalBytes': totalBytes,
      'archiveFileId': archiveFileId,
      'archiveFileName': archiveFileName,
    };
  }

  String encode() => jsonEncode(toJson());

  factory DriveBackupMetadata.fromJson(Map<String, dynamic> json) {
    return DriveBackupMetadata(
      backupId: json['backupId'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '')?.toUtc() ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      backupFormatVersion: (json['backupFormatVersion'] as num?)?.toInt() ??
          currentBackupFormatVersion,
      databaseFileCount: (json['databaseFileCount'] as num?)?.toInt() ?? 0,
      audioFileCount: (json['audioFileCount'] as num?)?.toInt() ?? 0,
      totalBytes: (json['totalBytes'] as num?)?.toInt() ?? 0,
      archiveFileId: json['archiveFileId'] as String?,
      archiveFileName:
          json['archiveFileName'] as String? ?? archiveFileNameDefault,
    );
  }

  factory DriveBackupMetadata.decode(String raw) {
    return DriveBackupMetadata.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
  }
}
