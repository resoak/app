import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dart_sentencepiece_tokenizer/dart_sentencepiece_tokenizer.dart';
import 'package:flutter/services.dart';
import 'package:onnxruntime/onnxruntime.dart';

abstract class SentenceEmbeddingRuntime {
  Future<List<List<double>>> embedSentences(List<String> sentences);
}

class MiniLmRuntimeService implements SentenceEmbeddingRuntime {
  const MiniLmRuntimeService();

  static const String modelAssetPath =
      'assets/models/minilm/model_quantized.onnx';
  static const String tokenizerAssetPath =
      'assets/models/minilm/tokenizer.json';
  static const String configAssetPath =
      'assets/models/minilm/sentence_bert_config.json';
  static const int _defaultMaxSequenceLength = 128;

  static Future<_MiniLmBundle>? _sharedBundleFuture;
  static bool _environmentInitialized = false;

  @override
  Future<List<List<double>>> embedSentences(List<String> sentences) async {
    if (sentences.isEmpty) {
      return const [];
    }

    final bundle = await _loadBundle();
    final embeddings = <List<double>>[];
    for (final sentence in sentences) {
      embeddings.add(await _embedSentence(bundle, sentence));
    }
    return embeddings;
  }

  Future<_MiniLmBundle> _loadBundle() {
    return _sharedBundleFuture ??= _createBundle();
  }

  Future<_MiniLmBundle> _createBundle() async {
    _ensureEnvironment();

    final modelBytes =
        (await rootBundle.load(modelAssetPath)).buffer.asUint8List();
    final tokenizerJson = utf8.decode(
      (await rootBundle.load(tokenizerAssetPath)).buffer.asUint8List(),
    );
    final configJson = utf8.decode(
      (await rootBundle.load(configAssetPath)).buffer.asUint8List(),
    );
    final config = jsonDecode(configJson) as Map<String, dynamic>;
    final maxSequenceLength = (config['max_seq_length'] as num?)?.toInt() ??
        _defaultMaxSequenceLength;

    final tokenizer = TokenizerJsonLoader.fromJsonString(tokenizerJson)
      ..enableTruncation(maxLength: maxSequenceLength);

    final sessionOptions = OrtSessionOptions();
    sessionOptions.setIntraOpNumThreads(1);
    final session = OrtSession.fromBuffer(modelBytes, sessionOptions);
    sessionOptions.release();

    return _MiniLmBundle(
      tokenizer: tokenizer,
      session: session,
      maxSequenceLength: maxSequenceLength,
    );
  }

  void _ensureEnvironment() {
    if (_environmentInitialized) {
      return;
    }
    OrtEnv.instance.init();
    _environmentInitialized = true;
  }

  Future<List<double>> _embedSentence(
    _MiniLmBundle bundle,
    String sentence,
  ) async {
    final encoding = bundle.tokenizer.encode(sentence);
    final inputIds = Int64List.fromList(encoding.ids);
    final attentionMask = Int64List.fromList(encoding.attentionMask);
    final typeIds = Int64List.fromList(encoding.typeIds);

    final ortInputs = <OrtValueTensor>[];
    final inputs = <String, OrtValue>{};
    void attachTensor(String name, Int64List values) {
      final tensor = OrtValueTensor.createTensorWithDataList(
        [values],
        [1, values.length],
      );
      ortInputs.add(tensor);
      inputs[name] = tensor;
    }

    for (final inputName in bundle.session.inputNames) {
      switch (inputName) {
        case 'input_ids':
          attachTensor(inputName, inputIds);
          break;
        case 'attention_mask':
          attachTensor(inputName, attentionMask);
          break;
        case 'token_type_ids':
          attachTensor(inputName, typeIds);
          break;
        default:
          break;
      }
    }

    if (!inputs.containsKey('input_ids') ||
        !inputs.containsKey('attention_mask')) {
      for (final tensor in ortInputs) {
        tensor.release();
      }
      throw StateError(
        'MiniLM ONNX model is missing required inputs: ${bundle.session.inputNames}',
      );
    }

    final runOptions = OrtRunOptions();
    List<OrtValue?> outputs = const [];
    try {
      outputs = bundle.session.run(runOptions, inputs);
      final sequenceOutput = outputs
          .whereType<OrtValueTensor>()
          .map((output) => output.value)
          .firstWhere(
            _looksLikeTensorOutput,
            orElse: () =>
                throw StateError('MiniLM model returned no tensor output.'),
          );
      return _extractEmbeddingVector(
        sequenceOutput,
        attentionMask,
        encoding.specialTokensMask,
      );
    } finally {
      runOptions.release();
      for (final tensor in ortInputs) {
        tensor.release();
      }
      for (final output in outputs) {
        output?.release();
      }
    }
  }

