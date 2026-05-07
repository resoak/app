import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_vault/models/app_settings.dart';
import 'package:lecture_vault/models/lecture.dart';
import 'package:lecture_vault/providers/app_settings_provider.dart';
import 'package:lecture_vault/services/db_service.dart';
import 'package:lecture_vault/services/settings_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('AppSettingsNotifier', () {
    late DbService db;
    late SettingsService settingsService;

    setUp(() async {
      db = DbService();
      await db.resetForTests();
      settingsService = SettingsService(dbService: db);
    });

    tearDown(() async {
      await db.close();
    });

    ProviderContainer createContainer() {
      return ProviderContainer(
        overrides: [
          settingsServiceProvider.overrideWithValue(settingsService),
          dbServiceProvider.overrideWithValue(db),
        ],
      );
    }

    test('loads local defaults when no settings exist', () async {
      final container = createContainer();
      addTearDown(container.dispose);

      final settings = await container.read(appSettingsProvider.future);

      expect(settings.profile.displayName, isEmpty);
      expect(settings.preferredWhisperModel, WhisperModel.base);
      expect(settings.summaryMethod, AppSummaryMethod.extractive);
      expect(settings.lectureLabels, AppSettings.defaultLectureLabels);
      expect(settings.timelineLabels, AppSettings.defaultTimelineLabels);
      expect(settings.backgroundStyle, AppBackgroundStyle.darkDefault);
    });

    test(
        'persists profile, model, summary method, labels, and background style',
        () async {
      final container = createContainer();
      addTearDown(container.dispose);
      await container.read(appSettingsProvider.future);

      final notifier = container.read(appSettingsProvider.notifier);
      await notifier.updateProfile(
        displayName: '林雨晴',
        organization: 'NTU / HCI Lab',
        note: '偏好精簡摘要',
      );
      await notifier.updatePreferredWhisperModel(WhisperModel.small);
      await notifier.updateSummaryMethod(AppSummaryMethod.androidLocalLlm);
      await notifier.addLectureLabel('專題');
      await notifier.addTimelineLabel('問答');
      await notifier.updateBackgroundStyle(AppBackgroundStyle.white);

      expect(
        await settingsService.getValue(AppSettingsKeys.profileDisplayName),
        '林雨晴',
      );
      expect(
        await settingsService.getValue(AppSettingsKeys.preferredWhisperModel),
        'small',
      );
      expect(
        await settingsService.getValue(AppSettingsKeys.summaryMethod),
        AppSummaryMethod.androidLocalLlm.storageValue,
      );
      expect(
        await settingsService.getValue(AppSettingsKeys.backgroundStyle),
        AppBackgroundStyle.white.storageValue,
      );

      final storedLectureLabels = jsonDecode(
        (await settingsService.getValue(AppSettingsKeys.lectureLabels))!,
      ) as List<dynamic>;
      final storedTimelineLabels = jsonDecode(
        (await settingsService.getValue(AppSettingsKeys.timelineLabels))!,
      ) as List<dynamic>;

      expect(storedLectureLabels, contains('專題'));
      expect(storedTimelineLabels, contains('問答'));

      final reloadedContainer = createContainer();
      addTearDown(reloadedContainer.dispose);

      final reloadedSettings =
          await reloadedContainer.read(appSettingsProvider.future);

      expect(reloadedSettings.profile.displayName, '林雨晴');
      expect(reloadedSettings.profile.organization, 'NTU / HCI Lab');
      expect(reloadedSettings.profile.note, '偏好精簡摘要');
      expect(reloadedSettings.preferredWhisperModel, WhisperModel.small);
      expect(
        reloadedSettings.summaryMethod,
        AppSummaryMethod.androidLocalLlm,
      );
      expect(reloadedSettings.lectureLabels, contains('專題'));
      expect(reloadedSettings.timelineLabels, contains('問答'));
      expect(reloadedSettings.backgroundStyle, AppBackgroundStyle.white);
    });

    test('updateLectureLabel 應替換現有標籤名稱並更新資料庫課程', () async {
      final container = createContainer();
      addTearDown(container.dispose);
      final notifier = container.read(appSettingsProvider.notifier);
      await container.read(appSettingsProvider.future);

      // 1. 建立一個帶有舊標籤的課程
      await db.insertLecture(Lecture(
        title: '測試課程',
        date: DateTime.now().toIso8601String(),
        audioPath: 'test.m4a',
        tags: ['舊標籤'],
      ));

      // 2. 執行標籤重新命名
      await notifier.addLectureLabel('舊標籤');
      await notifier.updateLectureLabel('舊標籤', '新標籤');

      // 3. 驗證設定檔
      final settings = await container.read(appSettingsProvider.future);
      expect(settings.lectureLabels, contains('新標籤'));
      expect(settings.lectureLabels, isNot(contains('舊標籤')));

      // 4. 驗證資料庫課程標籤已同步
      final lectures = await db.getAllLectures();
      expect(lectures.first.tags, contains('新標籤'));
    });
  });
}
