import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/drive_backup_metadata.dart';
import '../models/drive_backup_state.dart';
import '../services/drive_backup_local_store.dart';
import '../services/google_drive_auth_service.dart';
import '../services/google_drive_backup_service.dart';

final googleDriveAuthProvider = Provider<GoogleDriveAuthClient>((ref) {
  return GoogleDriveAuthService();
});

final driveBackupLocalStoreProvider = Provider<DriveBackupLocalStore>((ref) {
  return SettingsDriveBackupLocalStore();
});

final driveBackupServiceProvider = Provider<DriveBackupGateway>((ref) {
  return GoogleDriveBackupService(
    authClient: ref.read(googleDriveAuthProvider),
  );
});

final driveBackupControllerProvider =
    AsyncNotifierProvider<DriveBackupController, DriveBackupState>(
  DriveBackupController.new,
);

class DriveBackupController extends AsyncNotifier<DriveBackupState> {
  DriveBackupLocalStore get _localStore =>
      ref.read(driveBackupLocalStoreProvider);
  GoogleDriveAuthClient get _authService => ref.read(googleDriveAuthProvider);
  DriveBackupGateway get _backupService => ref.read(driveBackupServiceProvider);

  @override
  Future<DriveBackupState> build() async {
    final cachedAccount = await _localStore.loadCachedAccount();
    final cachedMetadata = await _localStore.loadLatestBackupMetadata();

    GoogleDriveAccount account =
        cachedAccount ?? const GoogleDriveAccount.signedOut();
    DriveBackupMetadata? latestBackup = cachedMetadata;
    String? lastError;

    try {
      account = await _authService.inspectAccount();
      if (account.isSignedIn) {
        await _localStore.saveCachedAccount(account);
        latestBackup = await _backupService.fetchLatestBackupMetadata();
        if (latestBackup != null) {
          await _localStore.saveLatestBackupMetadata(latestBackup);
        } else {
          await _localStore.clearLatestBackupMetadata();
        }
      }
    } catch (error) {
      lastError = error.toString();
    }

    return DriveBackupState(
      account: account,
      latestBackup: latestBackup,
      lastError: lastError,
    );
  }

  DriveBackupState get _current =>
      state.asData?.value ??
      const DriveBackupState(account: GoogleDriveAccount.signedOut());

  Future<GoogleDriveAccount> signIn() async {
    late GoogleDriveAccount signedInAccount;
    await _runBusy('正在連結 Google 帳號…', () async {
      signedInAccount = await _authService.signIn();
      await _localStore.saveCachedAccount(signedInAccount);
      state = AsyncData(
        _current.copyWith(
          account: signedInAccount,
          clearLastError: true,
        ),
      );
    });
    return signedInAccount;
  }

  Future<void> signOut() async {
    await _runBusy('正在中斷 Google 連結…', () async {
      await _authService.signOut();
      await _localStore.clearCachedAccount();
      state = AsyncData(
        _current.copyWith(
          account: const GoogleDriveAccount.signedOut(),
          clearLastError: true,
        ),
      );
    });
  }

  Future<void> refresh() async {
    await _runBusy('正在讀取 Google Drive 備份狀態…', () async {
      final account = await _authService.inspectAccount();
      final metadata = await _backupService.fetchLatestBackupMetadata(
        promptIfNeeded: false,
      );
      if (account.isSignedIn) {
        await _localStore.saveCachedAccount(account);
      } else {
        await _localStore.clearCachedAccount();
      }
      if (metadata == null) {
        await _localStore.clearLatestBackupMetadata();
      } else {
        await _localStore.saveLatestBackupMetadata(metadata);
      }
      state = AsyncData(
        _current.copyWith(
          account: account,
          latestBackup: metadata,
          clearLatestBackup: metadata == null,
          clearLastError: true,
        ),
      );
    });
  }

  Future<DriveBackupMetadata> createBackup() async {
    late DriveBackupMetadata metadata;
    await _runBusy('正在備份到 Google Drive…', () async {
      metadata = await _backupService.uploadLatestBackup();
      await _localStore.saveLatestBackupMetadata(metadata);
      state = AsyncData(
        _current.copyWith(
          latestBackup: metadata,
          clearLastError: true,
        ),
      );
    });
    return metadata;
  }

  Future<DriveBackupMetadata> restoreLatestBackup() async {
    late DriveBackupMetadata metadata;
    await _runBusy('正在從 Google Drive 還原備份…', () async {
      metadata = await _backupService.restoreLatestBackup();
      await _localStore.saveLatestBackupMetadata(metadata);
      state = AsyncData(
        _current.copyWith(
          latestBackup: metadata,
          clearLastError: true,
        ),
      );
    });
    return metadata;
  }

  Future<void> _runBusy(
    String _,
    Future<void> Function() action,
  ) async {
    final previous = _current;
    state = AsyncData(
      previous.copyWith(
        isBusy: true,
        clearLastError: true,
      ),
    );
    try {
      await action();
    } catch (error, stackTrace) {
      state = AsyncData(
        previous.copyWith(
          isBusy: false,
          lastError: error.toString(),
        ),
      );
      Error.throwWithStackTrace(error, stackTrace);
    } finally {
      state = AsyncData(_current.copyWith(isBusy: false));
    }
  }
}
