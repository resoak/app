import 'dart:async';

import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

import '../models/drive_backup_state.dart';

class DriveBackupException implements Exception {
  const DriveBackupException(this.userMessage, {this.cause});

  final String userMessage;
  final Object? cause;

  @override
  String toString() => userMessage;
}

abstract interface class GoogleDriveAuthClient {
  Future<GoogleDriveAccount> inspectAccount({bool trySilent});

  Future<GoogleDriveAccount> signIn();

  Future<void> signOut();

  Future<http.Client> getAuthenticatedClient({bool promptIfNeeded});
}

class GoogleDriveAuthService implements GoogleDriveAuthClient {
  GoogleDriveAuthService({GoogleSignIn? googleSignIn})
      : _googleSignIn =
            googleSignIn ?? GoogleSignIn(scopes: [drive.DriveApi.driveAppdataScope]);

  final GoogleSignIn _googleSignIn;

  @override
  Future<GoogleDriveAccount> inspectAccount({bool trySilent = true}) async {
    try {
      final currentUser = _googleSignIn.currentUser ??
          (trySilent ? await _googleSignIn.signInSilently() : null);
      return _toAccount(currentUser);
    } catch (error) {
      throw _mapException(error);
    }
  }

  @override
  Future<GoogleDriveAccount> signIn() async {
    try {
      final user = await _googleSignIn.signIn();
      if (user == null) {
        throw const DriveBackupException('已取消 Google 登入。');
      }
      return _toAccount(user);
    } catch (error) {
      if (error is DriveBackupException) {
        rethrow;
      }
      throw _mapException(error);
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (error) {
      throw _mapException(error);
    }
  }

  @override
  Future<http.Client> getAuthenticatedClient({bool promptIfNeeded = false}) async {
    try {
      final currentUser = _googleSignIn.currentUser ??
          (promptIfNeeded ? await _googleSignIn.signIn() : await _googleSignIn.signInSilently());
      if (currentUser == null) {
        throw const DriveBackupException('請先使用 Google 帳號登入，才能操作雲端備份。');
      }

      final client = await _googleSignIn.authenticatedClient();
      if (client == null) {
        throw const DriveBackupException('Google Drive 授權未完成，請重新登入後再試一次。');
      }
      return client;
    } catch (error) {
      if (error is DriveBackupException) {
        rethrow;
      }
      throw _mapException(error);
    }
  }

  GoogleDriveAccount _toAccount(GoogleSignInAccount? user) {
    if (user == null) {
      return const GoogleDriveAccount.signedOut();
    }

    return GoogleDriveAccount(
      isSignedIn: true,
      email: user.email,
      displayName: user.displayName ?? '',
    );
  }

  DriveBackupException _mapException(Object error) {
    final message = error.toString();
    final normalized = message.toLowerCase();

    if (normalized.contains('network')) {
      return DriveBackupException('無法連線到 Google，請確認網路後再試一次。', cause: error);
    }

    if (normalized.contains('canceled') || normalized.contains('cancelled')) {
      return DriveBackupException('已取消 Google 登入。', cause: error);
    }

    if (normalized.contains('apiexception: 10') ||
        normalized.contains('developer_error') ||
        normalized.contains('clientid') ||
        normalized.contains('google-services.json') ||
        normalized.contains('oauth') ||
        normalized.contains('reverse_client_id')) {
      return DriveBackupException(
        'Google 登入尚未設定完成。請先在此 App 加入正確的 Google OAuth 設定檔後再試。',
        cause: error,
      );
    }

    return DriveBackupException(
      'Google Drive 驗證失敗，請稍後再試一次。',
      cause: error,
    );
  }
}
