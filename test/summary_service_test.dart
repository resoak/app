import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_vault/services/android_local_llm_runtime_service.dart';
import 'package:lecture_vault/services/summary_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocalSummaryService', () {
    const service = LocalSummaryService();

    test('returns local fallback message for empty transcript', () async {
      final summary = await service.summarizeTranscript('');

      expect(summary, contains('無法產生摘要'));
    });

    test('formats short transcript as key point output', () async {
      final summary = await service.summarizeTranscript('今天講述分頁機制');

      expect(summary, startsWith('• '));
      expect(summary, endsWith('。'));
    });

    test('extracts multiple transcript-first key points for long transcript',
        () async {
      final transcript = [
        '今天課堂先說明二元搜尋樹的定義與節點排序規則。',
        '接著講到插入流程要一路比較節點大小直到找到空位置。',
        '老師提醒刪除節點時要區分零個子節點、一個子節點與兩個子節點。',
        '如果遇到兩個子節點，通常會改找中序後繼來維持結構。',
        '最後用幾個 traversal 範例整理 preorder、inorder 與 postorder 的差異。',
      ].join();

      final summary = await service.summarizeTranscript(transcript);
      final lines = summary.split('\n');

      expect(lines.length, greaterThanOrEqualTo(2));
      expect(lines.every((line) => line.startsWith('• ')), isTrue);
      expect(summary, contains('二元搜尋樹'));
    });

    test('long punctuationless transcript does not fall back to raw transcript',
        () async {
      const transcript =
          '今天老師先介紹資料庫交易隔離層級接著比較read committed與repeatable read的差異然後說明phantom read為什麼會造成查詢結果不一致最後整理實務上如何依照商業需求選擇正確層級並觀察系統效能';

      final summary = await service.summarizeTranscript(transcript);

      expect(summary, startsWith('• '));
      expect(summary, isNot(equals(transcript)));
      expect(summary, isNot(equals('• $transcript。')));
    });
  });

  group('AndroidLocalLlmSummaryService', () {
    test('returns formatted local LLM bullets when runtime succeeds', () async {
      final service = AndroidLocalLlmSummaryService(
        runtime: const _SuccessfulLocalLlmRuntime(
          '1. 資料庫索引能加速查詢\n2. 但會增加寫入成本',
        ),
        fallbackService: const _ThrowingSummaryService(),
      );

      final summary = await service.summarizeTranscript(
        '今天課堂比較資料庫索引帶來的查詢優勢與寫入成本。',
      );

      expect(summary, '• 資料庫索引能加速查詢。\n• 但會增加寫入成本。');
    });

    test('falls back when Android local runtime is unavailable', () async {
      final service = AndroidLocalLlmSummaryService(
        runtime: const _UnavailableLocalLlmRuntime(),
        fallbackService:
            const _RecordingSummaryService('• extractive fallback。'),
      );

      final summary = await service.summarizeTranscript(
        '今天老師講解圖論中的最短路徑與鬆弛操作。',
      );

      expect(summary, '• extractive fallback。');
    });

    test('falls back when Android local runtime throws', () async {
      final service = AndroidLocalLlmSummaryService(
        runtime: const _ThrowingLocalLlmRuntime(),
        fallbackService:
            const _RecordingSummaryService('• fallback after failure。'),
      );

      final summary = await service.summarizeTranscript(
        '今天老師整理 transaction isolation level 的差異。',
      );

      expect(summary, '• fallback after failure。');
    });
  });
}

class _SuccessfulLocalLlmRuntime implements LocalLlmTranscriptSummaryRuntime {
  const _SuccessfulLocalLlmRuntime(this.summary);

  final String summary;

  @override
  Future<LocalLlmSummaryAttempt> summarizeTranscript(String transcript) async {
    return LocalLlmSummaryAttempt.success(summary);
  }
}

class _UnavailableLocalLlmRuntime implements LocalLlmTranscriptSummaryRuntime {
  const _UnavailableLocalLlmRuntime();

  @override
  Future<LocalLlmSummaryAttempt> summarizeTranscript(String transcript) async {
    return const LocalLlmSummaryAttempt.unavailable(
      reason: LocalLlmUnavailableReason.missingBundledModel,
      message: 'Bundled GGUF model asset is missing.',
    );
  }
}

class _ThrowingLocalLlmRuntime implements LocalLlmTranscriptSummaryRuntime {
  const _ThrowingLocalLlmRuntime();

  @override
  Future<LocalLlmSummaryAttempt> summarizeTranscript(String transcript) {
    throw StateError('llm crashed');
  }
}

class _RecordingSummaryService implements SummaryService {
  const _RecordingSummaryService(this.value);

  final String value;

  @override
  Future<String> summarizeTranscript(String transcript) async => value;
}

class _ThrowingSummaryService implements SummaryService {
  const _ThrowingSummaryService();

  @override
  Future<String> summarizeTranscript(String transcript) {
    throw StateError('fallback should not run');
  }
}
