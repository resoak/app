// test/widget_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:lecture_vault/main.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const LectureVaultApp());
    await tester.pump();
    // App 啟動不 crash 即通過
    expect(find.byType(LectureVaultApp), findsOneWidget);
  });
}