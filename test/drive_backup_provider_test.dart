import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_vault/models/drive_backup_metadata.dart';
import 'package:lecture_vault/models/drive_backup_state.dart';
import 'package:lecture_vault/providers/drive_backup_provider.dart';
import 'package:lecture_vault/services/drive_backup_local_store.dart';
import 'package:lecture_vault/services/google_drive_auth_service.dart';
import 'package:lecture_vault/services/google_drive_backup_service.dart';
import 'package:http/http.dart' as http;

class _FakeDriveBackupLocalStore implements DriveBackupLocalStore {
  GoogleDriveAccount? account;
  DriveBackupMetadata? latestBackup;

  @override
  Future<void> clearCachedAccount() async {
    account = null;
  }

  @override
  Future<void> clearLatestBackupMetadata() async {
    latestBackup = null;
  }

  @override
  Future<GoogleDriveAccount?> loadCachedAccount() async => account;

  @override
  Future<DriveBackupMetadata?> loadLatestBackupMetadata() async => latestBackup;

  @override
  Future<void> saveCachedAccount(GoogleDriveAccount account) async {
    this.account = account;
  }

  @override
  Future<void> saveLatestBackupMetadata(DriveBackupMetadata metadata) async {
    latestBackup = metadata;
  }
}

class _FakeGoogleDriveAuthClient implements GoogleDriveAuthClient {
  _FakeGoogleDriveAuthClient({required this.account});

  GoogleDriveAccount account;

  @override
  Future<GoogleDriveAccount> inspectAccount({bool trySilent = true}) async =>
      account;

  @override
  Future<GoogleDriveAccount> signIn() async {
    account = const GoogleDriveAccount(
      isSignedIn: true,
      email: 'student@example.com',
      displayName: 'Student',
    );
    return account;
  }

  @override
  Future<void> signOut() async {
    account = const GoogleDriveAccount.signedOut();
  }

  @override
  Future<http.Client> getAuthenticatedClient(
      {bool promptIfNeeded = false}) async {
    return http.Client();
  }
}

class _FakeDriveBackupGateway implements DriveBackupGateway {
  _FakeDriveBackupGateway({this.latestBackup});

  DriveBackupMetadata? latestBackup;
  var uploadCount = 0;
  var restoreCount = 0;

  @override
  Future<DriveBackupMetadata?> fetchLatestBackupMetadata(
      {bool promptIfNeeded = false}) async {
    return latestBackup;
  }

  @override
  Future<DriveBackupMetadata> restoreLatestBackup() async {
    restoreCount += 1;
    return latestBackup!;
  }

  @override
  Future<DriveBackupMetadata> uploadLatestBackup() async {
    uploadCount += 1;
    return latestBackup!;
  }
}

void main() {
  group('DriveBackupController', () {
    test(
        'loads cached state and refreshes signed-in account plus latest backup',
        () async {
      final localStore = _FakeDriveBackupLocalStore();
      final latestBackup = DriveBackupMetadata(
        backupId: 'backup-1',
        createdAt: DateTime.utc(2026, 4, 25, 15),
        backupFormatVersion: 1,
        databaseFileCount: 1,
        audioFileCount: 2,
        totalBytes: 2048,
      );
      final authClient = _FakeGoogleDriveAuthClient(
        account: const GoogleDriveAccount(
          isSignedIn: true,
          email: 'student@example.com',
          displayName: 'Student',
        ),
      );
      final backupGateway = _FakeDriveBackupGateway(latestBackup: latestBackup);

      final container = ProviderContainer(
        overrides: [
          driveBackupLocalStoreProvider.overrideWithValue(localStore),
          googleDriveAuthProvider.overrideWithValue(authClient),
          driveBackupServiceProvider.overrideWithValue(backupGateway),
        ],
      );
      addTearDown(container.dispose);

      final state = await container.read(driveBackupControllerProvider.future);

      expect(state.account.isSignedIn, isTrue);
      expect(state.account.email, 'student@example.com');
      expect(state.latestBackup?.backupId, 'backup-1');
      expect(localStore.account?.email, 'student@example.com');
      expect(localStore.latestBackup?.backupId, 'backup-1');
    });

    test('createBackup updates latest backup metadata', () async {
      final localStore = _FakeDriveBackupLocalStore();
      final latestBackup = DriveBackupMetadata(
        backupId: 'backup-2',
        createdAt: DateTime.utc(2026, 4, 25, 16),
        backupFormatVersion: 1,
        databaseFileCount: 1,
        audioFileCount: 3,
        totalBytes: 4096,
      );
      final authClient = _FakeGoogleDriveAuthClient(
        account: const GoogleDriveAccount(
          isSignedIn: true,
          email: 'student@example.com',
          displayName: 'Student',
        ),
      );
      final backupGateway = _FakeDriveBackupGateway(latestBackup: latestBackup);

      final container = ProviderContainer(
        overrides: [
          driveBackupLocalStoreProvider.overrideWithValue(localStore),
          googleDriveAuthProvider.overrideWithValue(authClient),
          driveBackupServiceProvider.overrideWithValue(backupGateway),
        ],
      );
      addTearDown(container.dispose);
      await container.read(driveBackupControllerProvider.future);

      final metadata = await container
          .read(driveBackupControllerProvider.notifier)
          .createBackup();
      final state = container.read(driveBackupControllerProvider).requireValue;

      expect(metadata.backupId, 'backup-2');
      expect(state.latestBackup?.backupId, 'backup-2');
      expect(backupGateway.uploadCount, 1);
    });
  });
}
