// test/widget_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_vault/models/app_settings.dart';
import 'package:lecture_vault/theme/lecture_vault_theme.dart';

void main() {
  testWidgets('buildLectureVaultTheme supports white and default variants', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildLectureVaultTheme(AppBackgroundStyle.white),
        home: const SizedBox.shrink(),
      ),
    );

    var materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(materialApp.theme?.brightness, Brightness.light);
    expect(
      materialApp.theme?.scaffoldBackgroundColor,
      buildLectureVaultTheme(AppBackgroundStyle.white).scaffoldBackgroundColor,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildLectureVaultTheme(AppBackgroundStyle.darkDefault),
        home: const SizedBox.shrink(),
      ),
    );

    materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(materialApp.theme?.brightness, Brightness.dark);
    expect(
      materialApp.theme?.scaffoldBackgroundColor,
      buildLectureVaultTheme(AppBackgroundStyle.darkDefault)
          .scaffoldBackgroundColor,
    );
  });
}
