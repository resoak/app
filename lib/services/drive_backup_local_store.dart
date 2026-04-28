import '../models/app_setting.dart';
import '../models/drive_backup_metadata.dart';
import '../models/drive_backup_state.dart';
import 'settings_service.dart';

abstract interface class DriveBackupLocalStore {
  Future<GoogleDriveAccount?> loadCachedAccount();

  Future<void> saveCachedAccount(GoogleDriveAccount account);

  Future<void> clearCachedAccount();

  Future<DriveBackupMetadata?> loadLatestBackupMetadata();

  Future<void> saveLatestBackupMetadata(DriveBackupMetadata metadata);

  Future<void> clearLatestBackupMetadata();
}

class SettingsDriveBackupLocalStore implements DriveBackupLocalStore {
  SettingsDriveBackupLocalStore({SettingsService? settingsService})
      : _settingsService = settingsService ?? SettingsService();

  final SettingsService _settingsService;

  @override
  Future<GoogleDriveAccount?> loadCachedAccount() async {
    final email =
        await _settingsService.getValue(DriveBackupSettingsKeys.accountEmail);
    final displayName = await _settingsService
        .getValue(DriveBackupSettingsKeys.accountDisplayName);

    if ((email ?? '').trim().isEmpty && (displayName ?? '').trim().isEmpty) {
      return null;
    }

    return GoogleDriveAccount(
      isSignedIn: true,
      email: email ?? '',
      displayName: displayName ?? '',
    );
  }

  @override
  Future<void> saveCachedAccount(GoogleDriveAccount account) async {
    await _syncValue(
        DriveBackupSettingsKeys.accountEmail, account.email.trim());
    await _syncValue(
      DriveBackupSettingsKeys.accountDisplayName,
      account.displayName.trim(),
    );
  }

  @override
  Future<void> clearCachedAccount() async {
    await _settingsService.deleteSetting(DriveBackupSettingsKeys.accountEmail);
    await _settingsService
        .deleteSetting(DriveBackupSettingsKeys.accountDisplayName);
  }

  @override
  Future<DriveBackupMetadata?> loadLatestBackupMetadata() async {
    final raw = await _settingsService
        .getValue(DriveBackupSettingsKeys.latestBackupMetadata);
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }

    try {
      return DriveBackupMetadata.decode(raw);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveLatestBackupMetadata(DriveBackupMetadata metadata) async {
    await _settingsService.saveSetting(
      AppSetting(
        key: DriveBackupSettingsKeys.latestBackupMetadata,
        value: metadata.encode(),
      ),
    );
  }

  @override
  Future<void> clearLatestBackupMetadata() async {
    await _settingsService
        .deleteSetting(DriveBackupSettingsKeys.latestBackupMetadata);
  }

  Future<void> _syncValue(String key, String value) async {
    if (value.isEmpty) {
      await _settingsService.deleteSetting(key);
      return;
    }

    await _settingsService.saveSetting(AppSetting(key: key, value: value));
  }
}

abstract final class DriveBackupSettingsKeys {
  static const String accountEmail = 'drive.account.email';
  static const String accountDisplayName = 'drive.account.displayName';
  static const String latestBackupMetadata = 'drive.backup.latestMetadata';
}
