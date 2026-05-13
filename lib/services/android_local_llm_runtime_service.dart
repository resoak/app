import 'dart:io';
import 'package:fcllama/fllama.dart';
import 'package:flutter/foundation.dart';

import 'model_download_service.dart';

enum LocalLlmUnavailableReason {
  unsupportedPlatform,
  missingBundledModel,
  nativeBridgeUnavailable,
  initializationFailed,
}

class LocalLlmSummaryAttempt {
  const LocalLlmSummaryAttempt._({
    required this.summary,
    required this.unavailableReason,
    required this.message,
  });

  const LocalLlmSummaryAttempt.success(String summary)
      : this._(
          summary: summary,
          unavailableReason: null,
          message: null,
        );

  const LocalLlmSummaryAttempt.unavailable({
    required LocalLlmUnavailableReason reason,
    required String message,
  }) : this._(
          summary: null,
          unavailableReason: reason,
          message: message,
        );

  final String? summary;
  final LocalLlmUnavailableReason? unavailableReason;
  final String? message;

  bool get hasSummary => summary != null && summary!.trim().isNotEmpty;
  bool get isUnavailable => unavailableReason != null;
}

abstract class LocalLlmTranscriptSummaryRuntime {
  Future<LocalLlmSummaryAttempt> summarizeTranscript(String transcript);
}

typedef AndroidPlatformChecker = bool Function();
typedef FCllamaProvider = FCllama? Function();

