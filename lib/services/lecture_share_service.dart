import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/lecture.dart';
import '../utils/format_utils.dart';
import 'db_service.dart';

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
      throw LectureShareException(
        error.message ?? '無法開啟分享面板，請稍後再試。',
      );
    }
  }
}

class LectureShareService {
  LectureShareService({
    DbService? dbService,
    LectureShareGateway? gateway,
    Future<Directory> Function()? temporaryDirectory,
  })  : _dbService = dbService ?? DbService(),
        _gateway = gateway ?? MethodChannelLectureShareGateway(),
        _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory;

  final DbService _dbService;
  final LectureShareGateway _gateway;
  final Future<Directory> Function() _temporaryDirectory;

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
    if (!includeAudio && !includeNotes) {
      throw const LectureShareException('請至少選擇一種匯出內容。');
    }

    final filePaths = <String>[];

    if (includeAudio) {
      final audioFile = await _dbService.resolveAudioFile(lecture);
      if (!await audioFile.exists()) {
        throw const LectureShareException('找不到這堂課的音檔，無法分享。');
      }
      filePaths.add(audioFile.path);
    }

    if (includeNotes) {
      final exportFile = await _writeNotesExport(lecture);
      filePaths.add(exportFile.path);
    }

    if (filePaths.isEmpty) {
      throw const LectureShareException('沒有可匯出的內容。');
    }

    return LectureSharePayload(
      subject: lecture.title.trim().isEmpty ? 'LectureVault 匯出' : lecture.title,
      text: _buildShareMessage(lecture, includeAudio: includeAudio),
      filePaths: List.unmodifiable(filePaths),
    );
  }

  Future<File> _writeNotesExport(Lecture lecture) async {
    final directory = await _temporaryDirectory();
    await directory.create(recursive: true);

    final safeStem = _sanitizeFileName(lecture.title);
    final file = File(
      p.join(directory.path,
          '${safeStem.isEmpty ? 'lecture_vault' : safeStem}_notes.txt'),
    );

    await file.writeAsString(_buildNotesDocument(lecture));
    return file;
  }

  String _buildShareMessage(Lecture lecture, {required bool includeAudio}) {
    final summary = lecture.summary.trim();
    final label = lecture.tag.trim();
    final parts = <String>[
      lecture.title.trim().isEmpty ? 'LectureVault 匯出' : lecture.title.trim(),
      if (label.isNotEmpty) '標籤：$label',
      if (summary.isNotEmpty) summary,
      if (summary.isEmpty && lecture.transcript.trim().isNotEmpty)
        '已附上逐字稿與摘要文字檔。',
      if (includeAudio) '含原始音檔。',
    ];
    return parts.join('\n');
  }

  String _buildNotesDocument(Lecture lecture) {
    final buffer = StringBuffer()
      ..writeln(
          lecture.title.trim().isEmpty ? 'LectureVault 匯出' : lecture.title)
      ..writeln(
          '日期：${lecture.date.trim().isEmpty ? '未提供' : lecture.date.trim()}')
      ..writeln('時長：${FormatUtils.formatDuration(lecture.durationSeconds)}');

    if (lecture.tag.trim().isNotEmpty) {
      buffer.writeln('課程標籤：${lecture.tag.trim()}');
    }

    buffer
      ..writeln()
      ..writeln('【摘要】')
      ..writeln(
          lecture.summary.trim().isEmpty ? '尚無摘要。' : lecture.summary.trim())
      ..writeln();

    if (lecture.timeline.isNotEmpty) {
      buffer.writeln('【時間軸】');
      for (final entry in lecture.timeline) {
        final timestamp = _formatTimelineTime(entry.startMs);
        final label = entry.label == null || entry.label!.trim().isEmpty
            ? ''
            : ' [${entry.label!.trim()}]';
        buffer.writeln('- $timestamp$label ${entry.text.trim()}');
      }
      buffer.writeln();
    }

    buffer
      ..writeln('【逐字稿】')
      ..writeln(lecture.transcript.trim().isEmpty
          ? '尚無逐字稿。'
          : lecture.transcript.trim());

    return buffer.toString().trimRight();
  }

  String _formatTimelineTime(int startMs) {
    final totalSeconds = (startMs / 1000).floor();
    final h = (totalSeconds ~/ 3600).toString().padLeft(2, '0');
    final m = ((totalSeconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String _sanitizeFileName(String raw) {
    return raw
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_')
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }
}
