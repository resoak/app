import 'dart:async';

import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

import '../models/drive_backup_state.dart';
import 'google_sign_in_configuration.dart';

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
      : _googleSignIn = googleSignIn ??
            buildGoogleSignIn(scopes: const [drive.DriveApi.driveAppdataScope]);

  final GoogleSignIn _googleSignIn;

  @override
  Future<GoogleDriveAccount> inspectAccount({bool trySilent = true}) async {
    try {
      final currentUser = _googleSignIn.currentUser ??
          (trySilent
              ? await _googleSignIn.signInSilently(suppressErrors: true)
              : null);
      return _toAccount(currentUser);
    } catch (error) {
      throw _mapException(error);
    }
  }

  @override
  Future<GoogleDriveAccount> signIn() async {
    try {
      debugPrint('GoogleDriveAuthService.signIn: start');
      final user = await _googleSignIn.signIn();
      debugPrint('GoogleDriveAuthService.signIn: signIn returned ${user?.email ?? 'null'}');
      if (user == null) {
        throw const DriveBackupException('已取消 Google 登入。');
      }
      debugPrint('GoogleDriveAuthService.signIn: success');
      return _toAccount(user);
    } catch (error) {
      debugPrint('GoogleDriveAuthService.signIn: error $error');
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
  Future<http.Client> getAuthenticatedClient(
      {bool promptIfNeeded = false}) async {
    try {
      debugPrint('GoogleDriveAuthService.getAuthenticatedClient: start promptIfNeeded=$promptIfNeeded');
      GoogleSignInAccount? currentUser = _googleSignIn.currentUser;
      debugPrint('GoogleDriveAuthService.getAuthenticatedClient: currentUser=${currentUser?.email ?? 'null'}');

      // 如果目前沒有登入且需要提示，則嘗試登入
      if (currentUser == null) {
        if (promptIfNeeded) {
          debugPrint('GoogleDriveAuthService.getAuthenticatedClient: calling signIn');
          currentUser = await _googleSignIn.signIn();
          debugPrint('GoogleDriveAuthService.getAuthenticatedClient: signIn returned ${currentUser?.email ?? 'null'}');
        } else {
          debugPrint('GoogleDriveAuthService.getAuthenticatedClient: calling signInSilently');
          currentUser =
              await _googleSignIn.signInSilently(suppressErrors: true);
          debugPrint('GoogleDriveAuthService.getAuthenticatedClient: signInSilently returned ${currentUser?.email ?? 'null'}');
        }
      }

      if (currentUser == null) {
        throw const DriveBackupException('請先登入 Google 帳號以進行雲端備份。');
      }

      // 韌性優化：主動清除快取以強迫刷新 Token，防止在備份中途過期
      try {
        debugPrint('GoogleDriveAuthService.getAuthenticatedClient: clearing auth cache');
        await currentUser.clearAuthCache();
        debugPrint('GoogleDriveAuthService.getAuthenticatedClient: auth cache cleared');
      } catch (e) {
        // 清除失敗通常不代表致命錯誤，記錄即可
        debugPrint('GoogleDriveAuth: 無法清除 Token 快取: $e');
      }

      debugPrint('GoogleDriveAuthService.getAuthenticatedClient: requesting authenticated client');
      final client = await _googleSignIn.authenticatedClient();
      debugPrint('GoogleDriveAuthService.getAuthenticatedClient: authenticated client ${client == null ? 'null' : 'ready'}');
      if (client == null) {
        throw const DriveBackupException('無法取得 Google 授權，請嘗試重新登入。');
      }
      debugPrint('GoogleDriveAuthService.getAuthenticatedClient: success');
      return client;
    } catch (error) {
      debugPrint('GoogleDriveAuthService.getAuthenticatedClient: error $error');
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
    final message = mapGoogleSignInError(error);

    if (message == error.toString()) {
      return DriveBackupException('Google Drive 服務暫時無法使用 ($error)',
          cause: error);
    }

    return DriveBackupException(message, cause: error);
  }
}
