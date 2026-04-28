import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_vault/models/lecture.dart';
import 'package:lecture_vault/services/db_service.dart';
import 'package:lecture_vault/services/lecture_share_service.dart';

class _FakeLectureShareGateway implements LectureShareGateway {
  LectureSharePayload? lastPayload;

  @override
  Future<void> share(LectureSharePayload payload) async {
    lastPayload = payload;
  }
}

void main() {
  group('LectureShareService', () {
    late Directory tempDir;
    late DbService dbService;
    late _FakeLectureShareGateway gateway;
    late LectureShareService service;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('lecture_share_service');
      dbService = DbService(documentsDirectory: () async => tempDir);
      gateway = _FakeLectureShareGateway();
      service = LectureShareService(
        dbService: dbService,
        gateway: gateway,
        temporaryDirectory: () async => tempDir,
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    Future<Lecture> createLectureWithManagedAudio() async {
      final audioFile = File(
        '${tempDir.path}${Platform.pathSeparator}media${Platform.pathSeparator}audio${Platform.pathSeparator}lecture.m4a',
      );
      await audioFile.parent.create(recursive: true);
      await audioFile.writeAsBytes(const [1, 2, 3, 4]);

      return Lecture(
        title: '演算法總複習',
        date: '2026.04.22',
        audioPath: '/legacy/audio.m4a',
        managedAudioPath: 'media/audio/lecture.m4a',
        transcript: '第一段逐字稿。第二段逐字稿。',
        summary: '整理遞迴、排序與圖論的核心觀念。',
        durationSeconds: 95,
        tag: '考試',
        timeline: [
          const LectureTimelineEntry(
            text: '老師先回顧遞迴觀念',
            startMs: 15000,
            endMs: 28000,
            label: '重點',
          ),
        ],
      );
    }

    test('shareLectureBundle includes audio file and generated note export',
        () async {
      final lecture = await createLectureWithManagedAudio();

      await service.shareLectureBundle(lecture);

      final payload = gateway.lastPayload;
      expect(payload, isNotNull);
      expect(payload!.subject, equals('演算法總複習'));
      expect(payload.filePaths, hasLength(2));
      expect(payload.text, contains('含原始音檔'));

      final notePath = payload.filePaths.firstWhere(
        (path) => path.endsWith('_notes.txt'),
      );
      final noteText = await File(notePath).readAsString();

      expect(noteText, contains('課程標籤：考試'));
      expect(noteText, contains('【摘要】'));
      expect(noteText, contains('整理遞迴、排序與圖論的核心觀念。'));
      expect(noteText, contains('00:00:15 [重點] 老師先回顧遞迴觀念'));
      expect(noteText, contains('【逐字稿】'));
    });

    test('shareLectureNotes exports text package without requiring audio',
        () async {
      final lecture = Lecture(
        title: '僅文字匯出',
        date: '2026.04.22',
        audioPath: '/missing/audio.m4a',
        transcript: '只需要分享這份文字。',
        summary: '',
      );

      await service.shareLectureNotes(lecture);

      final payload = gateway.lastPayload;
      expect(payload, isNotNull);
      expect(payload!.filePaths, hasLength(1));
      expect(payload.filePaths.single, endsWith('_notes.txt'));
      expect(payload.text, contains('已附上逐字稿與摘要文字檔。'));
    });

    test('shareLectureBundle throws when managed audio file is missing',
        () async {
      final lecture = Lecture(
        title: '找不到音檔',
        date: '2026.04.22',
        audioPath: '/legacy/missing.m4a',
        managedAudioPath: 'media/audio/missing.m4a',
      );

      await expectLater(
        service.shareLectureBundle(lecture),
        throwsA(
          isA<LectureShareException>().having(
            (error) => error.message,
            'message',
            contains('找不到這堂課的音檔'),
          ),
        ),
      );
    });
  });
}
