import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_vault/models/app_setting.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:lecture_vault/models/lecture.dart';
import 'package:lecture_vault/services/db_service.dart';
import 'package:lecture_vault/services/settings_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('DbService CRUD', () {
    late DbService db;

    setUp(() async {
      db = DbService();
      await db.resetForTests();
    });

    tearDown(() async {
      await db.close();
    });

    Lecture makeLecture({String title = '測試講座'}) => Lecture(
          title: title,
          date: DateTime(2026, 3, 9).toIso8601String(),
          audioPath: '/fake/path/audio.m4a',
          transcript: '',
          summary: '',
          durationSeconds: 0,
          tags: ['一般'],
        );

    test('insertLecture 會為新資料補上穩定 uid', () async {
      final id = await db.insertLecture(makeLecture());
      final lecture = await db.getLectureById(id);

      expect(lecture, isNotNull);
      expect(lecture!.uid, isNotEmpty);
      expect(lecture.uid, startsWith('lec_'));
    });

    test('insertLecture 回傳大於 0 的 id', () async {
      final id = await db.insertLecture(makeLecture());
      expect(id, greaterThan(0));
    });

    test('getAllLectures 可以讀取剛插入的資料', () async {
      await db.insertLecture(makeLecture(title: '第一講'));
      await db.insertLecture(makeLecture(title: '第二講'));
      final lectures = await db.getAllLectures();
      expect(lectures.any((l) => l.title == '第一講'), isTrue);
    });

    test('updateLecture 可以更新 transcript 與自訂標籤', () async {
      final id = await db.insertLecture(makeLecture());
      final lectures = await db.getAllLectures();
      final lecture = lectures.firstWhere((l) => l.id == id);
      final updated = Lecture(
        id: lecture.id,
        uid: lecture.uid,
        title: lecture.title,
        date: lecture.date,
        audioPath: lecture.audioPath,
        managedAudioPath: 'media/audio/audio.m4a',
        transcript: '這是更新後的轉錄內容',
        summary: '這是摘要',
        transcriptionStatus: LectureProcessingStatus.completed,
        summaryStatus: LectureProcessingStatus.completed,
        durationSeconds: lecture.durationSeconds,
        tags: ['考試'],
        timeline: const [
          LectureTimelineEntry(
            text: '重點一',
            startMs: 1000,
            endMs: 2400,
            labels: ['開場'],
          ),
        ],
      );
      await db.updateLecture(updated);
      final all = await db.getAllLectures();
      final result = all.firstWhere((l) => l.id == id);
      expect(result.transcript, equals('這是更新後的轉錄內容'));
      expect(result.summary, equals('這是摘要'));
      expect(result.managedAudioPath, equals('media/audio/audio.m4a'));
      expect(
        result.transcriptionStatus,
        equals(LectureProcessingStatus.completed),
      );
      expect(result.summaryStatus, equals(LectureProcessingStatus.completed));
      expect(result.tags, contains('考試'));
      expect(result.timeline, hasLength(1));
      expect(result.timeline.first.text, equals('重點一'));
      expect(result.timeline.first.labels, contains('開場'));
    });

    test('deleteLecture 刪除後查不到', () async {
      final id = await db.insertLecture(makeLecture(title: '要刪除的'));
      final lecture = (await db.getLectureById(id))!;
      await db.deleteLecture(lecture);
      final all = await db.getAllLectures();
      expect(all.any((l) => l.id == id), isFalse);
    });

    test('deleteLecture 先刪除資料列再清理受管音檔', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('lecture_vault_delete_');
      final customDb = DbService(documentsDirectory: () async => tempDir);
      await customDb.resetForTests();

      final managedAudioFile = File(
        '${tempDir.path}${Platform.pathSeparator}media${Platform.pathSeparator}audio${Platform.pathSeparator}managed.m4a',
      );
      await managedAudioFile.parent.create(recursive: true);
      await managedAudioFile.writeAsBytes(const [1, 2, 3]);

      final id = await customDb.insertLecture(
        Lecture(
          title: '受管音檔刪除',
          date: DateTime(2026, 3, 9).toIso8601String(),
          audioPath: '/legacy/managed.m4a',
          managedAudioPath: 'media/audio/managed.m4a',
          transcript: '',
          summary: '',
          durationSeconds: 0,
          tags: ['一般'],
        ),
      );

      final lecture = (await customDb.getLectureById(id))!;
      await customDb.deleteLecture(lecture);

      expect(await customDb.getLectureById(id), isNull);
      expect(await managedAudioFile.exists(), isFalse);

      await customDb.close();
      await tempDir.delete(recursive: true);
    });

    test('deleteLecture 在音檔已不存在時仍安全完成', () async {
      final tempDir = await Directory.systemTemp
          .createTemp('lecture_vault_missing_delete_');
      final customDb = DbService(documentsDirectory: () async => tempDir);
      await customDb.resetForTests();

      final id = await customDb.insertLecture(
        Lecture(
          title: '遺失音檔',
          date: DateTime(2026, 3, 9).toIso8601String(),
          audioPath: '/legacy/missing.m4a',
          managedAudioPath: 'media/audio/missing.m4a',
          transcript: '',
          summary: '',
          durationSeconds: 0,
          tags: ['一般'],
        ),
      );

      final lecture = (await customDb.getLectureById(id))!;
      await customDb.deleteLecture(lecture);

      expect(await customDb.getLectureById(id), isNull);

      await customDb.close();
      await tempDir.delete(recursive: true);
    });

    test('deleteLecture 不會刪除受管目錄外的舊版絕對音檔', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('lecture_vault_legacy_delete_');
      final externalDir =
          await Directory.systemTemp.createTemp('lecture_vault_external_');
      final customDb = DbService(documentsDirectory: () async => tempDir);
      await customDb.resetForTests();

      final externalAudio = File(
        '${externalDir.path}${Platform.pathSeparator}legacy.m4a',
      );
      await externalAudio.writeAsBytes(const [4, 5, 6]);

      final id = await customDb.insertLecture(
        Lecture(
          title: '舊版外部音檔',
          date: DateTime(2026, 3, 9).toIso8601String(),
          audioPath: externalAudio.path,
          transcript: '',
          summary: '',
          durationSeconds: 0,
          tags: ['一般'],
        ),
      );

      final lecture = (await customDb.getLectureById(id))!;
      await customDb.deleteLecture(lecture);

      expect(await customDb.getLectureById(id), isNull);
      expect(await externalAudio.exists(), isTrue);

      await customDb.close();
      await tempDir.delete(recursive: true);
      await externalDir.delete(recursive: true);
    });

    test('updateLectureTag 應正確更新所有關聯課程的標籤', () async {
      await db
          .insertLecture(makeLecture(title: '課程 1').copyWith(tags: ['舊標籤']));
      await db
          .insertLecture(makeLecture(title: '課程 2').copyWith(tags: ['舊標籤']));
      await db
          .insertLecture(makeLecture(title: '課程 3').copyWith(tags: ['其他標籤']));

      await db.updateLectureTag('舊標籤', '新標籤');

      final all = await db.getAllLectures();
      final updated = all.where((l) => l.tags.contains('新標籤')).toList();
      final remaining = all.where((l) => l.tags.contains('舊標籤')).toList();
      final unaffected = all.where((l) => l.tags.contains('其他標籤')).toList();

      expect(updated.length, 2);
      expect(remaining.length, 0);
      expect(unaffected.length, 1);
    });

    test('notifyExternalDataMutation 會發出資料變更事件', () async {
      final changeFuture = db.changes.first;

      db.notifyExternalDataMutation();

      await expectLater(changeFuture, completes);
    });

    test('getAllLectures 可略過 embedding 解碼以加速列表查詢', () async {
      await db.insertLecture(
        makeLecture(title: '向量課程').copyWith(embedding: const [1.0, 0.0]),
      );

      final lightweight = await db.getAllLectures(includeEmbeddings: false);
      final full = await db.getAllLectures();

      expect(lightweight.single.embedding, isNull);
      expect(full.single.embedding, equals([1.0, 0.0]));
    });

    test('searchLecturesBySimilarity 只回傳達門檻且依相似度排序的課程', () async {
      await db.insertLecture(
        makeLecture(title: '高度相關').copyWith(embedding: const [1.0, 0.0]),
      );
      await db.insertLecture(
        makeLecture(title: '部分相關').copyWith(embedding: const [0.6, 0.4]),
      );
      await db.insertLecture(
        makeLecture(title: '沒有向量'),
      );

      final results = await db.searchLecturesBySimilarity(
        const [1.0, 0.0],
        threshold: 0.5,
      );

      expect(results.map((lecture) => lecture.title), [
        '高度相關',
        '部分相關',
      ]);
    });

    test('getManagedAudioPaths 只讀取受管音檔相對路徑', () async {
      await db.insertLecture(
        makeLecture(title: '受管音檔').copyWith(
          managedAudioPath: 'media/audio/one.wav',
        ),
      );
      await db.insertLecture(makeLecture(title: '舊版外部音檔'));

      final paths = await db.getManagedAudioPaths();

      expect(paths, equals({'media/audio/one.wav'}));
    });

    test('getAllLectures 回傳正確型別', () async {
      final lectures = await db.getAllLectures();
      expect(lectures, isA<List<Lecture>>());
    });

    test('resolveAudioPath 優先使用受管相對路徑', () async {
      final tempDir = await Directory.systemTemp.createTemp('lecture_vault');
      final customDb = DbService(documentsDirectory: () async => tempDir);
      final lecture = Lecture(
        title: '路徑測試',
        date: '2026.03.09',
        audioPath: '/legacy/audio.wav',
        managedAudioPath: 'media/audio/test.wav',
      );

      final resolvedPath = await customDb.resolveAudioPath(lecture);

      expect(
        resolvedPath,
        endsWith(
            '${Platform.pathSeparator}media${Platform.pathSeparator}audio${Platform.pathSeparator}test.wav'),
      );

      await tempDir.delete(recursive: true);
    });

    test('resolveAudioPath 允許受管目錄內的舊版絕對 audioPath', () async {
      final tempDir = await Directory.systemTemp.createTemp('lecture_vault');
      final customDb = DbService(documentsDirectory: () async => tempDir);
      final managedAbsolutePath =
          '${tempDir.path}${Platform.pathSeparator}media${Platform.pathSeparator}audio${Platform.pathSeparator}legacy.wav';
      final lecture = Lecture(
        title: '舊版音檔',
        date: '2026.03.09',
        audioPath: managedAbsolutePath,
      );

      final resolvedPath = await customDb.resolveAudioPath(lecture);

      expect(resolvedPath, equals(managedAbsolutePath));

      await tempDir.delete(recursive: true);
    });

    test('resolveAudioPath 保留舊版絕對 audioPath', () async {
      final lecture = Lecture(
        title: '舊版外部音檔',
        date: '2026.03.09',
        audioPath: '/legacy/audio.wav',
      );

      final resolvedPath = await db.resolveAudioPath(lecture);

      expect(resolvedPath, equals('/legacy/audio.wav'));
    });

    test('resolveSafeAudioPath 允許受管目錄內的舊版絕對 audioPath', () async {
      final tempDir = await Directory.systemTemp.createTemp('lecture_vault');
      final customDb = DbService(documentsDirectory: () async => tempDir);
      final managedAbsolutePath =
          '${tempDir.path}${Platform.pathSeparator}media${Platform.pathSeparator}audio${Platform.pathSeparator}legacy.wav';
      final lecture = Lecture(
        title: '舊版受管音檔',
        date: '2026.03.09',
        audioPath: managedAbsolutePath,
      );

      final resolvedPath = await customDb.resolveSafeAudioPath(lecture);

      expect(resolvedPath, equals(managedAbsolutePath));

      await tempDir.delete(recursive: true);
    });

    test('resolveSafeAudioPath 拒絕受管目錄外的舊版絕對 audioPath', () async {
      final tempDir = await Directory.systemTemp.createTemp('lecture_vault');
      final customDb = DbService(documentsDirectory: () async => tempDir);
      final lecture = Lecture(
        title: '舊版外部音檔',
        date: '2026.03.09',
        audioPath: '/legacy/audio.wav',
      );

      await expectLater(
        customDb.resolveSafeAudioPath(lecture),
        throwsA(isA<StateError>()),
      );

      await tempDir.delete(recursive: true);
    });
  });

  group('DbService migration safety', () {
    late DbService db;

    setUp(() async {
      db = DbService();
      await db.resetForTests();
    });

    tearDown(() async {
      await db.close();
    });

    test('version 3 rows migrate without losing readability', () async {
      final dbPath = await getDatabasesPath();
      final legacyDatabase = await openDatabase(
        '$dbPath${Platform.pathSeparator}lecture_vault.db',
        version: 3,
        onCreate: (database, version) async {
          await database.execute('''
            CREATE TABLE lectures (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              title TEXT NOT NULL,
              date TEXT NOT NULL,
              audioPath TEXT NOT NULL,
              transcript TEXT DEFAULT '',
              summary TEXT DEFAULT '',
              durationSeconds INTEGER DEFAULT 0,
              tag TEXT DEFAULT '',
              timelineJson TEXT DEFAULT ''
            )
          ''');
        },
      );

      await legacyDatabase.insert('lectures', {
        'title': '舊版資料',
        'date': '2026.03.09',
        'audioPath': '/legacy/audio.wav',
        'transcript': '',
        'summary': '背景轉錄中…',
        'durationSeconds': 42,
        'tag': '一般',
        'timelineJson': '[{"text":"第一段","startMs":0,"endMs":1200}]',
      });
      await legacyDatabase.close();

      final lectures = await db.getAllLectures();

      expect(lectures, hasLength(1));
      expect(lectures.first.uid, equals('legacy-1'));
      expect(
        lectures.first.transcriptionStatus,
        equals(LectureProcessingStatus.processing),
      );
      expect(
        lectures.first.summaryStatus,
        equals(LectureProcessingStatus.processing),
      );
      expect(lectures.first.audioPath, equals('/legacy/audio.wav'));
      expect(lectures.first.managedAudioPath, isEmpty);
      expect(lectures.first.timeline, hasLength(1));
      expect(lectures.first.timeline.first.labels, isEmpty);
    });
  });

  group('SettingsService CRUD', () {
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

    test('saveSetting and getSetting work', () async {
      await settingsService.saveSetting(
        const AppSetting(key: 'selectedWhisperModel', value: 'base'),
      );

      final setting = await settingsService.getSetting('selectedWhisperModel');

      expect(setting, isNotNull);
      expect(setting!.value, equals('base'));
    });

    test('saveSetting replaces existing values', () async {
      await settingsService.saveSetting(
        const AppSetting(key: 'selectedWhisperModel', value: 'base'),
      );
      await settingsService.saveSetting(
        const AppSetting(key: 'selectedWhisperModel', value: 'small'),
      );

      final value = await settingsService.getValue('selectedWhisperModel');

      expect(value, equals('small'));
    });

    test('deleteSetting removes persisted values', () async {
      await settingsService.saveSetting(
        const AppSetting(key: 'themeMode', value: 'dark'),
      );

      await settingsService.deleteSetting('themeMode');

      expect(await settingsService.getSetting('themeMode'), isNull);
    });

    test('getAllSettings returns stored key value entries', () async {
      await settingsService.saveSetting(
        const AppSetting(key: 'a', value: '1'),
      );
      await settingsService.saveSetting(
        const AppSetting(key: 'b', value: '2'),
      );

      final settings = await settingsService.getAllSettings();

      expect(settings.map((setting) => setting.key), equals(['a', 'b']));
    });
  });
}
