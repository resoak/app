import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_vault/services/minilm_runtime_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('MiniLmRuntimeService loads model assets and returns embeddings',
      () async {
    const runtime = MiniLmRuntimeService();

    final embeddings = await runtime.embedSentences(const [
      '今天課堂整理資料庫索引與查詢最佳化。',
      '最後補充 transaction isolation level 的差異。',
    ]);

    expect(embeddings.length, 2);
    expect(embeddings.first.length, greaterThan(100));
    expect(
      embeddings.first.any((value) => value.abs() > 0.000001),
      isTrue,
    );
  });
}
