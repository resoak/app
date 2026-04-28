import 'drive_backup_metadata.dart';

class GoogleDriveAccount {
  const GoogleDriveAccount({
    required this.isSignedIn,
    required this.email,
    required this.displayName,
    this.userMessage,
  });

  const GoogleDriveAccount.signedOut({this.userMessage})
      : isSignedIn = false,
        email = '',
        displayName = '';

  final bool isSignedIn;
  final String email;
  final String displayName;
  final String? userMessage;

  String get label {
    if (displayName.trim().isNotEmpty) {
      return displayName.trim();
    }
    if (email.trim().isNotEmpty) {
      return email.trim();
    }
    return 'Google Drive';
  }

  GoogleDriveAccount copyWith({
    bool? isSignedIn,
    String? email,
    String? displayName,
    String? userMessage,
    bool clearUserMessage = false,
  }) {
    return GoogleDriveAccount(
      isSignedIn: isSignedIn ?? this.isSignedIn,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      userMessage: clearUserMessage ? null : (userMessage ?? this.userMessage),
    );
  }
}

class DriveBackupState {
  const DriveBackupState({
    required this.account,
    this.latestBackup,
    this.isBusy = false,
    this.lastError,
  });

  final GoogleDriveAccount account;
  final DriveBackupMetadata? latestBackup;
  final bool isBusy;
  final String? lastError;

  bool get isConnected => account.isSignedIn;

  bool get canRunDriveActions => account.isSignedIn && !isBusy;

  DriveBackupState copyWith({
    GoogleDriveAccount? account,
    DriveBackupMetadata? latestBackup,
    bool clearLatestBackup = false,
    bool? isBusy,
    String? lastError,
    bool clearLastError = false,
  }) {
    return DriveBackupState(
      account: account ?? this.account,
      latestBackup:
          clearLatestBackup ? null : (latestBackup ?? this.latestBackup),
      isBusy: isBusy ?? this.isBusy,
      lastError: clearLastError ? null : (lastError ?? this.lastError),
    );
  }
}
