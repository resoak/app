import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_vault/services/minilm_runtime_service.dart';
import 'package:lecture_vault/services/summary_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MiniLmSummaryService', () {
    test('formats MiniLM-ranked key points as bullet lines', () async {
      const service = MiniLmSummaryService(
        runtime: _FakeRuntime([
          [1.0, 0.0],
          [0.95, 0.05],
          [0.1, 0.9],
        ]),
        fallbackService: LocalSummaryService(),
      );

      final transcript = [
        '今天先介紹作業系統中的行程切換成本。',
        '老師接著補充 context switch 太頻繁會拖慢效能。',
        '最後整理 interrupt 與 scheduler 的互動方式。',
      ].join();

      final summary = await service.summarizeTranscript(transcript);
      final lines = summary.split('\n');

      expect(lines.length, greaterThanOrEqualTo(2));
      expect(lines.every((line) => line.startsWith('• ')), isTrue);
      expect(summary, contains('行程切換成本'));
    });

    test('falls back to LocalSummaryService when MiniLM runtime fails',
        () async {
      const service = MiniLmSummaryService(
        runtime: _ThrowingRuntime(),
        fallbackService: LocalSummaryService(),
      );

      final transcript = [
        '今天先講解紅黑樹的五個性質。',
        '接著說明旋轉與重新著色如何維持平衡。',
        '最後比較紅黑樹與 AVL 樹在插入時的差異。',
      ].join();

      final summary = await service.summarizeTranscript(transcript);

      expect(summary, startsWith('• '));
      expect(summary, contains('紅黑樹'));
    });

    test('uses real MiniLM runtime without falling back', () async {
      const service = MiniLmSummaryService(
        runtime: MiniLmRuntimeService(),
        fallbackService: _FailingFallbackService(),
      );

      final transcript = [
        '今天先說明 transaction isolation level 的分類。',
        '接著比較 read committed 與 repeatable read 的差異。',
        '最後補充 phantom read 為什麼會影響查詢一致性。',
      ].join();

      final summary = await service.summarizeTranscript(transcript);

      expect(summary, startsWith('• '));
      expect(summary, contains('transaction isolation level'));
    });
  });
}

class _FakeRuntime implements SentenceEmbeddingRuntime {
  const _FakeRuntime(this.embeddings);

  final List<List<double>> embeddings;

  @override
  Future<List<List<double>>> embedSentences(List<String> sentences) async {
    return embeddings;
  }
}

class _ThrowingRuntime implements SentenceEmbeddingRuntime {
  const _ThrowingRuntime();

  @override
  Future<List<List<double>>> embedSentences(List<String> sentences) {
    throw StateError('runtime unavailable');
  }
}

class _FailingFallbackService implements SummaryService {
  const _FailingFallbackService();

  @override
  Future<String> summarizeTranscript(String transcript) {
    throw StateError('fallback should not run');
  }
}
