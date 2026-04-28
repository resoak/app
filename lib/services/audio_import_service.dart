import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/lecture.dart';
import 'db_service.dart';

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
  static const List<String> allowedExtensions = [
    'aac',
    'flac',
    'm4a',
    'mp3',
    'ogg',
    'opus',
    'wav',
    'webm',
  ];

  @override
  Future<SelectedAudioImport?> pickAudioFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: allowedExtensions,
      allowMultiple: false,
      withData: false,
    );

    if (result == null || result.files.isEmpty) {
      return null;
    }

    final pickedFile = result.files.single;
    final path = pickedFile.path;
    if (path == null || path.trim().isEmpty) {
      throw StateError('Selected audio file is missing a readable local path.');
    }

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
    Future<Directory> Function()? documentsDirectory,
    Random? random,
  })  : _dbService = dbService ?? DbService(),
        _picker = picker ?? FilePickerAudioImportPicker(),
        _documentsDirectory =
            documentsDirectory ?? getApplicationDocumentsDirectory,
        _random = random ?? Random.secure();

  static final String _managedAudioDirectory = p.join('media', 'audio');

  final DbService _dbService;
  final AudioImportPicker _picker;
  final Future<Directory> Function() _documentsDirectory;
  final Random _random;

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
    final normalizedSourcePath = sourcePath.trim();
    if (normalizedSourcePath.isEmpty) {
      throw ArgumentError.value(
          sourcePath, 'sourcePath', 'Source path is empty.');
    }

    final sourceFile = File(normalizedSourcePath);
    if (!await sourceFile.exists()) {
      throw FileSystemException(
        'Audio file does not exist.',
        normalizedSourcePath,
      );
    }

    final documentsDirectory = await _documentsDirectory();
    final extension = _resolveExtension(normalizedSourcePath, sourceName);
    final managedAudioPath = p.join(
      _managedAudioDirectory,
      'imp_${DateTime.now().millisecondsSinceEpoch}_${_randomSuffix()}$extension',
    );
    final destinationPath = p.join(documentsDirectory.path, managedAudioPath);

    await File(destinationPath).parent.create(recursive: true);
    await sourceFile.copy(destinationPath);

    final now = DateTime.now();
    final dateLabel =
        '${now.year}.${now.month.toString().padLeft(2, '0')}.${now.day.toString().padLeft(2, '0')}';
    final timeLabel =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    final draftLecture = Lecture(
      title: _buildLectureTitle(sourceName, dateLabel, timeLabel),
      date: dateLabel,
      audioPath: destinationPath,
      managedAudioPath: managedAudioPath,
      transcript: '',
      summary: '',
      transcriptionStatus: LectureProcessingStatus.processing,
      summaryStatus: LectureProcessingStatus.pending,
      durationSeconds: 0,
      tag: '一般',
      timeline: const [],
    );

    try {
      final id = await _dbService.insertLecture(draftLecture);
      return draftLecture.copyWith(id: id);
    } catch (_) {
      final destinationFile = File(destinationPath);
      if (await destinationFile.exists()) {
        await destinationFile.delete();
      }
      rethrow;
    }
  }

  String _resolveExtension(String sourcePath, String? sourceName) {
    final fromName = sourceName == null ? '' : p.extension(sourceName.trim());
    final fromPath = p.extension(sourcePath);
    final extension = fromName.isNotEmpty ? fromName : fromPath;
    return extension.isEmpty ? '.wav' : extension.toLowerCase();
  }

  String _buildLectureTitle(
    String? sourceName,
    String dateLabel,
    String timeLabel,
  ) {
    final fileStem = sourceName == null
        ? ''
        : p
            .basenameWithoutExtension(sourceName)
            .replaceAll(RegExp(r'[_\-]+'), ' ')
            .trim();
    if (fileStem.isNotEmpty) {
      return fileStem;
    }
    return '匯入音檔 $dateLabel $timeLabel';
  }

  String _randomSuffix() =>
      _random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0');
}
