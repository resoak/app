import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_vault/services/background_image_service.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('imports background image into managed background directory', () async {
    final tempDocsDir = await Directory.systemTemp.createTemp('bg_image_docs_');
    final sourceDir = await Directory.systemTemp.createTemp('bg_image_src_');
    final sourceFile =
        File('${sourceDir.path}${Platform.pathSeparator}wallpaper.png');
    await sourceFile.writeAsBytes(const [7, 8, 9]);

    final service = BackgroundImageService(
      documentsDirectoryProvider: () async => tempDocsDir,
    );

    final managedPath = await service.importBackgroundImage(
      sourcePath: sourceFile.path,
      sourceName: 'wallpaper.png',
    );

    expect(managedPath.startsWith(p.join('media', 'backgrounds')), isTrue);
    expect(p.extension(managedPath), '.png');

    final resolvedPath = await service.resolveManagedImagePath(managedPath);
    final copiedFile = File(resolvedPath);
    expect(await copiedFile.exists(), isTrue);
    expect(await copiedFile.readAsBytes(), [7, 8, 9]);

    await tempDocsDir.delete(recursive: true);
    await sourceDir.delete(recursive: true);
  });
}
