import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_vault/services/audio_transcoding_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AudioTranscodingService desktop CLI path', () {
    test('converts audio with whisper-compatible ffmpeg arguments', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('audio_transcoding_cli_');
      final sourceFile =
          File('${tempDir.path}${Platform.pathSeparator}input.mp3');
      final destinationFile =
          File('${tempDir.path}${Platform.pathSeparator}output.wav');
      await sourceFile.writeAsBytes(const [1, 2, 3]);

      late String executable;
      late List<String> arguments;

      final service = AudioTranscodingService(
        useDesktopCli: () => true,
        resolveCliExecutable: ({required toolName, required envKeys}) async {
          expect(toolName, 'ffmpeg');
          return 'fake-ffmpeg';
        },
        processRunner: (command, args) async {
          executable = command;
          arguments = List<String>.from(args);
          await destinationFile.writeAsBytes(const [82, 73, 70, 70]);
          return ProcessResult(1, 0, '', '');
        },
      );

      await service.convertToWhisperWav(
        sourcePath: sourceFile.path,
        destinationPath: destinationFile.path,
      );

      expect(executable, 'fake-ffmpeg');
      expect(
        arguments,
        equals([
          '-y',
          '-i',
          sourceFile.path,
          '-ar',
          '16000',
          '-ac',
          '1',
          '-c:a',
          'pcm_s16le',
          destinationFile.path,
        ]),
      );

      await tempDir.delete(recursive: true);
    });

    test('parses duration from ffprobe output on desktop CLI path', () async {
      final service = AudioTranscodingService(
        useDesktopCli: () => true,
        resolveCliExecutable: ({required toolName, required envKeys}) async {
          expect(toolName, 'ffprobe');
          return 'fake-ffprobe';
        },
        processRunner: (command, args) async {
          expect(command, 'fake-ffprobe');
          return ProcessResult(1, 0, '12.6', '');
        },
      );

      final duration = await service.probeDurationSeconds('input.mp3');

      expect(duration, 13);
    });

    test('throws helpful error when ffmpeg executable is unavailable',
        () async {
      final service = AudioTranscodingService(
        useDesktopCli: () => true,
        resolveCliExecutable: ({required toolName, required envKeys}) async {
          throw AudioTranscodingException('找不到可用的 $toolName');
        },
        processRunner: (command, args) async {
          fail(
              'processRunner should not be called when executable resolution fails');
        },
      );

      await expectLater(
        service.convertToWhisperWav(
          sourcePath: 'input.mp3',
          destinationPath: 'output.wav',
        ),
        throwsA(
          isA<AudioTranscodingException>().having(
            (error) => error.message,
            'message',
            contains('找不到可用的 ffmpeg'),
          ),
        ),
      );
    });
  });
}
