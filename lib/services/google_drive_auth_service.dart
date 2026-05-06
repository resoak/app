import 'dart:async';

import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:flutter/foundation.dart';
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
      GoogleSignInAccount? currentUser = _googleSignIn.currentUser;
      
      // 如果目前沒有登入且需要提示，則嘗試登入
      if (currentUser == null) {
        if (promptIfNeeded) {
          currentUser = await _googleSignIn.signIn();
        } else {
          currentUser = await _googleSignIn.signInSilently();
        }
      }

      if (currentUser == null) {
        throw const DriveBackupException('請先登入 Google 帳號以進行雲端備份。');
      }

      // 韌性優化：主動清除快取以強迫刷新 Token，防止在備份中途過期
      try {
        await currentUser.clearAuthCache();
      } catch (e) {
        // 清除失敗通常不代表致命錯誤，記錄即可
        debugPrint('GoogleDriveAuth: 無法清除 Token 快取: $e');
      }

      final client = await _googleSignIn.authenticatedClient();
      if (client == null) {
        throw const DriveBackupException('無法取得 Google 授權，請嘗試重新登入。');
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

    // 針對台灣常見網路錯誤與 Google API 錯誤進行優化
    if (normalized.contains('network') || normalized.contains('connection')) {
      return DriveBackupException('網路連線異常，請檢查 Wi-Fi 或行動數據後再試。', cause: error);
    }

    if (normalized.contains('canceled') || normalized.contains('cancelled')) {
      return DriveBackupException('操作已取消。', cause: error);
    }

    if (normalized.contains('user-recoverable')) {
      return DriveBackupException('Google 帳號需要重新驗證，請登出後再重新登入。', cause: error);
    }

    if (normalized.contains('apiexception: 10') ||
        normalized.contains('developer_error')) {
      return DriveBackupException(
        'Google 服務設定錯誤（可能是 SHA-1 指紋不符），請聯絡開發人員。',
        cause: error,
      );
    }

    return DriveBackupException(
      'Google Drive 服務暫時無法使用 ($error)',
      cause: error,
    );
  }
}
