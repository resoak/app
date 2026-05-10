import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Model download information
class ModelDownloadInfo {
  final String id;
  final String name;
  final String description;
  final String downloadUrl;
  final int expectedSizeBytes;

  const ModelDownloadInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.downloadUrl,
    required this.expectedSizeBytes,
  });

  /// Available models for download
  static const List<ModelDownloadInfo> availableModels = [
    ModelDownloadInfo(
      id: 'llama-3.2-3b',
      name: 'Llama 3.2 3B',
      description: 'Meta 官方模型，品質穩定。約 2GB。',
      downloadUrl: 'https://huggingface.co/hugging-quants/Llama-3.2-3B-Instruct-Q4_K_M-GGUF/resolve/main/llama-3.2-3b-instruct-q4_k_m.gguf',
      expectedSizeBytes: 2117000000, // ~2GB
    ),
  ];
}

/// Download progress state
class ModelDownloadProgress {
  final String modelId;
  final double progress; // 0.0 to 1.0
  final int downloadedBytes;
  final int totalBytes;
  final bool isDownloading;
  final bool isCompleted;
  final bool hasError;
  final String? errorMessage;

  const ModelDownloadProgress({
    required this.modelId,
    this.progress = 0.0,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    this.isDownloading = false,
    this.isCompleted = false,
    this.hasError = false,
    this.errorMessage,
  });

  ModelDownloadProgress copyWith({
    double? progress,
    int? downloadedBytes,
    int? totalBytes,
    bool? isDownloading,
    bool? isCompleted,
    bool? hasError,
    String? errorMessage,
  }) {
    return ModelDownloadProgress(
      modelId: modelId,
      progress: progress ?? this.progress,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      isDownloading: isDownloading ?? this.isDownloading,
      isCompleted: isCompleted ?? this.isCompleted,
      hasError: hasError ?? this.hasError,
      errorMessage: errorMessage,
    );
  }
}

/// Callback type for progress updates
typedef ProgressCallback = void Function(ModelDownloadProgress);

/// Service for downloading LLM models
class ModelDownloadService {
  final http.Client _client;

  ModelDownloadService({http.Client? client}) : _client = client ?? http.Client();

  /// Check if a model is already downloaded
  Future<bool> isModelDownloaded(String modelId) async {
    final file = await _getModelFile(modelId);
    return file.existsSync();
  }

  /// Get the downloaded model file path
  Future<dynamic> getModelFile(String modelId) async {
    final file = await _getModelFile(modelId);
    if (file.existsSync()) {
      return file;
    }
    return null;
  }

  /// Download a model with progress tracking
  Future<dynamic> downloadModel(
    String modelId, {
    ProgressCallback? onProgress,
  }) async {
    final modelInfo = ModelDownloadInfo.availableModels.firstWhere(
      (m) => m.id == modelId,
      orElse: () => throw Exception('Unknown model ID: $modelId'),
    );

    // Initialize progress
    final progress = ModelDownloadProgress(
      modelId: modelId,
      isDownloading: true,
      totalBytes: modelInfo.expectedSizeBytes,
    );
    onProgress?.call(progress);

    try {
      final request = http.Request('GET', Uri.parse(modelInfo.downloadUrl));
      final response = await _client.send(request);

      if (response.statusCode != 200) {
        throw Exception('Failed to download: HTTP ${response.statusCode}');
      }

      final contentLength = response.contentLength ?? modelInfo.expectedSizeBytes;
      final file = await _getModelFile(modelId);
      
      // Ensure directory exists
      await file.parent.create(recursive: true);

      // Create a temporary file for downloading
      final tempFile = File('${file.path}.tmp');
      
      int receivedBytes = 0;
      final sink = tempFile.openWrite();

      await for (final chunk in response.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;

        // Update progress
        final currentProgress = receivedBytes / contentLength;
        final newProgress = ModelDownloadProgress(
          modelId: modelId,
          progress: currentProgress,
          downloadedBytes: receivedBytes,
          totalBytes: contentLength,
          isDownloading: true,
        );
        onProgress?.call(newProgress);
      }

      await sink.close();

      // Rename temp file to final file
      await tempFile.rename(file.path);

      // Mark as completed
      final completedProgress = ModelDownloadProgress(
        modelId: modelId,
        progress: 1.0,
        downloadedBytes: contentLength,
        totalBytes: contentLength,
        isDownloading: false,
        isCompleted: true,
      );
      onProgress?.call(completedProgress);

      return file;
    } catch (e) {
      final errorProgress = ModelDownloadProgress(
        modelId: modelId,
        isDownloading: false,
        hasError: true,
        errorMessage: e.toString(),
      );
      onProgress?.call(errorProgress);
      rethrow;
    }
  }

  /// Delete a downloaded model
  Future<void> deleteModel(String modelId) async {
    final file = await _getModelFile(modelId);
    if (file.existsSync()) {
      await file.delete();
    }
  }

  /// Get all downloaded models
  Future<List<String>> getDownloadedModelIds() async {
    final dir = await _getModelsDirectory();
    if (!dir.existsSync()) {
      return [];
    }

    final List<String> downloadedIds = [];
    for (final modelInfo in ModelDownloadInfo.availableModels) {
      final file = File(p.join(dir.path, '${modelInfo.id}.gguf'));
      if (file.existsSync()) {
        downloadedIds.add(modelInfo.id);
      }
    }
    return downloadedIds;
  }

  Future<dynamic> _getModelFile(String modelId) async {
    final dir = await _getModelsDirectory();
    return File(p.join(dir.path, '$modelId.gguf'));
  }

  Future<dynamic> _getModelsDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    return Directory(p.join(appDir.path, 'models', 'llm'));
  }

  void dispose() {
    _client.close();
  }
}