  bool _looksLikeTensorOutput(Object? value) {
    return value is List && value.isNotEmpty && value.first is List;
  }

  List<double> _extractEmbeddingVector(
    Object? output,
    Int64List attentionMask,
    Uint8List specialTokensMask,
  ) {
    if (output is! List || output.isEmpty) {
      throw StateError('MiniLM output was empty.');
    }

    final batch = output.first;
    if (batch is List && batch.isNotEmpty && batch.first is List) {
      final tokenVectors = batch
          .map<List<double>>(
            (token) => (token as List)
                .map((value) => (value as num).toDouble())
                .toList(growable: false),
          )
          .toList(growable: false);
      final pooled = _meanPool(
        tokenVectors: tokenVectors,
        attentionMask: attentionMask,
        specialTokensMask: specialTokensMask,
      );
      return _normalize(pooled);
    }

    if (batch is List) {
      return _normalize(
        batch
            .map<double>((value) => (value as num).toDouble())
            .toList(growable: false),
      );
    }

    throw StateError('MiniLM output shape is not supported.');
  }

  List<double> _meanPool({
    required List<List<double>> tokenVectors,
    required Int64List attentionMask,
    required Uint8List specialTokensMask,
  }) {
    if (tokenVectors.isEmpty) {
      return const [];
    }

    final dimensions = tokenVectors.first.length;
    final pooled = List<double>.filled(dimensions, 0.0);
    var count = 0;

    for (var index = 0; index < tokenVectors.length; index++) {
      final attended = index < attentionMask.length && attentionMask[index] > 0;
      final isSpecial =
          index < specialTokensMask.length && specialTokensMask[index] > 0;
      if (!attended || isSpecial) {
        continue;
      }

      final tokenVector = tokenVectors[index];
      for (var dimension = 0; dimension < dimensions; dimension++) {
        pooled[dimension] += tokenVector[dimension];
      }
      count += 1;
    }

    if (count == 0) {
      count = math.min(tokenVectors.length, attentionMask.length);
      for (var index = 0; index < count; index++) {
        final tokenVector = tokenVectors[index];
        for (var dimension = 0; dimension < dimensions; dimension++) {
          pooled[dimension] += tokenVector[dimension];
        }
      }
    }

    if (count <= 0) {
      return List<double>.filled(dimensions, 0.0, growable: false);
    }

    return pooled.map((value) => value / count).toList(growable: false);
  }

  List<double> _normalize(List<double> vector) {
    if (vector.isEmpty) {
      return const [];
    }

    var magnitude = 0.0;
    for (final value in vector) {
      magnitude += value * value;
    }
    magnitude = math.sqrt(magnitude);
    if (magnitude <= 1e-12) {
      return List<double>.filled(vector.length, 0.0, growable: false);
    }
    return vector.map((value) => value / magnitude).toList(growable: false);
  }
}

class _MiniLmBundle {
  const _MiniLmBundle({
    required this.tokenizer,
    required this.session,
    required this.maxSequenceLength,
  });

  final SentencePieceTokenizer tokenizer;
  final OrtSession session;
  final int maxSequenceLength;
}
