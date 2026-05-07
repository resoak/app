import 'dart:io';
import 'package:fcllama/fllama.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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

typedef LlmAssetLoader = Future<ByteData> Function(String assetPath);
typedef AppSupportDirectoryResolver = Future<Directory> Function();
typedef AndroidPlatformChecker = bool Function();
typedef FCllamaProvider = FCllama? Function();

class AndroidLocalLlmRuntimeService
    implements LocalLlmTranscriptSummaryRuntime {
  AndroidLocalLlmRuntimeService({
    LlmAssetLoader? assetLoader,
    AppSupportDirectoryResolver? appSupportDirectoryResolver,
    AndroidPlatformChecker? isAndroid,
    FCllamaProvider? llamaProvider,
  })  : _assetLoader = assetLoader ?? rootBundle.load,
        _appSupportDirectoryResolver =
            appSupportDirectoryResolver ?? getApplicationSupportDirectory,
        _isAndroid = isAndroid ?? _defaultIsAndroid,
        _llamaProvider = llamaProvider ?? FCllama.instance;

  static const String bundledModelAssetPath =
      'assets/models/llm/lecture_vault_summary.gguf';
  static const String bundledModelFileName = 'lecture_vault_summary.gguf';
  static const int _contextWindow = 1024;
  static const int _batchSize = 256;
  static const int _threadCount = 2;
  static const int _maxPredictionTokens = 220;

  final LlmAssetLoader _assetLoader;
  final AppSupportDirectoryResolver _appSupportDirectoryResolver;
  final AndroidPlatformChecker _isAndroid;
  final FCllamaProvider _llamaProvider;

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

    final modelFile = await _ensureBundledModelPresent();
    if (modelFile == null) {
      return const LocalLlmSummaryAttempt.unavailable(
        reason: LocalLlmUnavailableReason.missingBundledModel,
        message: 'Bundled GGUF model asset is missing.',
      );
    }

    double? contextId;
    try {
      final context = await llama.initContext(
        modelFile.path,
        nCtx: _contextWindow,
        nBatch: _batchSize,
        nThreads: _threadCount,
        nGpuLayers: 0,
        useMlock: false,
        useMmap: true,
        emitLoadProgress: false,
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
        temperature: 0.2,
        topK: 32,
        topP: 0.9,
        minP: 0.05,
        typicalP: 1.0,
        penaltyLastN: 128,
        penaltyRepeat: 1.05,
        penaltyFreq: 0.0,
        penaltyPresent: 0.0,
        stop: const ['<END_SUMMARY>', '逐字稿：'],
        emitRealtimeCompletion: false,
      );

      final summary = _extractCompletionText(response);
      if (summary.isEmpty) {
        throw StateError('Local LLM returned an empty summary.');
      }

      return LocalLlmSummaryAttempt.success(summary);
    } finally {
      if (contextId != null && contextId > 0) {
        try {
          await llama.stopCompletion(contextId: contextId);
        } catch (_) {}
        try {
          await llama.releaseContext(contextId);
        } catch (_) {}
      }
    }
  }

  Future<File?> _ensureBundledModelPresent() async {
    ByteData bytes;
    try {
      bytes = await _assetLoader(bundledModelAssetPath);
    } on FlutterError catch (error) {
      if (_looksLikeMissingAsset(error)) {
        return null;
      }
      rethrow;
    }

    final supportDirectory = await _appSupportDirectoryResolver();
    final modelDirectory = Directory(
      p.join(supportDirectory.path, 'models', 'llm'),
    );
    await modelDirectory.create(recursive: true);

    final file = File(p.join(modelDirectory.path, bundledModelFileName));
    final data =
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);

    if (!await file.exists() || await file.length() != data.length) {
      await file.writeAsBytes(data, flush: true);
    }

    return file;
  }

  bool _looksLikeMissingAsset(FlutterError error) {
    final message = error.message.toString();
    return message.contains('Unable to load asset') ||
        message.contains(bundledModelAssetPath);
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
    return '''你是一位協助整理大學課堂錄音的中文助教。請根據逐字稿整理重點。

規則：
1. 使用繁體中文。
2. 產出 3 到 5 點重點，每點單獨一行。
3. 每一行都以「• 」開頭。
4. 不要捏造逐字稿中沒有的資訊。
5. 優先保留課程中的定義、流程、比較、結論、專有名詞與演算法名稱。
6. 若逐字稿品質不佳，仍請整理出最可信的重點。
7. 不要加上前言、標題或結語，只輸出條列重點。

逐字稿：
$transcript

摘要：''';
  }
}
