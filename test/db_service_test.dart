import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:lecture_vault/services/db_service.dart';
import 'package:lecture_vault/models/lecture.dart';

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
          tag: '一般',
        );

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

    test('updateLecture 可以更新 transcript', () async {
      final id = await db.insertLecture(makeLecture());
      final lectures = await db.getAllLectures();
      final lecture = lectures.firstWhere((l) => l.id == id);
      final updated = Lecture(
        id: lecture.id,
        title: lecture.title,
        date: lecture.date,
        audioPath: lecture.audioPath,
        transcript: '這是更新後的轉錄內容',
        summary: lecture.summary,
        durationSeconds: lecture.durationSeconds,
        tag: lecture.tag,
        timeline: const [
          LectureTimelineEntry(text: '重點一', startMs: 1000, endMs: 2400),
        ],
      );
      await db.updateLecture(updated);
      final all = await db.getAllLectures();
      final result = all.firstWhere((l) => l.id == id);
      expect(result.transcript, equals('這是更新後的轉錄內容'));
      expect(result.timeline, hasLength(1));
      expect(result.timeline.first.text, equals('重點一'));
    });

    test('deleteLecture 刪除後查不到', () async {
      final id = await db.insertLecture(makeLecture(title: '要刪除的'));
      await db.deleteLecture(id);
      final all = await db.getAllLectures();
      expect(all.any((l) => l.id == id), isFalse);
    });

    test('getAllLectures 回傳正確型別', () async {
      final lectures = await db.getAllLectures();
      expect(lectures, isA<List<Lecture>>());
    });
  });
}
