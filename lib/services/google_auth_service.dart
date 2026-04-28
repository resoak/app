import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';

const String _googleClientId =
    String.fromEnvironment('GOOGLE_CLIENT_ID', defaultValue: '');
const String _googleServerClientId =
    String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID', defaultValue: '');

class GoogleAuthException implements Exception {
  const GoogleAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

class GoogleAuthService {
  GoogleAuthService({GoogleSignIn? googleSignIn})
      : _googleSignIn = googleSignIn ??
            GoogleSignIn(
              scopes: const [drive.DriveApi.driveAppdataScope],
              clientId: _googleClientId.trim().isEmpty
                  ? null
                  : _googleClientId.trim(),
              serverClientId: _googleServerClientId.trim().isEmpty
                  ? null
                  : _googleServerClientId.trim(),
            );

  final GoogleSignIn _googleSignIn;

  GoogleSignInAccount? get currentUser => _googleSignIn.currentUser;

  String? get currentUserEmail => _googleSignIn.currentUser?.email;

  Future<GoogleSignInAccount?> tryRestoreSession() {
    return _googleSignIn.signInSilently(suppressErrors: true);
  }

  Future<GoogleSignInAccount> signInInteractive() async {
    try {
      final account = _googleSignIn.currentUser ?? await _googleSignIn.signIn();
      if (account == null) {
        throw const GoogleAuthException('已取消 Google 登入。');
      }

      final granted = await _googleSignIn.canAccessScopes(
        const [drive.DriveApi.driveAppdataScope],
      );
      if (!granted) {
        final requested = await _googleSignIn.requestScopes(
          const [drive.DriveApi.driveAppdataScope],
        );
        if (!requested) {
          throw const GoogleAuthException('尚未授權 Google Drive 備份權限。');
        }
      }

      return account;
    } on PlatformException catch (error) {
      throw GoogleAuthException(_mapPlatformError(error));
    }
  }

  Future<void> signOut() async {
    try {
      await _googleSignIn.disconnect();
    } on PlatformException {
      await _googleSignIn.signOut();
    }
  }

  Future<drive.DriveApi> getAuthorizedDriveApi({
    bool interactiveIfNeeded = false,
  }) async {
    try {
      var account = _googleSignIn.currentUser;
      account ??= await _googleSignIn.signInSilently(suppressErrors: true);
      if (account == null && interactiveIfNeeded) {
        account = await signInInteractive();
      }
      if (account == null) {
        throw const GoogleAuthException('請先連結 Google 帳號。');
      }

      final granted = await _googleSignIn.canAccessScopes(
        const [drive.DriveApi.driveAppdataScope],
      );
      if (!granted) {
        if (!interactiveIfNeeded) {
          throw const GoogleAuthException('Google Drive 權限尚未授予。');
        }
        final requested = await _googleSignIn.requestScopes(
          const [drive.DriveApi.driveAppdataScope],
        );
        if (!requested) {
          throw const GoogleAuthException('尚未授權 Google Drive 備份權限。');
        }
      }

      final client = await _googleSignIn.authenticatedClient();
      if (client == null) {
        throw const GoogleAuthException(
          '目前無法取得 Google Drive 授權。請重新登入後再試。',
        );
      }
      return drive.DriveApi(client);
    } on PlatformException catch (error) {
      throw GoogleAuthException(_mapPlatformError(error));
    }
  }

  String _mapPlatformError(PlatformException error) {
    final combined = '${error.code} ${error.message ?? ''}'.toLowerCase();
    if (combined.contains('clientconfiguration') ||
        combined.contains('serverclientid') ||
        combined.contains('client id') ||
        combined.contains('reversed client id') ||
        combined.contains('configuration')) {
      return 'Google 登入尚未完成設定。請補上 Google OAuth client 設定後再試。';
    }
    if (error.code == GoogleSignIn.kSignInCanceledError) {
      return '已取消 Google 登入。';
    }
    if (combined.contains('network')) {
      return 'Google 登入失敗：網路連線異常。';
    }
    return error.message?.trim().isNotEmpty == true
        ? error.message!.trim()
        : 'Google 登入失敗，請稍後再試。';
  }
}
