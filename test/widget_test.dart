// test/widget_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:lecture_vault/main.dart';
import 'package:lecture_vault/services/db_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await DbService().resetForTests();
  });

  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: LectureVaultApp(),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('BASE'), findsOneWidget);
    expect(find.text('SMALL'), findsOneWidget);
    expect(find.text('MEDIUM'), findsNothing);

    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(LectureVaultApp), findsOneWidget);
  });
}
