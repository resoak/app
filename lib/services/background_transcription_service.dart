import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';

import '../models/lecture.dart';
import 'db_service.dart';
import 'summary_service.dart';
import 'stt_service.dart';
import 'minilm_runtime_service.dart';

typedef SttServiceFactory = SttService Function(WhisperModel whisperModel);

class BackgroundTranscriptionService {
  BackgroundTranscriptionService({
    DbService? dbService,
    SummaryService? summaryService,
    SttServiceFactory? sttServiceFactory,
    SentenceEmbeddingRuntime? embeddingService,
  })  : _dbService = dbService ?? DbService(),
        _summaryService = summaryService ?? const MiniLmSummaryService(),
        _embeddingService = embeddingService ?? const MiniLmRuntimeService(),
        _sttServiceFactory = sttServiceFactory ??
            ((whisperModel) => SttService(whisperModel: whisperModel));

  final DbService _dbService;
  final SummaryService _summaryService;
  final SttServiceFactory _sttServiceFactory;
  final SentenceEmbeddingRuntime _embeddingService;

  Future<void> transcribeLecture(
    Lecture lecture, {
    WhisperModel whisperModel = WhisperModel.base,
  }) async {
    final sttService = _sttServiceFactory(whisperModel);
    final currentLecture = lecture.copyWith(
      transcriptionStatus: LectureProcessingStatus.processing,
      summaryStatus: LectureProcessingStatus.pending,
      summary: '',
    );

    try {
      if (currentLecture.id != null) {
        await _dbService.updateLecture(currentLecture);
      }

      final audioPath = await _dbService.resolveSafeAudioPath(currentLecture);

      final audioFile = File(audioPath);
      if (!await audioFile.exists()) {
        throw FileSystemException('找不到音檔，無法開始轉錄', audioPath);
      }

      debugPrint('開始轉錄音檔: $audioPath');
      await sttService.transcribeFile(audioPath);

      final transcript = sttService.persistedTranscript;
      final timeline = sttService.timeline;

      if (transcript.trim().isEmpty) {
        throw StateError('無法辨識此音檔內容，請確認音量或嘗試使用 WAV 格式。');
      }

      var transcribedLecture = currentLecture.copyWith(
        transcript: transcript,
        timeline: timeline,
        transcriptionStatus: LectureProcessingStatus.completed,
        summaryStatus: LectureProcessingStatus.processing,
      );

      // 產生摘要
      try {
        debugPrint('開始產生 AI 摘要...');
        final summary = await _summaryService.summarizeTranscript(transcript);
        transcribedLecture = transcribedLecture.copyWith(
          summary: summary.isNotEmpty ? summary : 'AI 分析完成，無顯著重點。',
          summaryStatus: LectureProcessingStatus.completed,
        );
      } catch (e) {
        debugPrint('摘要失敗: $e');
        transcribedLecture = transcribedLecture.copyWith(
          summary: '摘要整理發生錯誤。',
          summaryStatus: LectureProcessingStatus.failed,
        );
      }

      // [新增] 產生語義向量 (Embedding) 與自動標籤建議
      try {
        debugPrint('開始產生語義向量...');
        // 使用標題 + 摘要 + 前 500 字轉錄內容作為語義特徵
        final contentForEmbedding =
            '${transcribedLecture.title}\n${transcribedLecture.summary}\n${transcript.take(500)}';
        final embeddings =
            await _embeddingService.embedSentences([contentForEmbedding]);
        if (embeddings.isNotEmpty) {
          final vector = embeddings.first;
          transcribedLecture = transcribedLecture.copyWith(embedding: vector);

          // 透過語義相似度建議標籤
          final suggestedTags = await _suggestTags(
            vector,
            excludeId: transcribedLecture.id,
          );
          if (suggestedTags.isNotEmpty) {
            // 合併現有標籤與建議標籤，移除重複並排除預設的「一般」
            final currentTags =
                transcribedLecture.tags.where((t) => t != '一般').toSet();
            final mergedTags = (currentTags..addAll(suggestedTags)).toList();

            // 若完全沒有標籤，則保留「一般」；若有具體標籤，則取代之
            transcribedLecture = transcribedLecture.copyWith(
              tags: mergedTags.isEmpty ? const ['一般'] : mergedTags,
            );
            debugPrint('自動建議標籤: $suggestedTags');
          }
        }
      } catch (e) {
        debugPrint('向量生成或標籤建議失敗: $e');
      }

      await _dbService.updateLecture(transcribedLecture);
    } catch (e) {
      debugPrint('Transcription Error: $e');
      await _dbService.updateLecture(
        currentLecture.copyWith(
          transcript: '',
          summary: '處理失敗：${e.toString()}',
          transcriptionStatus: LectureProcessingStatus.failed,
          summaryStatus: LectureProcessingStatus.failed,
        ),
      );
      rethrow;
    } finally {
      sttService.dispose();
    }
  }

  /// 根據向量尋找相似課程並提取高頻標籤
  Future<List<String>> _suggestTags(List<double> embedding,
      {int? excludeId}) async {
    try {
      // 門檻值設為 0.5 以確保語義相關性
      final similarLectures = await _dbService.searchLecturesBySimilarity(
        embedding,
        threshold: 0.5,
      );

      final tagCounts = <String, int>{};
      for (final lecture in similarLectures) {
        if (lecture.id == excludeId) continue;
        for (final tag in lecture.tags) {
          if (tag == '一般') continue;
          tagCounts[tag] = (tagCounts[tag] ?? 0) + 1;
        }
      }

      if (tagCounts.isEmpty) return const [];

      // 依頻率排序，取前 3 名
      final sortedEntries = tagCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      return sortedEntries.take(3).map((e) => e.key).toList();
    } catch (e) {
      debugPrint('建議標籤計算出錯: $e');
      return const [];
    }
  }
}

extension on String {
  String take(int n) => length <= n ? this : substring(0, n);
}
