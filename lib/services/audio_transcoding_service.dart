import 'dart:io';

import 'package:ffmpeg_kit_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_min_gpl/ffprobe_kit.dart';
import 'package:ffmpeg_kit_min_gpl/return_code.dart';
import 'package:flutter/foundation.dart';

typedef AudioDurationProbe = Future<int> Function(String sourcePath);
typedef WhisperAudioConverter = Future<void> Function({
  required String sourcePath,
  required String destinationPath,
});
typedef ProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);
typedef DesktopCliSelector = bool Function();
typedef CliExecutableResolver = Future<String> Function({
  required String toolName,
  required List<String> envKeys,
});

class AudioTranscodingException implements Exception {
  const AudioTranscodingException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AudioTranscodingService {
  AudioTranscodingService({
    AudioDurationProbe? probeDuration,
    WhisperAudioConverter? convertToWhisperWav,
    DesktopCliSelector? useDesktopCli,
    CliExecutableResolver? resolveCliExecutable,
    ProcessRunner? processRunner,
  })  : _probeDuration = probeDuration ??
            ((sourcePath) => _createDefaultProbeDuration(
                  useDesktopCli ?? _defaultUseDesktopCli,
                  resolveCliExecutable ?? _defaultResolveCliExecutable,
                  processRunner ?? _defaultProcessRunner,
                  sourcePath,
                )),
        _convertToWhisperWav = convertToWhisperWav ??
            (({required sourcePath, required destinationPath}) =>
                _createDefaultConvertToWhisperWav(
                  useDesktopCli: useDesktopCli ?? _defaultUseDesktopCli,
                  resolveCliExecutable:
                      resolveCliExecutable ?? _defaultResolveCliExecutable,
                  processRunner: processRunner ?? _defaultProcessRunner,
                  sourcePath: sourcePath,
                  destinationPath: destinationPath,
                ));

  final AudioDurationProbe _probeDuration;
  final WhisperAudioConverter _convertToWhisperWav;

  Future<int> probeDurationSeconds(String sourcePath) =>
      _probeDuration(sourcePath);

  Future<void> convertToWhisperWav({
    required String sourcePath,
    required String destinationPath,
  }) {
    return _convertToWhisperWav(
      sourcePath: sourcePath,
      destinationPath: destinationPath,
    );
  }

  static bool _defaultUseDesktopCli() => Platform.isWindows || Platform.isLinux;

  static Future<int> _createDefaultProbeDuration(
    DesktopCliSelector useDesktopCli,
    CliExecutableResolver resolveCliExecutable,
    ProcessRunner processRunner,
    String sourcePath,
  ) async {
    try {
      if (useDesktopCli()) {
        return await _probeDurationWithCli(
          sourcePath,
          resolveCliExecutable: resolveCliExecutable,
          processRunner: processRunner,
        );
      }

      final mediaInformation = await FFprobeKit.getMediaInformation(sourcePath);
      final info = mediaInformation.getMediaInformation();
      final durationStr = info?.getDuration();
      final duration =
          durationStr == null ? null : double.tryParse(durationStr);
      return duration?.round() ?? 0;
    } catch (error) {
      debugPrint('無法取得音檔時長: $error');
      return 0;
    }
  }

  static Future<void> _createDefaultConvertToWhisperWav({
    required DesktopCliSelector useDesktopCli,
    required CliExecutableResolver resolveCliExecutable,
    required ProcessRunner processRunner,
    required String sourcePath,
    required String destinationPath,
  }) async {
    if (useDesktopCli()) {
      await _convertToWhisperWavWithCli(
        sourcePath: sourcePath,
        destinationPath: destinationPath,
        resolveCliExecutable: resolveCliExecutable,
        processRunner: processRunner,
      );
      return;
    }

    final command = [
      '-y',
      '-i',
      sourcePath,
      '-ar',
      '16000',
      '-ac',
      '1',
      '-c:a',
      'pcm_s16le',
      destinationPath,
    ];
    final session = await FFmpegKit.executeWithArguments(command);
    final returnCode = await session.getReturnCode();

    if (!ReturnCode.isSuccess(returnCode)) {
      final failStackTrace = await session.getFailStackTrace();
      final output = await session.getOutput();
      throw AudioTranscodingException(
        _buildPluginFailureMessage(
          output: output,
          failStackTrace: failStackTrace,
        ),
      );
    }

    await _verifyOutputFile(destinationPath);
  }

  static Future<int> _probeDurationWithCli(
    String sourcePath, {
    required CliExecutableResolver resolveCliExecutable,
    required ProcessRunner processRunner,
  }) async {
    try {
      final ffprobePath = await resolveCliExecutable(
        toolName: 'ffprobe',
        envKeys: const ['LECTURE_VAULT_FFPROBE_PATH', 'FFPROBE_PATH'],
      );
      final result = await processRunner(ffprobePath, [
        '-v',
        'error',
        '-show_entries',
        'format=duration',
        '-of',
        'default=noprint_wrappers=1:nokey=1',
        sourcePath,
      ]);

      if (result.exitCode != 0) {
        debugPrint('無法取得音檔時長: ${_buildProcessDetails(result)}');
        return 0;
      }

      final duration = double.tryParse(result.stdout.toString().trim());
      return duration?.round() ?? 0;
    } catch (error) {
      debugPrint('無法取得音檔時長: $error');
      return 0;
    }
  }

  static Future<void> _convertToWhisperWavWithCli({
    required String sourcePath,
    required String destinationPath,
    required CliExecutableResolver resolveCliExecutable,
    required ProcessRunner processRunner,
  }) async {
    final ffmpegPath = await resolveCliExecutable(
      toolName: 'ffmpeg',
      envKeys: const ['LECTURE_VAULT_FFMPEG_PATH', 'FFMPEG_PATH'],
    );
    final result = await processRunner(ffmpegPath, [
      '-y',
      '-i',
      sourcePath,
      '-ar',
      '16000',
      '-ac',
      '1',
      '-c:a',
      'pcm_s16le',
      destinationPath,
    ]);

    if (result.exitCode != 0) {
      throw AudioTranscodingException(
        '音訊轉換失敗：${_buildProcessDetails(result)}',
      );
    }

    await _verifyOutputFile(destinationPath);
  }

  static Future<String> _defaultResolveCliExecutable({
    required String toolName,
    required List<String> envKeys,
  }) async {
    for (final envKey in envKeys) {
      final configuredPath = Platform.environment[envKey]?.trim();
      if (configuredPath != null && configuredPath.isNotEmpty) {
        final configuredFile = File(configuredPath);
        if (await configuredFile.exists()) {
          return configuredPath;
        }
      }
    }

    final lookupResult = await Process.run(
      Platform.isWindows ? 'where.exe' : 'which',
      [toolName],
    );
    if (lookupResult.exitCode == 0) {
      final candidates = lookupResult.stdout
          .toString()
          .split(RegExp(r'\r?\n'))
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty);

      for (final candidate in candidates) {
        if (await File(candidate).exists()) {
          return candidate;
        }
      }
    }

    throw AudioTranscodingException(
      '找不到可用的 $toolName。Windows/Linux 目前改用系統上的 ffmpeg/ffprobe，'
      '請先安裝並確認 `$toolName` 可在命令列執行，或設定 ${envKeys.first}。',
    );
  }

