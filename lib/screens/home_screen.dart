import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';

import '../models/lecture.dart';
import '../providers/transcription_provider.dart';
import '../services/db_service.dart';
import '../theme/lecture_vault_theme.dart';
import '../utils/format_utils.dart';
import 'lecture_detail_screen.dart';
import 'recording_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  static const List<WhisperModel> _availableWhisperModels = [
    WhisperModel.base,
    WhisperModel.small,
  ];

  final DbService _dbService = DbService();
  StreamSubscription<void>? _dbChangesSub;
  List<Lecture> _lectures = [];
  final Map<int, String> _fileSizeById = {};
  bool _isLoadingLectures = true;
  int _refreshGeneration = 0;
  String _filterKey = 'all';
  String _searchQuery = '';
  int _bottomIndex = 0;
  int? _selectedLectureId;
  WhisperModel _selectedWhisperModel = WhisperModel.base;

  List<MapEntry<String, String>> get _filters {
    final tags = _lectures
        .map((lecture) => lecture.tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return [
      const MapEntry('all', '全部'),
      ...tags.map((tag) => MapEntry(tag, '#$tag')),
    ];
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
    final data = await _dbService.getAllLectures();

    if (!mounted || refreshGeneration != _refreshGeneration) return;

    setState(() {
      _lectures = data;
      _isLoadingLectures = false;
      if (_selectedLectureId != null &&
          !data.any((e) => e.id == _selectedLectureId)) {
        _selectedLectureId = null;
      }
      if (_selectedLectureId == null && data.isNotEmpty) {
        _selectedLectureId = data.first.id;
      }
    });

    final sizes = <int, String>{};
    for (final l in data) {
      if (l.id == null) continue;
      final f = File(l.audioPath);
      try {
        if (await f.exists()) {
          final bytes = await f.length();
          sizes[l.id!] = FormatUtils.formatBytes(bytes);
        } else {
          sizes[l.id!] = '—';
        }
      } catch (e) {
        sizes[l.id!] = '—';
      }
    }

    if (!mounted || refreshGeneration != _refreshGeneration) return;
    setState(() {
      _fileSizeById
        ..clear()
        ..addAll(sizes);
    });
  }

  bool _passesFilter(Lecture l) {
    if (_filterKey == 'all') return true;
    return l.tag.trim() == _filterKey;
  }

  List<Lecture> get _visibleLectures {
    var list = _lectures.where(_passesFilter).toList();
    final q = _searchQuery.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list
          .where(
            (e) =>
                e.title.toLowerCase().contains(q) ||
                e.transcript.toLowerCase().contains(q),
          )
          .toList();
    }
    return list;
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
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: LectureVaultColors.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('確認刪除', style: lvHeading(18)),
        content: Text(
          '刪除「${lecture.title}」？\n錄音檔案也會一併刪除。',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('取消',
                style: lvMono(14, color: LectureVaultColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('刪除',
                style: lvMono(14, color: LectureVaultColors.stopRed)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final file = File(lecture.audioPath);
    if (await file.exists()) await file.delete();

    await _dbService.deleteLecture(lecture.id!);
    _refreshData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LectureVaultColors.bgDeep,
      extendBody: true,
      body: SafeArea(
        bottom: false,
        child: _bottomIndex == 0 ? _buildHomeBody() : _buildSearchBody(),
      ),
      floatingActionButton: _buildFab(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildHomeBody() {
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
                    Text('LectureVault', style: lvHeading(26)),
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
                          style:
                              lvMono(11, color: LectureVaultColors.statusGreen),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.12)),
                  color: LectureVaultColors.bgCard,
                ),
                child: IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.person_outline_rounded,
                      color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildWhisperModelSelector(),
          const SizedBox(height: 18),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _filters.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final e = _filters[i];
                final selected = _filterKey == e.key;
                return FilterChip(
                  label: Text(e.value),
                  selected: selected,
                  onSelected: (_) => setState(() => _filterKey = e.key),
                  showCheckmark: false,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  labelStyle: lvMono(12,
                      color: selected
                          ? Colors.white
                          : LectureVaultColors.textMuted),
                  selectedColor: LectureVaultColors.purple,
                  backgroundColor: Colors.transparent,
                  side: BorderSide(
                    color: selected
                        ? LectureVaultColors.purpleBright
                        : Colors.white.withValues(alpha: 0.2),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
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
                    ? Center(
                        child: Text(
                          _lectures.isEmpty
                              ? '還沒有錄音\n點中央 + 開始錄音'
                              : _filterKey == 'all'
                                  ? '尚無課程'
                                  : '此標籤尚無課程',
                          textAlign: TextAlign.center,
                          style:
                              lvMono(14, color: LectureVaultColors.textMuted),
                        ),
                      )
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

  Widget _buildWhisperModelSelector() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: LectureVaultColors.bgCard,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'WHISPER MODEL',
            style: lvMono(10, color: LectureVaultColors.textMuted),
          ),
          const SizedBox(height: 6),
          Text(
            '新錄音將使用所選模型進行背景轉錄',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.62),
              fontSize: 12,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _availableWhisperModels.map((model) {
              final isSelected = _selectedWhisperModel == model;
              return ChoiceChip(
                label: Text(_whisperModelLabel(model)),
                selected: isSelected,
                showCheckmark: false,
                onSelected: (_) {
                  setState(() => _selectedWhisperModel = model);
                },
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                labelStyle: lvMono(
                  11,
                  color:
                      isSelected ? Colors.white : LectureVaultColors.textMuted,
                  weight: FontWeight.w600,
                ),
                selectedColor:
                    LectureVaultColors.purple.withValues(alpha: 0.36),
                backgroundColor: Colors.transparent,
                side: BorderSide(
                  color: isSelected
                      ? LectureVaultColors.purpleBright
                      : Colors.white.withValues(alpha: 0.16),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('搜尋', style: lvHeading(22)),
          const SizedBox(height: 12),
          TextField(
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: '標題或轉錄內容…',
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
              filled: true,
              fillColor: LectureVaultColors.bgCard,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide:
                    BorderSide(color: Colors.white.withValues(alpha: 0.08)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide:
                    BorderSide(color: Colors.white.withValues(alpha: 0.08)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide:
                    const BorderSide(color: LectureVaultColors.purpleBright),
              ),
              prefixIcon:
                  const Icon(Icons.search, color: LectureVaultColors.textMuted),
            ),
            onChanged: (v) => setState(() => _searchQuery = v),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _visibleLectures.isEmpty
                ? Center(
                    child: Text(
                      '沒有符合的結果',
                      style: lvMono(14, color: LectureVaultColors.textMuted),
                    ),
                  )
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
    final sizeLabel =
        lecture.id != null ? (_fileSizeById[lecture.id!] ?? '—') : '—';
    final transcriptionState = lecture.id == null
        ? null
        : ref.watch(
            transcriptionProvider.select((states) => states[lecture.id!]),
          );
    final isTranscribing =
        transcriptionState?.status == TranscriptionStatus.transcribing;
    final hasCompletedSummary =
        lecture.summary.trim().isNotEmpty && lecture.summary.trim() != '背景轉錄中…';

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
              color: isSelected
                  ? LectureVaultColors.bgCardActive
                  : LectureVaultColors.bgCard,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(
                color: isSelected
                    ? LectureVaultColors.borderActive
                    : Colors.white.withValues(alpha: 0.06),
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
                      style: lvMono(10, color: LectureVaultColors.textMuted),
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
                          '轉錄中 ${(transcriptionState!.progress * 100).round()}%',
                          style: lvMono(10,
                              color: LectureVaultColors.blueElectric),
                        ),
                      )
                    else if (transcriptionState?.status ==
                        TranscriptionStatus.error)
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
                          style: lvMono(10, color: LectureVaultColors.stopRed),
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
                          style: lvMono(10,
                              color: LectureVaultColors.purpleBright),
                        ),
                      ),
                    PopupMenuButton<String>(
                      icon: Icon(
                        Icons.more_horiz_rounded,
                        color: Colors.white.withValues(alpha: 0.45),
                      ),
                      color: LectureVaultColors.bgCard,
                      onSelected: (v) {
                        if (v == 'delete') _deleteLecture(lecture);
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'delete',
                          child: Text('刪除',
                              style: lvMono(13,
                                  color: LectureVaultColors.stopRed)),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  lecture.title,
                  style: lvHeading(17, weight: FontWeight.w600),
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
                      style: lvMono(12, color: LectureVaultColors.textMuted),
                    ),
                    const SizedBox(width: 18),
                    Icon(Icons.sd_storage_outlined,
                        size: 16,
                        color: LectureVaultColors.purpleBright
                            .withValues(alpha: 0.85)),
                    const SizedBox(width: 6),
                    Text(
                      sizeLabel,
                      style: lvMono(12, color: LectureVaultColors.textMuted),
                    ),
                  ],
                ),
                if (isTranscribing) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: transcriptionState!.progress.clamp(0.0, 1.0),
                      minHeight: 8,
                      backgroundColor: Colors.white.withValues(alpha: 0.08),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        LectureVaultColors.blueElectric,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'AI 正在背景轉錄這段錄音',
                    style: lvMono(11, color: LectureVaultColors.textMuted),
                  ),
                ],
                if (lecture.tag.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
                      '#${lecture.tag.trim()}',
                      style: lvMono(11, color: LectureVaultColors.blueElectric),
                    ),
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
          onTap: () async {
            final res = await Navigator.push<bool>(
              context,
              MaterialPageRoute(
                builder: (_) => RecordingScreen(
                  whisperModel: _selectedWhisperModel,
                ),
              ),
            );
            if (res == true) _refreshData();
          },
          child: const Center(
            child: Icon(Icons.add, color: Colors.white, size: 34),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return BottomAppBar(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: const Color(0xFF0B1120),
      shape: const CircularNotchedRectangle(),
      notchMargin: 10,
      child: Row(
        children: [
          IconButton(
            onPressed: () => setState(() => _bottomIndex = 0),
            icon: Icon(
              Icons.home_rounded,
              color: _bottomIndex == 0
                  ? Colors.white
                  : LectureVaultColors.textMuted,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: () => setState(() => _bottomIndex = 1),
            icon: Icon(
              Icons.search_rounded,
              color: _bottomIndex == 1
                  ? Colors.white
                  : LectureVaultColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _dbChangesSub?.cancel();
    super.dispose();
  }
}
