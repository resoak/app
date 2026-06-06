import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';

import '../models/app_settings.dart';
import '../models/lecture.dart';
import '../providers/app_settings_provider.dart';
import '../providers/transcription_provider.dart';
import '../services/audio_import_service.dart';
import '../services/db_service.dart';
import '../services/minilm_runtime_service.dart';
import '../theme/lecture_vault_theme.dart';
import '../utils/format_utils.dart';
import '../widgets/lecture_vault_background.dart';
import 'lecture_detail_screen.dart';
import 'recording_screen.dart';
import 'settings_screen.dart';

String transcriptionProgressBadgeLabel(TranscriptionState? transcriptionState) {
  if (transcriptionState == null) {
    return '轉錄中…';
  }

  final progressPercent =
      (transcriptionState.progress.clamp(0.0, 1.0) * 100).round();
  return '轉錄中 $progressPercent%';
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final DbService _dbService = DbService();
  final AudioImportService _audioImportService = AudioImportService();
  StreamSubscription<void>? _dbChangesSub;
  List<Lecture> _lectures = [];
  List<Lecture> _visibleLectures = [];
  List<MapEntry<String, String>> _cachedFilters = [const MapEntry('all', '全部')];
  final Map<int, String> _fileSizeById = {};
  bool _isLoadingLectures = true;
  int _refreshGeneration = 0;
  String _filterKey = 'all';
  String _searchQuery = '';
  bool _isSemanticSearching = false;
  Timer? _searchDebounce;
  int _semanticSearchGeneration = 0;
  int _bottomIndex = 0;
  int? _selectedLectureId;

  void _updateFilters() {
    final allTags = _lectures
        .expand((lecture) => lecture.tags)
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    _cachedFilters = [
      const MapEntry('all', '全部'),
      ...allTags.map((tag) => MapEntry(tag, '#$tag')),
    ];
  }

  void _updateVisibleLectures() {
    final q = _searchQuery.trim().toLowerCase();

    _visibleLectures = _lectures.where((l) {
      // 標籤篩選
      if (_filterKey != 'all' && !l.tags.any((t) => t.trim() == _filterKey)) {
        return false;
      }
      // 搜尋關鍵字
      if (q.isNotEmpty) {
        return l.title.toLowerCase().contains(q) ||
            l.transcript.toLowerCase().contains(q) ||
            l.summary.toLowerCase().contains(q);
      }
      return true;
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _dbChangesSub = _dbService.changes.listen((_) {
      if (mounted) {
        _refreshData();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _refreshData();
    });
  }

  Future<void> _refreshData() async {
    final refreshGeneration = ++_refreshGeneration;
    final data = await _dbService.getAllLectures(includeEmbeddings: false);

    if (!mounted || refreshGeneration != _refreshGeneration) return;

    setState(() {
      _lectures = data;
      _isLoadingLectures = false;
      _updateFilters();
      _updateVisibleLectures();

      if (_selectedLectureId != null &&
          !data.any((e) => e.id == _selectedLectureId)) {
        _selectedLectureId = null;
      }
      if (_selectedLectureId == null && data.isNotEmpty) {
        _selectedLectureId = data.first.id;
      }
    });

    final sizeEntries = await Future.wait(data.map(_loadLectureFileSize));
    final sizes = <int, String>{
      for (final entry in sizeEntries)
        if (entry != null) entry.key: entry.value,
    };

    if (!mounted || refreshGeneration != _refreshGeneration) return;
    setState(() {
      _fileSizeById
        ..clear()
        ..addAll(sizes);
    });
  }

  Future<MapEntry<int, String>?> _loadLectureFileSize(Lecture lecture) async {
    final lectureId = lecture.id;
    if (lectureId == null) return null;

    try {
      final file = await _dbService.resolveSafeAudioFile(lecture);
      if (!await file.exists()) {
        return MapEntry(lectureId, '—');
      }

      final bytes = await file.length();
      return MapEntry(lectureId, FormatUtils.formatBytes(bytes));
    } catch (_) {
      return MapEntry(lectureId, '—');
    }
  }

  void _setFilter(String key) {
    if (_filterKey == key) return;
    setState(() {
      _filterKey = key;
      _updateVisibleLectures();
    });
  }

  void _setSearchQuery(String query) {
    if (_searchQuery == query) return;
    _searchDebounce?.cancel();

    final normalizedQuery = query.trim();
    final shouldRunSemanticSearch = normalizedQuery.length >= 2;

    setState(() {
      _searchQuery = query;
      _semanticSearchGeneration++;
      _isSemanticSearching = false;
      _updateVisibleLectures(); // 立即進行關鍵字過濾，保持反應靈敏
    });

    // 語義搜尋防抖：延遲 600ms 後執行 AI 向量運算
    if (shouldRunSemanticSearch) {
      final generation = _semanticSearchGeneration;
      _searchDebounce = Timer(
        const Duration(milliseconds: 600),
        () => unawaited(
          _performSemanticSearch(normalizedQuery, generation),
        ),
      );
    }
  }

  void _setBottomIndex(int index) {
    if (_bottomIndex == index) return;
    setState(() => _bottomIndex = index);
  }

  Future<void> _performSemanticSearch(String query, int generation) async {
    if (!mounted || generation != _semanticSearchGeneration) return;

    setState(() => _isSemanticSearching = true);

    List<Lecture> semanticResults = const [];
    try {
      // 1. 將搜尋詞轉換為 384 維向量
      final queryVectors =
          await const MiniLmRuntimeService().embedSentences([query]);
      if (queryVectors.isEmpty) {
        semanticResults = const [];
      } else {
        // 2. 從資料庫進行向量相似度檢索 (Threshold 設為 0.3)
        semanticResults = await _dbService.searchLecturesBySimilarity(
          queryVectors.first,
          threshold: 0.25, // 放寬門檻，讓更多相關內容出現
        );
      }
    } catch (e) {
      debugPrint('語義搜尋失敗: $e');
    }

    if (!mounted ||
        generation != _semanticSearchGeneration ||
        _searchQuery.trim() != query) {
      return;
    }

    setState(() {
      // 如果語義搜尋有結果，優先顯示（或與關鍵字結果合併）
      // 這裡我們採取覆蓋策略，因為 searchLecturesBySimilarity 已經包含了排序
      if (semanticResults.isNotEmpty) {
        _visibleLectures = semanticResults;
      }
      _isSemanticSearching = false;
    });
  }

  String _whisperModelLabel(WhisperModel model) {
    switch (model) {
      case WhisperModel.base:
        return 'BASE';
      case WhisperModel.small:
        return 'SMALL';
      default:
        return model.name.toUpperCase();
    }
  }

  Future<void> _deleteLecture(Lecture lecture) async {
    final palette = context.lvPalette;
    final scheme = Theme.of(context).colorScheme;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: palette.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('確認刪除', style: ctx.lvHeading(18)),
        content: Text(
          '刪除「${lecture.title}」？\n錄音檔案也會一併刪除。',
          style: TextStyle(color: palette.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('取消', style: ctx.lvMono(14, color: palette.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('刪除', style: ctx.lvMono(14, color: scheme.error)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await _dbService.deleteLecture(lecture);
    _refreshData();
  }

  Future<void> _renameLecture(Lecture lecture) async {
    final palette = context.lvPalette;

    final controller = TextEditingController(text: lecture.title);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: palette.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('重新命名', style: ctx.lvHeading(18)),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: '輸入新名稱',
            hintStyle: TextStyle(color: palette.textMuted),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: palette.borderSubtle),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: LectureVaultColors.blueElectric),
            ),
          ),
          style: context.lvMono(14, color: palette.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('取消', style: ctx.lvMono(14, color: palette.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text('儲存',
                style: ctx.lvMono(14, color: LectureVaultColors.blueElectric)),
          ),
        ],
      ),
    );

    if (newTitle == null || newTitle.isEmpty || newTitle == lecture.title) {
      return;
    }

    await _dbService.updateLecture(lecture.copyWith(title: newTitle));
  }

  Future<void> _editTag(String oldTag) async {
    final palette = context.lvPalette;

    final controller = TextEditingController(text: oldTag);
    final newTag = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: palette.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('編輯標籤', style: ctx.lvHeading(18)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: palette.textPrimary),
          decoration: InputDecoration(
            labelText: '標籤名稱',
            labelStyle: TextStyle(color: palette.textMuted),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: palette.borderSubtle),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: LectureVaultColors.purpleBright),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('取消', style: ctx.lvMono(14, color: palette.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text('儲存',
                style: ctx.lvMono(14, color: LectureVaultColors.purpleBright)),
          ),
        ],
      ),
    );

    if (newTag == null || newTag.isEmpty || newTag == oldTag) return;

    // Update lectures in DB
    await _dbService.updateLectureTag(oldTag, newTag);
    // Update label in AppSettings
    await ref
        .read(appSettingsProvider.notifier)
        .updateLectureLabel(oldTag, newTag);

    if (_filterKey == oldTag) {
      setState(() => _filterKey = newTag);
    }
    _refreshData();
  }

  Future<void> _openCreateLectureSheet() async {
    final palette = context.lvPalette;

    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.mic_rounded, color: palette.textPrimary),
                title: Text('開始錄音', style: context.lvHeading(16)),
                subtitle: Text(
                  '建立新的現場錄音並在背景轉錄',
                  style: TextStyle(color: palette.textSecondary),
                ),
                onTap: () => Navigator.pop(context, 'record'),
              ),
              ListTile(
                leading:
                    Icon(Icons.audio_file_rounded, color: palette.textPrimary),
                title: Text('匯入音檔', style: context.lvHeading(16)),
                subtitle: Text(
                  '複製本機音檔到受管儲存並開始轉錄',
                  style: TextStyle(color: palette.textSecondary),
                ),
                onTap: () => Navigator.pop(context, 'import'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (!mounted || action == null) return;

    if (action == 'record') {
      await _startRecordingLecture();
      return;
    }
    if (action == 'import') {
      await _importAudioLecture();
    }
  }

  Future<void> _startRecordingLecture() async {
    final selectedWhisperModel =
        ref.read(appSettingsProvider).asData?.value.preferredWhisperModel ??
            AppSettings.defaultWhisperModel;
    final res = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => RecordingScreen(
          whisperModel: selectedWhisperModel,
        ),
      ),
    );
    if (res == true) {
      _refreshData();
    }
  }

  Future<void> _importAudioLecture() async {
    // 顯示進度指示器，避免大檔案匯入時沒反應
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final selectedWhisperModel =
          ref.read(appSettingsProvider).asData?.value.preferredWhisperModel ??
              AppSettings.defaultWhisperModel;
      final importedLecture = await _audioImportService.pickAndImportLecture();

      if (!mounted) return;
      Navigator.pop(context); // 關閉進度指示器

      if (importedLecture == null) {
        return;
      }

      unawaited(
        ref.read(transcriptionProvider.notifier).transcribeLecture(
              importedLecture,
              whisperModel: selectedWhisperModel,
            ),
      );

      _refreshData();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已匯入「${importedLecture.title}」，正在背景轉錄。')),
      );
    } catch (error) {
      if (!mounted) return;
      Navigator.pop(context); // 確保對話框關閉
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('音檔匯入失敗：$error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedWhisperModel = ref.watch(
      appSettingsProvider.select(
        (state) =>
            state.asData?.value.preferredWhisperModel ??
            AppSettings.defaultWhisperModel,
      ),
    );
    final palette = context.lvPalette;

    return LectureVaultBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: true,
        extendBodyBehindAppBar: true, // 確保背景延伸到頂部狀態欄
        body: SafeArea(
          bottom: false,
          child: _bottomIndex == 0
              ? _buildHomeBody(selectedWhisperModel)
              : _buildSearchBody(),
        ),
        floatingActionButton: _buildFab(),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
        bottomNavigationBar: _buildBottomBar(palette),
      ),
    );
  }

  Widget _buildHomeBody(WhisperModel selectedWhisperModel) {
    final palette = context.lvPalette;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('LectureVault', style: context.lvHeading(26)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: LectureVaultColors.statusGreen,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Color(0x5522C55E),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'LOCAL_AI_READY',
                          style: context.lvMono(
                            11,
                            color: LectureVaultColors.statusGreen,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: palette.borderSubtle),
                  color: palette.surface,
                ),
                child: IconButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const SettingsScreen(),
                      ),
                    );
                  },
                  icon: Icon(
                    Icons.person_outline_rounded,
                    color: palette.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildWhisperModelSelector(selectedWhisperModel),
          const SizedBox(height: 18),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _cachedFilters.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final e = _cachedFilters[i];
                final selected = _filterKey == e.key;
                return GestureDetector(
                  onLongPress: e.key == 'all' ? null : () => _editTag(e.key),
                  child: FilterChip(
                    label: Text(e.value),
                    selected: selected,
                    onSelected: (_) => _setFilter(e.key),
                    showCheckmark: false,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    labelStyle: context.lvMono(
                      12,
                      color: selected ? Colors.white : palette.textMuted,
                    ),
                    selectedColor: LectureVaultColors.purple,
                    backgroundColor: Colors.transparent,
                    side: BorderSide(
                      color: selected
                          ? LectureVaultColors.purpleBright
                          : palette.borderSubtle,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: _isLoadingLectures
                ? const Center(child: CircularProgressIndicator())
                : _visibleLectures.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        padding: EdgeInsets.zero,
                        itemCount: _visibleLectures.length,
                        itemBuilder: (context, index) {
                          final lecture = _visibleLectures[index];
                          final isSelected = lecture.id == _selectedLectureId;
                          return _buildLectureCard(lecture, isSelected);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final bool isSearchOrFilter =
        _filterKey != 'all' || _searchQuery.isNotEmpty;
    final palette = context.lvPalette;

    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: palette.surface,
                border: Border.all(color: palette.borderSubtle),
              ),
              child: Icon(
                isSearchOrFilter
                    ? Icons.search_off_rounded
                    : Icons.mic_none_rounded,
                size: 64,
                color: palette.textMuted.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              isSearchOrFilter ? '找不到符合的內容' : '這裡空空如也',
              style: context.lvHeading(18),
            ),
            const SizedBox(height: 8),
            Text(
              isSearchOrFilter
                  ? '請嘗試更換標籤或關鍵字'
                  : '點擊下方的 + 按鈕開始您的第一份錄音\n所有 AI 運算皆在本地完成',
              textAlign: TextAlign.center,
              style: context.lvMono(12, color: palette.textMuted),
            ),
            if (!isSearchOrFilter) ...[
              const SizedBox(height: 32),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: LectureVaultColors.statusGreen
                          .withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.security_rounded,
                        size: 14, color: LectureVaultColors.statusGreen),
                    const SizedBox(width: 8),
                    Text('隱私保護中：無外部伺服器存取',
                        style: context.lvMono(
                          10,
                          color: LectureVaultColors.statusGreen,
                        )),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildWhisperModelSelector(WhisperModel selectedWhisperModel) {
    final palette = context.lvPalette;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'WHISPER MODEL',
            style: context.lvMono(10, color: palette.textMuted),
          ),
          const SizedBox(height: 6),
          Text(
            '新錄音將使用所選模型進行背景轉錄',
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: 12,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: AppSettings.availableWhisperModels.map((model) {
              final isSelected = selectedWhisperModel == model;
              return ChoiceChip(
                label: Text(_whisperModelLabel(model)),
                selected: isSelected,
                showCheckmark: false,
                onSelected: (_) {
                  ref
                      .read(appSettingsProvider.notifier)
                      .updatePreferredWhisperModel(model);
                },
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                labelStyle: context.lvMono(
                  11,
                  color: isSelected ? Colors.white : palette.textMuted,
                  weight: FontWeight.w600,
                ),
                selectedColor:
                    LectureVaultColors.purple.withValues(alpha: 0.36),
                backgroundColor: Colors.transparent,
                side: BorderSide(
                  color: isSelected
                      ? LectureVaultColors.purpleBright
                      : palette.borderSubtle,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              );
            }).toList(growable: false),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBody() {
    final palette = context.lvPalette;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('搜尋', style: context.lvHeading(22)),
          const SizedBox(height: 12),
          TextField(
            autofocus: true,
            style: TextStyle(color: palette.textPrimary),
            decoration: InputDecoration(
              hintText: '標題或轉錄內容…',
              hintStyle:
                  TextStyle(color: palette.textMuted.withValues(alpha: 0.55)),
              filled: true,
              fillColor: palette.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: palette.borderSubtle),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: palette.borderSubtle),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide:
                    const BorderSide(color: LectureVaultColors.purpleBright),
              ),
              prefixIcon: Icon(Icons.search, color: palette.textMuted),
              suffixIcon: _isSemanticSearching
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: Padding(
                        padding: EdgeInsets.all(12.0),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(
                              LectureVaultColors.purpleBright),
                        ),
                      ),
                    )
                  : (_searchQuery.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.close, color: palette.textMuted),
                          onPressed: () {
                            _setSearchQuery('');
                            FocusScope.of(context).unfocus();
                          },
                        )
                      : null),
            ),
            onChanged: _setSearchQuery,
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _visibleLectures.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    itemCount: _visibleLectures.length,
                    itemBuilder: (context, index) {
                      final lecture = _visibleLectures[index];
                      final isSelected = lecture.id == _selectedLectureId;
                      return _buildLectureCard(lecture, isSelected);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildLectureCard(Lecture lecture, bool isSelected) {
    final palette = context.lvPalette;

    final sizeLabel =
        lecture.id != null ? (_fileSizeById[lecture.id!] ?? '—') : '—';
    final transcriptionState = lecture.id == null
        ? null
        : ref.watch(
            transcriptionProvider.select((states) => states[lecture.id!]),
          );
    final effectiveTranscriptionStatus =
        transcriptionState?.status == TranscriptionStatus.transcribing
            ? LectureProcessingStatus.processing
            : transcriptionState?.status == TranscriptionStatus.error
                ? LectureProcessingStatus.failed
                : lecture.transcriptionStatus;
    final isTranscribing =
        effectiveTranscriptionStatus == LectureProcessingStatus.processing;
    final hasCompletedSummary =
        lecture.summaryStatus == LectureProcessingStatus.completed &&
            lecture.summary.trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(26),
          onTap: () {
            setState(() => _selectedLectureId = lecture.id);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => LectureDetailScreen(lecture: lecture),
              ),
            ).then((_) => _refreshData());
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.fromLTRB(18, 16, 12, 16),
            decoration: BoxDecoration(
              color: isSelected ? palette.surfaceSelected : palette.surface,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(
                color: isSelected ? palette.borderStrong : palette.borderSubtle,
                width: isSelected ? 1.5 : 1,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color:
                            LectureVaultColors.purple.withValues(alpha: 0.25),
                        blurRadius: 24,
                        spreadRadius: 0,
                      ),
                    ]
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      lecture.date,
                      style: context.lvMono(10, color: palette.textMuted),
                    ),
                    const Spacer(),
                    if (isTranscribing)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: LectureVaultColors.blueElectric
                              .withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          transcriptionProgressBadgeLabel(transcriptionState),
                          style: context.lvMono(10,
                              color: LectureVaultColors.blueElectric),
                        ),
                      )
                    else if (effectiveTranscriptionStatus ==
                        LectureProcessingStatus.failed)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: LectureVaultColors.stopRed
                              .withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '轉錄失敗',
                          style: context.lvMono(10,
                              color: LectureVaultColors.stopRed),
                        ),
                      )
                    else if (hasCompletedSummary)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color:
                              LectureVaultColors.purple.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '已總結',
                          style: context.lvMono(10,
                              color: LectureVaultColors.purpleBright),
                        ),
                      ),
                    PopupMenuButton<String>(
                      icon: Icon(
                        Icons.more_horiz_rounded,
                        color: palette.textMuted,
                      ),
                      color: palette.surface,
                      onSelected: (v) {
                        if (v == 'delete') _deleteLecture(lecture);
                        if (v == 'rename') _renameLecture(lecture);
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'rename',
                          child: Text('重新命名',
                              style: context.lvMono(13,
                                  color: palette.textPrimary)),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text('刪除',
                              style: context.lvMono(13,
                                  color: LectureVaultColors.stopRed)),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  lecture.title,
                  style: context.lvHeading(17, weight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.schedule_rounded,
                        size: 16,
                        color: LectureVaultColors.blueElectric
                            .withValues(alpha: 0.9)),
                    const SizedBox(width: 6),
                    Text(
                      FormatUtils.formatDuration(lecture.durationSeconds),
                      style: context.lvMono(12, color: palette.textMuted),
                    ),
                    const SizedBox(width: 18),
                    Icon(Icons.sd_storage_outlined,
                        size: 16,
                        color: LectureVaultColors.purpleBright
                            .withValues(alpha: 0.85)),
                    const SizedBox(width: 6),
                    Text(
                      sizeLabel,
                      style: context.lvMono(12, color: palette.textMuted),
                    ),
                  ],
                ),
                if (isTranscribing && transcriptionState != null) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: transcriptionState.progress.clamp(0.0, 1.0),
                      minHeight: 8,
                      backgroundColor: palette.borderSubtle,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        LectureVaultColors.blueElectric,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'AI 正在背景轉錄這段錄音',
                    style: context.lvMono(11, color: palette.textMuted),
                  ),
                ],
                if (lecture.tags.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: lecture.tags.map((tag) {
                      final trimmed = tag.trim();
                      if (trimmed.isEmpty) return const SizedBox.shrink();
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: LectureVaultColors.blueElectric
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: LectureVaultColors.blueElectric
                                .withValues(alpha: 0.25),
                          ),
                        ),
                        child: Text(
                          '#$trimmed',
                          style: context.lvMono(11,
                              color: LectureVaultColors.blueElectric),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFab() {
    return Container(
      height: 68,
      width: 68,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [
            LectureVaultColors.blueElectric,
            LectureVaultColors.purple,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: LectureVaultColors.purpleBright.withValues(alpha: 0.55),
            blurRadius: 22,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: _openCreateLectureSheet,
          child: const Center(
            child: Icon(Icons.add, color: Colors.white, size: 34),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar(LectureVaultPalette palette) {
    return BottomAppBar(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: palette.chromeSurface,
      shape: const CircularNotchedRectangle(),
      notchMargin: 10,
      child: Row(
        children: [
          IconButton(
            onPressed: () => _setBottomIndex(0),
            icon: Icon(
              Icons.home_rounded,
              color:
                  _bottomIndex == 0 ? palette.textPrimary : palette.textMuted,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: () => _setBottomIndex(1),
            icon: Icon(
              Icons.search_rounded,
              color:
                  _bottomIndex == 1 ? palette.textPrimary : palette.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _dbChangesSub?.cancel();
    super.dispose();
  }
}