  static Future<void> _verifyOutputFile(String destinationPath) async {
    final outputFile = File(destinationPath);
    if (!await outputFile.exists()) {
      throw const AudioTranscodingException('音訊轉換失敗：輸出 WAV 檔未建立。');
    }

    if (await outputFile.length() <= 0) {
      throw const AudioTranscodingException('音訊轉換失敗：輸出 WAV 檔內容為空。');
    }
  }

  static String _buildPluginFailureMessage({
    required String? output,
    required String? failStackTrace,
  }) {
    final details = [
      if (output != null && output.trim().isNotEmpty) output.trim(),
      if (failStackTrace != null && failStackTrace.trim().isNotEmpty)
        failStackTrace.trim(),
    ].join('\n');

    if (details.isEmpty) {
      return '音訊轉換失敗，請確認檔案格式是否正確。';
    }

    return '音訊轉換失敗：$details';
  }

  static String _buildProcessDetails(ProcessResult result) {
    final stderr = result.stderr.toString().trim();
    final stdout = result.stdout.toString().trim();

    if (stderr.isNotEmpty) {
      return stderr;
    }

    if (stdout.isNotEmpty) {
      return stdout;
    }

    return 'ffmpeg 結束碼 ${result.exitCode}';
  }

  static Future<ProcessResult> _defaultProcessRunner(
    String executable,
    List<String> arguments,
  ) {
    return Process.run(executable, arguments);
  }
}
