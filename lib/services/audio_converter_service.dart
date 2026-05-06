import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'audio_transcoding_service.dart';

class AudioConverterService {
  AudioConverterService({AudioTranscodingService? transcodingService})
      : _transcodingService = transcodingService ?? AudioTranscodingService();

  final AudioTranscodingService _transcodingService;

  /// 將任何音檔轉換為 Whisper 要求的格式：WAV, 16kHz, Single Channel (Mono)
  Future<String?> convertToWhisperFormat(String inputPath) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final fileName = p.basenameWithoutExtension(inputPath);
      // 輸出路徑設在暫存區，避免佔用永久空間
      final outputPath = p.join(tempDir.path, '${fileName}_whisper_ready.wav');

      // 如果檔案已存在則刪除，確保重新轉換
      final outputFile = File(outputPath);
      if (await outputFile.exists()) {
        await outputFile.delete();
      }

      await _transcodingService.convertToWhisperWav(
        sourcePath: inputPath,
        destinationPath: outputPath,
      );

      debugPrint('音檔轉換成功: $outputPath');
      return outputPath;
    } catch (e) {
      debugPrint('轉換過程發生錯誤: $e');
      return null;
    }
  }
}
