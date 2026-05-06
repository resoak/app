import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/lecture.dart';
import 'audio_transcoding_service.dart';
import 'db_service.dart';

typedef DocumentsDirectoryProvider = Future<Directory> Function();
typedef LectureInserter = Future<int> Function(Lecture lecture);

class SelectedAudioImport {
  const SelectedAudioImport({
    required this.path,
    required this.name,
  });

  final String path;
  final String name;
}

abstract class AudioImportPicker {
  Future<SelectedAudioImport?> pickAudioFile();
}

class FilePickerAudioImportPicker implements AudioImportPicker {
  @override
  Future<SelectedAudioImport?> pickAudioFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: false,
    );

    if (result == null || result.files.isEmpty) return null;

    final pickedFile = result.files.single;
    final path = pickedFile.path;
    if (path == null) return null;

    return SelectedAudioImport(
      path: path,
      name: pickedFile.name,
    );
  }
}

class AudioImportService {
  AudioImportService({
    DbService? dbService,
    AudioImportPicker? picker,
    DocumentsDirectoryProvider? documentsDirectoryProvider,
    AudioTranscodingService? transcodingService,
    LectureInserter? lectureInserter,
  })  : _picker = picker ?? FilePickerAudioImportPicker(),
        _documentsDirectoryProvider =
            documentsDirectoryProvider ?? getApplicationDocumentsDirectory,
        _transcodingService = transcodingService ?? AudioTranscodingService(),
        _lectureInserter = lectureInserter ??
            ((lecture) => (dbService ?? DbService()).insertLecture(lecture));

  final AudioImportPicker _picker;
  final DocumentsDirectoryProvider _documentsDirectoryProvider;
  final AudioTranscodingService _transcodingService;
  final LectureInserter _lectureInserter;

  Future<Lecture?> pickAndImportLecture() async {
    final selection = await _picker.pickAudioFile();
    if (selection == null) return null;

    return importAudioLecture(
      sourcePath: selection.path,
      sourceName: selection.name,
    );
  }

  Future<Lecture> importAudioLecture({
    required String sourcePath,
    String? sourceName,
  }) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw FileSystemException('找不到來源音檔', sourcePath);
    }

    final durationSeconds =
        await _transcodingService.probeDurationSeconds(sourcePath);

    final docsDir = await _documentsDirectoryProvider();
    final managedRelativePath = p.join(
        'media', 'audio', 'imp_${DateTime.now().millisecondsSinceEpoch}.wav');
    final destinationPath = p.join(docsDir.path, managedRelativePath);

    await File(destinationPath).parent.create(recursive: true);

    await _transcodingService.convertToWhisperWav(
      sourcePath: sourcePath,
      destinationPath: destinationPath,
    );

    final now = DateTime.now();
    final dateLabel =
        '${now.year}.${now.month.toString().padLeft(2, '0')}.${now.day.toString().padLeft(2, '0')}';

    final lecture = Lecture(
      title: _buildLectureTitle(sourceName, dateLabel),
      date: dateLabel,
      audioPath: destinationPath,
      managedAudioPath: managedRelativePath,
      durationSeconds: durationSeconds,
      transcriptionStatus: LectureProcessingStatus.pending,
      summaryStatus: LectureProcessingStatus.pending,
      tags: ['匯入'],
      transcript: '',
      summary: '',
      timeline: [],
    );

    try {
      final id = await _lectureInserter(lecture);
      return lecture.copyWith(id: id);
    } catch (_) {
      final destinationFile = File(destinationPath);
      if (await destinationFile.exists()) {
        await destinationFile.delete();
      }
      rethrow;
    }
  }

  String _buildLectureTitle(String? sourceName, String dateLabel) {
    if (sourceName == null || sourceName.trim().isEmpty) {
      return '匯入音檔 $dateLabel';
    }

    final normalizedTitle = p.basenameWithoutExtension(sourceName).trim();
    if (normalizedTitle.isEmpty) {
      return '匯入音檔 $dateLabel';
    }

    return normalizedTitle;
  }
}
