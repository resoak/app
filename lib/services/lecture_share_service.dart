import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/lecture.dart';
import '../utils/format_utils.dart';
import 'db_service.dart';

typedef TemporaryDirectoryProvider = Future<Directory> Function();

class LectureShareException implements Exception {
  const LectureShareException(this.message);
  final String message;
  @override
  String toString() => message;
}

class LectureSharePayload {
  const LectureSharePayload({
    required this.subject,
    required this.text,
    required this.filePaths,
  });
  final String subject;
  final String text;
  final List<String> filePaths;

  Map<String, Object?> toMap() {
    return {
      'subject': subject,
      'text': text,
      'filePaths': filePaths,
    };
  }
}

abstract class LectureShareGateway {
  Future<void> share(LectureSharePayload payload);
}

class MethodChannelLectureShareGateway implements LectureShareGateway {
  static const MethodChannel _channel = MethodChannel('lecture_vault/share');
  @override
  Future<void> share(LectureSharePayload payload) async {
    try {
      await _channel.invokeMethod<void>('shareFiles', payload.toMap());
    } on MissingPluginException {
      throw const LectureShareException('此裝置目前不支援系統分享。');
    } on PlatformException catch (error) {
      throw LectureShareException(error.message ?? '無法開啟分享面板。');
    }
  }
}

class LectureShareService {
  LectureShareService({
    DbService? dbService,
    LectureShareGateway? gateway,
    TemporaryDirectoryProvider? temporaryDirectory,
  })  : _dbService = dbService ?? DbService(),
        _gateway = gateway ?? MethodChannelLectureShareGateway(),
        _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory;

  final DbService _dbService;
  final LectureShareGateway _gateway;
  final TemporaryDirectoryProvider _temporaryDirectory;

  Future<void> shareLectureBundle(Lecture lecture) async {
    final payload = await buildSharePayload(
      lecture,
      includeAudio: true,
      includeNotes: true,
    );
    await _gateway.share(payload);
  }

  Future<void> shareLectureNotes(Lecture lecture) async {
    final payload = await buildSharePayload(
      lecture,
      includeAudio: false,
      includeNotes: true,
    );
    await _gateway.share(payload);
  }

  Future<LectureSharePayload> buildSharePayload(
    Lecture lecture, {
    required bool includeAudio,
    required bool includeNotes,
  }) async {
    final filePaths = <String>[];
    final cacheDir = await _temporaryDirectory();

    if (includeAudio) {
      final audioFile = await _dbService.resolveSafeAudioFile(lecture);
      if (!await audioFile.exists()) {
        throw const LectureShareException('找不到這堂課的音檔，無法建立分享包。');
      }

      // 強制將音檔複製到 Cache 目錄，避免 FileProvider 權限問題。
      final tempAudioPath = p.join(
        cacheDir.path,
        'share_${p.basename(audioFile.path)}',
      );
      final tempFile = await audioFile.copy(tempAudioPath);
      filePaths.add(tempFile.path);
    }

    if (includeNotes) {
      final notesFile = File(
        p.join(cacheDir.path, '${_sanitizeFileName(lecture.title)}_notes.txt'),
      );
      await notesFile.writeAsString(_buildNotesDocument(lecture));
      filePaths.add(notesFile.path);
    }

    return LectureSharePayload(
      subject: lecture.title.isEmpty ? 'LectureVault 匯出' : lecture.title,
      text: _buildShareMessage(
        lecture,
        includeAudio: includeAudio,
        includeNotes: includeNotes,
      ),
      filePaths: filePaths,
    );
  }

  String _buildShareMessage(
    Lecture lecture, {
    required bool includeAudio,
    required bool includeNotes,
  }) {
    final lines = <String>[
      lecture.title.isEmpty ? 'LectureVault 匯出' : lecture.title,
    ];
    final summary = lecture.summary.trim();
    if (summary.isNotEmpty) {
      lines.add(summary);
    }
    if (includeAudio) {
      lines.add('含原始音檔。');
    }
    if (includeNotes) {
      lines.add('已附上逐字稿與摘要文字檔。');
    }
    return lines.join('\n');
  }

  String _buildNotesDocument(Lecture lecture) {
    final buffer = StringBuffer()
      ..writeln(lecture.title.isEmpty ? '未命名課程' : lecture.title)
      ..writeln()
      ..writeln('日期：${lecture.date}');

    if (lecture.durationSeconds > 0) {
      buffer
          .writeln('長度：${FormatUtils.formatDuration(lecture.durationSeconds)}');
    }
    final tags =
        lecture.tags.map((tag) => tag.trim()).where((tag) => tag.isNotEmpty);
    if (tags.isNotEmpty) {
      buffer.writeln('課程標籤：${tags.join('、')}');
    }

    if (lecture.timeline.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('【時間軸】');
      for (final entry in lecture.timeline) {
        final labels = entry.labels
            .map((label) => label.trim())
            .where((label) => label.isNotEmpty)
            .join('、');
        final labelText = labels.isEmpty ? '' : ' [$labels]';
        buffer.writeln(
          '${_formatTimelineTimestamp(entry.startMs)}$labelText ${entry.text}',
        );
      }
    }

    buffer
      ..writeln()
      ..writeln('【摘要】')
      ..writeln(
          lecture.summary.trim().isEmpty ? '（無摘要）' : lecture.summary.trim())
      ..writeln()
      ..writeln('【逐字稿】')
      ..write(lecture.transcript.trim().isEmpty
          ? '（無逐字稿）'
          : lecture.transcript.trim());

    return buffer.toString();
  }

  String _formatTimelineTimestamp(int milliseconds) {
    final totalSeconds = milliseconds ~/ 1000;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  String _sanitizeFileName(String raw) {
    final sanitized = raw.replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_').trim();
    return sanitized.isEmpty ? 'lecture_vault' : sanitized;
  }
}
