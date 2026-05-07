import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_vault/services/google_sign_in_configuration.dart';

void main() {
  group('mapGoogleSignInError', () {
    test('explains Android developer_error with package and SHA-1 guidance',
        () {
      final error = PlatformException(
        code: 'sign_in_failed',
        message: 'ApiException: 10: developer_error',
      );

      final message = mapGoogleSignInError(error);

      expect(message, contains('developer_error / SHA-1'));
      expect(message, contains(androidGoogleSignInPackageName));
      expect(message, contains('GOOGLE_SERVER_CLIENT_ID'));
      expect(message, contains('google-services.json'));
    });

    test('explains missing client configuration with dart-define guidance', () {
      final error = PlatformException(
        code: 'sign_in_failed',
        message: 'Missing default_web_client_id clientConfiguration',
      );

      final message = mapGoogleSignInError(error);

      expect(message, contains('Google 登入尚未完成設定'));
      expect(message, contains('GOOGLE_SERVER_CLIENT_ID'));
      expect(message, contains('default_web_client_id'));
    });
  });
}