class AndroidLocalLlmRuntimeService
    implements LocalLlmTranscriptSummaryRuntime {
  AndroidLocalLlmRuntimeService({
    AndroidPlatformChecker? isAndroid,
    FCllamaProvider? llamaProvider,
    String? modelFilePath,
  })  : _isAndroid = isAndroid ?? _defaultIsAndroid,
        _llamaProvider = llamaProvider ?? FCllama.instance,
        _customModelFilePath = modelFilePath;

  /// Static variable to store the selected model ID for this session
  /// Set this before calling summarizeTranscript to use a specific model
  static String? selectedModelId;

  static const int _contextWindow = 512;
  static const int _batchSize = 128;
  static const int _threadCount = 4;
  static const int _maxPredictionTokens = 200;

  final AndroidPlatformChecker _isAndroid;
  final FCllamaProvider _llamaProvider;
  final String? _customModelFilePath;

  static bool _defaultIsAndroid() => !kIsWeb && Platform.isAndroid;

  @override
  Future<LocalLlmSummaryAttempt> summarizeTranscript(String transcript) async {
    final normalizedTranscript = transcript.trim();
    if (normalizedTranscript.isEmpty) {
      return const LocalLlmSummaryAttempt.success('');
    }

    if (!_isAndroid()) {
      return const LocalLlmSummaryAttempt.unavailable(
        reason: LocalLlmUnavailableReason.unsupportedPlatform,
        message: 'Android local LLM summarization is only enabled on Android.',
      );
    }

    final llama = _llamaProvider();
    if (llama == null) {
      return const LocalLlmSummaryAttempt.unavailable(
        reason: LocalLlmUnavailableReason.nativeBridgeUnavailable,
        message: 'FCllama runtime bridge is not available in this process.',
      );
    }

    final modelFile = await _resolveModelFile();
    if (modelFile == null) {
      return const LocalLlmSummaryAttempt.unavailable(
        reason: LocalLlmUnavailableReason.missingBundledModel,
        message: 'LLM model file is missing.',
      );
    }

    double? contextId;
    try {
      debugPrint('LLM: Loading model from: ${modelFile.path}');
      final context = await llama.initContext(
        modelFile.path,
        nCtx: _contextWindow,
        nBatch: _batchSize,
        nThreads: _threadCount,
        nGpuLayers: 0,
        useMlock: false,
        useMmap: true,
        emitLoadProgress: true,
      );
      contextId = _parseContextId(context);
      if (contextId == null || contextId <= 0) {
        return const LocalLlmSummaryAttempt.unavailable(
          reason: LocalLlmUnavailableReason.initializationFailed,
          message: 'FCllama failed to initialize a usable model context.',
        );
      }

      final response = await llama.completion(
        contextId,
        prompt: _buildPrompt(normalizedTranscript),
        nThreads: _threadCount,
        nPredict: _maxPredictionTokens,
        temperature: 0.1,
        topK: 20,
        topP: 0.85,
        minP: 0.05,
        typicalP: 1.0,
        penaltyLastN: 256,
        penaltyRepeat: 1.18,
        penaltyFreq: 0.05,
        penaltyPresent: 0.1,
        stop: const [
          '<|im_end|>',
          '<|im_start|>',
          '<|eot_id|>',
          '\n\n\n',
          '---',
          '逐字稿',
        ],
        emitRealtimeCompletion: false,
      );

      final rawSummary = _extractCompletionText(response);
      if (rawSummary.isEmpty) {
        throw StateError('Local LLM returned an empty summary.');
      }

      return LocalLlmSummaryAttempt.success(rawSummary);
    } catch (error, stackTrace) {
      debugPrint('=== AndroidLocalLlmRuntimeService ERROR ===');
      debugPrint('Error type: ${error.runtimeType}');
      debugPrint('Error message: $error');
      debugPrint('Stack trace: $stackTrace');
      debugPrint('============================================');

      // Check if it's an ONNX-related error
      final errorStr = error.toString().toLowerCase();
      if (errorStr.contains('clipboard') || errorStr.contains('onnx')) {
        debugPrint(
            'DETECTED: ONNX/Clipboard related error - checking model file...');
      }

      return LocalLlmSummaryAttempt.unavailable(
        reason: LocalLlmUnavailableReason.initializationFailed,
        message: 'LLM 執行失敗：$error',
      );
    } finally {
      if (contextId != null && contextId > 0) {
        try {
          await llama.stopCompletion(contextId: contextId);
        } catch (error) {
          debugPrint('LLM: Failed to stop completion: $error');
        }
        try {
          await llama.releaseContext(contextId);
        } catch (error) {
          debugPrint('LLM: Failed to release context: $error');
        }
      }
    }
  }

  Future<File?> _resolveModelFile() async {
    // 1. If custom model path provided, use it directly
    final customModelFilePath = _customModelFilePath;
    if (customModelFilePath != null) {
      final customFile = File(customModelFilePath);
      if (await customFile.exists()) {
        debugPrint('LLM: Using custom model path: $customModelFilePath');
        return customFile;
      }
    }

    // 2. Use a downloaded model
    final downloadService = ModelDownloadService();
    try {
      final downloadedIds = await downloadService.getDownloadedModelIds();
      if (downloadedIds.isNotEmpty) {
        final modelIdToUse =
            (selectedModelId != null && downloadedIds.contains(selectedModelId))
                ? selectedModelId!
                : downloadedIds.first;

        final modelFile = await downloadService.getModelFile(modelIdToUse);
        if (modelFile != null && await modelFile.exists()) {
          debugPrint('LLM: Using downloaded model: $modelIdToUse');
          return modelFile;
        }
      }
    } finally {
      downloadService.dispose();
    }

    // No model available
    debugPrint(
        'LLM: No downloaded model found. Please download a model first.');
    return null;
  }

  double? _parseContextId(Map<Object?, dynamic>? context) {
    final raw = context?['contextId'];
    if (raw is num) {
      return raw.toDouble();
    }
    if (raw is String) {
      return double.tryParse(raw);
    }
    return null;
  }

  String _extractCompletionText(Map<Object?, dynamic>? response) {
    final directText = response?['text'];
    if (directText is String && directText.trim().isNotEmpty) {
      return directText.trim();
    }

    final content = response?['content'];
    if (content is String && content.trim().isNotEmpty) {
      return content.trim();
    }

    final result = response?['result'];
    if (result is String && result.trim().isNotEmpty) {
      return result.trim();
    }
    if (result is Map<Object?, dynamic>) {
      final resultText = result['text'] ?? result['content'] ?? result['token'];
      if (resultText is String && resultText.trim().isNotEmpty) {
        return resultText.trim();
      }
    }

    return '';
  }

  String _buildPrompt(String transcript) {
    // Clean transcript of invalid UTF-8 characters before passing to LLM
    final sanitizedTranscript = _sanitizeUtf8(transcript);

    // Truncate very long transcripts to stay within context window limits.
    // Reserve ~300 tokens for prompt framing + output.
    const maxTranscriptChars = 600;
    final truncatedTranscript = sanitizedTranscript.length > maxTranscriptChars
        ? _truncateAtValidUtf8(sanitizedTranscript, maxTranscriptChars)
        : sanitizedTranscript;

    // SmolLM2 uses ChatML format with <|im_start|> and <|im_end|> tokens.
    // Keep the prompt minimal to reduce echo/leakage from small models.
    return '<|im_start|>system\n'
        '用繁體中文寫重點摘要。每行以「• 」開頭。只寫重點，不要寫其他東西。\n'
        '<|im_end|>\n'
        '<|im_start|>user\n'
        '$truncatedTranscript\n'
        '<|im_end|>\n'
        '<|im_start|>assistant\n'
        '• ';
  }

  /// Remove invalid UTF-8 characters that cause JNI crash in fcllama
  String _sanitizeUtf8(String input) {
    // Replace common problematic characters
    return input
        .replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '') // Remove control characters
        .replaceAll('\uFFFD', ' ') // Replace replacement character
        .trim();
  }

  /// Truncate string at a valid UTF-8 code point boundary to avoid JNI crash.
  /// If truncation point falls in the middle of a multi-byte character,
  /// backtrack to the nearest valid character boundary.
  String _truncateAtValidUtf8(String input, int maxChars) {
    if (input.length <= maxChars) {
      return input;
    }

    // Get the substring up to maxChars
    var truncated = input.substring(0, maxChars);

    // Check if the last character is complete (not a truncated multi-byte)
    // Walk backwards to find a valid character boundary
    while (truncated.isNotEmpty) {
      final lastCodeUnit = truncated.codeUnitAt(truncated.length - 1);

      // ASCII (0x00-0x7F) - single byte, always valid
      if (lastCodeUnit <= 0x7F) {
        break;
      }

      // Check for valid UTF-8 leading byte patterns:
      // - 2-byte: 110xxxxx (0xC0-0xDF)
      // - 3-byte: 1110xxxx (0xE0-0xEF)
      // - 4-byte: 11110xxx (0xF0-0xF7)
      final isLeadingByte = (lastCodeUnit & 0xC0) == 0xC0;

      if (!isLeadingByte) {
        // This is a continuation byte (10xxxxxx), not a valid start
        // Remove it and check again
        truncated = truncated.substring(0, truncated.length - 1);
        continue;
      }

      // Calculate expected length of this character
      int expectedLength;
      if ((lastCodeUnit & 0xE0) == 0xC0) {
        expectedLength = 2; // 110xxxxx
      } else if ((lastCodeUnit & 0xF0) == 0xE0) {
        expectedLength = 3; // 1110xxxx
      } else if ((lastCodeUnit & 0xF8) == 0xF0) {
        expectedLength = 4; // 11110xxx
      } else {
        // Invalid leading byte, remove it
        truncated = truncated.substring(0, truncated.length - 1);
        continue;
      }

      // Check if we have enough characters for this code point
      if (truncated.length >= expectedLength) {
        // Valid - we have the complete character
        break;
      } else {
        // Incomplete multi-byte character - remove it
        truncated = truncated.substring(0, truncated.length - 1);
      }
    }

    return truncated;
  }
}
