import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

typedef BackgroundImageDocumentsDirectoryProvider = Future<Directory>
    Function();

class SelectedBackgroundImage {
  const SelectedBackgroundImage({
    required this.path,
    required this.name,
  });

  final String path;
  final String name;
}

abstract class BackgroundImagePicker {
  Future<SelectedBackgroundImage?> pickImageFile();
}

class FilePickerBackgroundImagePicker implements BackgroundImagePicker {
  @override
  Future<SelectedBackgroundImage?> pickImageFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) {
      return null;
    }

    final file = result.files.single;
    final path = file.path;
    if (path == null) {
      return null;
    }

    return SelectedBackgroundImage(path: path, name: file.name);
  }
}

class BackgroundImageService {
  BackgroundImageService({
    BackgroundImagePicker? picker,
    BackgroundImageDocumentsDirectoryProvider? documentsDirectoryProvider,
  })  : _picker = picker ?? FilePickerBackgroundImagePicker(),
        _documentsDirectoryProvider =
            documentsDirectoryProvider ?? getApplicationDocumentsDirectory;

  final BackgroundImagePicker _picker;
  final BackgroundImageDocumentsDirectoryProvider _documentsDirectoryProvider;

  Future<String?> pickAndImportBackgroundImage() async {
    final selection = await _picker.pickImageFile();
    if (selection == null) {
      return null;
    }

    return importBackgroundImage(
      sourcePath: selection.path,
      sourceName: selection.name,
    );
  }

  Future<String> importBackgroundImage({
    required String sourcePath,
    String? sourceName,
  }) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw FileSystemException('找不到背景圖片', sourcePath);
    }

    final fileName =
        _buildManagedFileName(sourceName ?? p.basename(sourcePath));
    final docsDir = await _documentsDirectoryProvider();
    final managedRelativePath = p.join('media', 'backgrounds', fileName);
    final destinationPath = p.join(docsDir.path, managedRelativePath);

    await File(destinationPath).parent.create(recursive: true);
    await sourceFile.copy(destinationPath);
    return managedRelativePath;
  }

  Future<String> resolveManagedImagePath(String managedRelativePath) async {
    final docsDir = await _documentsDirectoryProvider();
    return p.join(docsDir.path, managedRelativePath);
  }

  Future<bool> managedImageExists(String managedRelativePath) async {
    if (managedRelativePath.trim().isEmpty) {
      return false;
    }
    final resolvedPath = await resolveManagedImagePath(managedRelativePath);
    return File(resolvedPath).exists();
  }

  Future<void> deleteManagedImage(String managedRelativePath) async {
    if (managedRelativePath.trim().isEmpty) {
      return;
    }
    final resolvedPath = await resolveManagedImagePath(managedRelativePath);
    final file = File(resolvedPath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  String _buildManagedFileName(String sourceName) {
    final trimmed = sourceName.trim();
    final ext = p.extension(trimmed).trim();
    final safeExt = ext.isEmpty ? '.png' : ext.toLowerCase();
    final base = p
        .basenameWithoutExtension(trimmed)
        .replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_');
    final normalizedBase = base.isEmpty ? 'bg' : base;
    return '${normalizedBase}_${DateTime.now().millisecondsSinceEpoch}$safeExt';
  }
}
