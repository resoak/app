import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

const String googleClientId =
    String.fromEnvironment('GOOGLE_CLIENT_ID', defaultValue: '');
const String googleServerClientId =
    String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID', defaultValue: '');
const String androidGoogleSignInPackageName = 'com.example.lecture_vault';

GoogleSignIn buildGoogleSignIn({required List<String> scopes}) {
  return GoogleSignIn(
    scopes: scopes,
    clientId: googleClientId.trim().isEmpty ? null : googleClientId.trim(),
    serverClientId: googleServerClientId.trim().isEmpty
        ? null
        : googleServerClientId.trim(),
  );
}

String mapGoogleSignInError(Object error) {
  final normalized = _normalizeGoogleSignInError(error);

  if (_containsAny(normalized, const ['canceled', 'cancelled']) ||
      (error is PlatformException &&
          error.code == GoogleSignIn.kSignInCanceledError)) {
    return '已取消 Google 登入。';
  }

  if (_containsAny(normalized, const ['network', 'connection'])) {
    return 'Google 登入失敗：網路連線異常。';
  }

  if (_containsAny(
      normalized, const ['user-recoverable', 'user_recoverable'])) {
    return 'Google 帳號需要重新驗證，請登出後再重新登入。';
  }

  if (_containsAny(normalized, const [
    'apiexception: 10',
    'developer_error',
    '12500',
  ])) {
    return _googleDeveloperErrorMessage();
  }

  if (_containsAny(normalized, const [
    'clientconfiguration',
    'serverclientid',
    'client id',
    'reversed client id',
    'default_web_client_id',
    'configuration',
  ])) {
    return _googleConfigurationMessage();
  }

  if (error is PlatformException && error.message?.trim().isNotEmpty == true) {
    return error.message!.trim();
  }

  final message = error.toString().trim();
  return message.isNotEmpty ? message : 'Google 登入失敗，請稍後再試。';
}

String _normalizeGoogleSignInError(Object error) {
  if (error is PlatformException) {
    return '${error.code} ${error.message ?? ''}'.toLowerCase();
  }
  return error.toString().toLowerCase();
}

bool _containsAny(String input, List<String> needles) {
  for (final needle in needles) {
    if (input.contains(needle)) {
      return true;
    }
  }
  return false;
}

String _googleConfigurationMessage() {
  return 'Google 登入尚未完成設定。若未使用標準 Firebase Android 設定產生 '
      'default_web_client_id，請改用 --dart-define=GOOGLE_SERVER_CLIENT_ID=<web-client-id> '
      '提供 Web OAuth client ID 後再試。';
}

String _googleDeveloperErrorMessage() {
  return 'Google 登入設定錯誤（developer_error / SHA-1）。請確認 Google Cloud 或 Firebase '
      '中的 Android OAuth client package name 為 '
      '$androidGoogleSignInPackageName，並已加入目前安裝版本使用的 SHA-1；若需要 Google Drive '
      '授權，再提供 Web OAuth client ID（--dart-define=GOOGLE_SERVER_CLIENT_ID=... 或標準 '
      'Firebase 產生的 default_web_client_id）。目前 repo 內的 android/app/google-services.json '
      '不是可直接完成 Android Google 登入設定的標準 Firebase 檔案。';
}
