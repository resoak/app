import 'package:flutter/foundation.dart';

class EmbeddingService {
  static final EmbeddingService _instance = EmbeddingService._internal();
  factory EmbeddingService() => _instance;
  EmbeddingService._internal();

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  Future<void> initialize() async {
    if (_isInitialized) return;
    // 暫時略過模型載入，秒速初始化
    await Future.delayed(const Duration(milliseconds: 100));
    _isInitialized = true;
    debugPrint('[Embedding] >>> 模擬初始化成功 (待未來接入 onnxruntime)');
  }

  /// 模擬生成向量 (回傳假資料以維持 TextRank 運作)
  List<double> embed(String text) {
    if (!_isInitialized) return [];
    return List.generate(384, (index) => (text.length * index) % 100 / 100.0);
  }

  static double cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length || a.isEmpty) return 0.0;
    double dot = 0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
    }
    return dot;
  }

  void dispose() {
    _isInitialized = false;
  }
}