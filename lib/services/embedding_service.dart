import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:path_provider/path_provider.dart';

class EmbeddingService {
  static final EmbeddingService _instance = EmbeddingService._();
  factory EmbeddingService() => _instance;
  EmbeddingService._();

  OrtSession? _session;
  Map<String, int> _vocab = {};
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  static const int _embDim = 384;
  static const int _maxLen = 128;

  Future<void> initialize() async {
    if (_isInitialized) return;

    OrtEnv.instance.init();

    final dir = await getApplicationDocumentsDirectory();
    final modelDir = Directory('${dir.path}/minilm');
    if (!await modelDir.exists()) await modelDir.create(recursive: true);

    final modelPath = '${modelDir.path}/model.onnx';
    final vocabPath = '${modelDir.path}/vocab.txt';

    await _copyAsset('assets/models/minilm/model.onnx', modelPath);
    await _copyAsset('assets/models/minilm/vocab.txt', vocabPath);

    final opts = OrtSessionOptions();
    _session = OrtSession.fromFile(File(modelPath), opts);
    _vocab = await _loadVocab(vocabPath);
    _isInitialized = true;
  }

  Future<List<double>> embed(String text) async {
    assert(_isInitialized, 'EmbeddingService not initialized');

    final tokens = _tokenize(text);
    final inputIds = _toInputIds(tokens);
    final attentionMask = List.filled(inputIds.length, 1);

    final inputIdsTensor = OrtValueTensor.createTensorWithDataList(
      Int64List.fromList(inputIds),
      [1, inputIds.length],
    );
    final maskTensor = OrtValueTensor.createTensorWithDataList(
      Int64List.fromList(attentionMask),
      [1, inputIds.length],
    );

    final inputs = {
      'input_ids': inputIdsTensor,
      'attention_mask': maskTensor,
    };

    final outputs = await _session!.runAsync(OrtRunOptions(), inputs);
    final hiddenState = outputs![0]!.value as List<List<List<double>>>;
    final embedding = _meanPool(hiddenState[0], attentionMask);

    inputIdsTensor.release();
    maskTensor.release();
    for (final o in outputs) {
      o?.release();
    }

    return _normalize(embedding);
  }

  static double cosineSimilarity(List<double> a, List<double> b) {
    assert(a.length == b.length);
    double dot = 0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
    }
    return dot;
  }

  List<String> _tokenize(String text) {
    final cleaned = text.toLowerCase().trim();
    final tokens = <String>['[CLS]'];

    for (final char in cleaned.runes) {
      final c = String.fromCharCode(char);
      if (_isCjk(char)) {
        tokens.add(c);
      } else if (c != ' ') {
        tokens.add(c);
      }
    }

    tokens.add('[SEP]');

    if (tokens.length > _maxLen) {
      return [...tokens.sublist(0, _maxLen - 1), '[SEP]'];
    }
    return tokens;
  }

  List<int> _toInputIds(List<String> tokens) {
    return tokens.map((t) => _vocab[t] ?? _vocab['[UNK]'] ?? 100).toList();
  }

  bool _isCjk(int codePoint) {
    return (codePoint >= 0x4E00 && codePoint <= 0x9FFF) ||
        (codePoint >= 0x3400 && codePoint <= 0x4DBF) ||
        (codePoint >= 0x20000 && codePoint <= 0x2A6DF);
  }

  List<double> _meanPool(List<List<double>> hiddenState, List<int> mask) {
    final result = List.filled(_embDim, 0.0);
    int count = 0;
    for (int i = 0; i < hiddenState.length; i++) {
      if (mask[i] == 1) {
        for (int j = 0; j < _embDim; j++) {
          result[j] += hiddenState[i][j];
        }
        count++;
      }
    }
    if (count > 0) {
      for (int j = 0; j < _embDim; j++) {
        result[j] /= count;
      }
    }
    return result;
  }

  List<double> _normalize(List<double> v) {
    double norm = 0;
    for (final x in v) {
      norm += x * x;
    }
    norm = sqrt(norm);
    if (norm == 0) return v;
    return v.map((x) => x / norm).toList();
  }

  Future<Map<String, int>> _loadVocab(String path) async {
    final lines = await File(path).readAsLines();
    final vocab = <String, int>{};
    for (int i = 0; i < lines.length; i++) {
      vocab[lines[i].trim()] = i;
    }
    return vocab;
  }

  Future<void> _copyAsset(String assetPath, String targetPath) async {
    final file = File(targetPath);
    if (await file.exists()) return;
    final data = await rootBundle.load(assetPath);
    await file.writeAsBytes(data.buffer.asUint8List());
  }

  void dispose() {
    _session?.release();
    OrtEnv.instance.release();
  }
}