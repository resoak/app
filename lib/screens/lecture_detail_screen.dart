import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_settings.dart';
import '../models/lecture.dart';
import '../providers/app_settings_provider.dart';
import '../providers/transcription_provider.dart';
import '../services/db_service.dart';
import '../services/lecture_share_service.dart';
import '../theme/lecture_vault_theme.dart';
import '../widgets/lecture_vault_background.dart';
import 'settings_screen.dart';

class LectureDetailScreen extends ConsumerStatefulWidget {
  const LectureDetailScreen({
    super.key,
    required this.lecture,
  });

  final Lecture lecture;

  @override
  ConsumerState<LectureDetailScreen> createState() =>
      _LectureDetailScreenState();
}

class _LectureDetailScreenState extends ConsumerState<LectureDetailScreen> {
  static const String _clearSelectionValue =
      '__lecture_vault_clear_selection__';

  final DbService _dbService = DbService();
  final LectureShareService _lectureShareService = LectureShareService();

  late AudioPlayer _audioPlayer;
  late Lecture _lecture;

  final List<StreamSubscription<dynamic>> _playerSubscriptions = [];
  StreamSubscription<void>? _dbChangesSub;

  bool _isPlaying = false;
  bool _isSharingBundle = false;
  bool _isSharingNotes = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _lecture = widget.lecture;
    _audioPlayer = AudioPlayer();

    final initialId = _lecture.id;
    if (initialId != null) {
      unawaited(_refreshLecture(initialId));
    }

    _dbChangesSub = _dbService.changes.listen((_) {
      final id = _lecture.id;
      if (id != null) {
        _refreshLecture(id);
      }
    });

    _playerSubscriptions.add(_audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() => _isPlaying = state == PlayerState.playing);
      }
    }));
    _playerSubscriptions.add(_audioPlayer.onDurationChanged.listen((value) {
      if (mounted) {
        setState(() => _duration = value);
      }
    }));
    _playerSubscriptions.add(_audioPlayer.onPositionChanged.listen((value) {
      if (mounted) {
        setState(() => _position = value);
      }
    }));
  }

  Future<void> _refreshLecture(int id) async {
    final updated = await _dbService.getLectureById(id);
    if (!mounted || updated == null) {
      return;
    }
    setState(() {
      _lecture = updated;
    });
  }

  Future<void> _togglePlayback() async {
    if (_isPlaying) {
      await _audioPlayer.pause();
      return;
    }

    final resolvedAudioPath = await _dbService.resolveAudioPath(_lecture);
    final file = File(resolvedAudioPath);
    final exists = await file.exists();

    if (!exists) {
      _showMessage('找不到音檔：$resolvedAudioPath');
      return;
    }

    await _audioPlayer.play(DeviceFileSource(resolvedAudioPath));
  }

  String _analysisTitle(String title) {
    final trimmed = title.trim();
    if (trimmed.toLowerCase().endsWith('analysis')) {
      return trimmed;
    }
    return '$trimmed Analysis';
  }

  List<LectureTimelineEntry> _buildTimelineEntries() {
    if (_lecture.timeline.isNotEmpty) {
      return _lecture.timeline;
    }

    if (_lecture.transcript.trim().isEmpty) {
      return const [];
    }

    final parts = _lecture.transcript
        .split(RegExp(r'[\n。．!?！？]+'))
        .map((segment) => segment.trim())
        .where((segment) => segment.length > 4)
        .take(12)
        .toList(growable: false);

    if (parts.isEmpty) {
      return const [];
    }

    final totalSeconds =
        _lecture.durationSeconds > 0 ? _lecture.durationSeconds : 3600;
    final step = totalSeconds / (parts.length + 1);

    return List.generate(parts.length, (index) {
      final seconds = ((index + 1) * step).round().clamp(0, totalSeconds);
      final text = parts[index].length > 100
          ? '${parts[index].substring(0, 97)}…'
          : parts[index];

      return LectureTimelineEntry(
        text: text,
        startMs: seconds * 1000,
        endMs: seconds * 1000,
        isEstimated: true,
      );
    }, growable: false);
  }

  String _formatHms(int seconds) {
    final h = (seconds ~/ 3600).toString().padLeft(2, '0');
    final m = ((seconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String _summaryParagraph() {
    if (_lecture.summaryStatus == LectureProcessingStatus.processing) {
      return '摘要產生中…';
    }
    if (_lecture.summaryStatus == LectureProcessingStatus.failed) {
      return '摘要產生失敗，請稍後再試。';
    }
    final summary = _lecture.summary.trim();
    if (summary.isEmpty) {
      return '尚無摘要。';
    }
    return summary;
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _persistLecture(
    Lecture updatedLecture, {
    String? successMessage,
  }) async {
    if (updatedLecture.id == null) {
      return;
    }

    await _dbService.updateLecture(updatedLecture);
    if (!mounted) {
      return;
    }

    setState(() {
      _lecture = updatedLecture;
    });

    if (successMessage != null && successMessage.trim().isNotEmpty) {
      _showMessage(successMessage);
    }
  }

  Future<void> _openSettingsScreen() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  Future<void> _showManagedLabelsEmptyDialog({
    required String title,
    required String description,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: LectureVaultColors.bgCard,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          title: Text(title, style: lvHeading(18)),
          content: Text(
            description,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: 14,
              height: 1.5,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(
                '稍後',
                style: lvMono(12, color: LectureVaultColors.textMuted),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _openSettingsScreen();
              },
              child: Text(
                '前往設定',
                style: lvMono(12, color: LectureVaultColors.blueElectric),
              ),
            ),
          ],
        );
      },
    );
  }

  List<String> _normalizeLabels(List<String> labels) {
    final normalized = <String>[];
    final seen = <String>{};

    for (final raw in labels) {
      final value = raw.trim();
      if (value.isEmpty || seen.contains(value)) {
        continue;
      }
      seen.add(value);
      normalized.add(value);
    }

    return normalized;
  }

  Future<String?> _showLabelPickerSheet({
    required String title,
    required String description,
    required List<String> labels,
    required String? currentValue,
    required String addMorePrompt,
  }) async {
    final normalizedLabels = _normalizeLabels(labels);
    if (normalizedLabels.isEmpty) {
      await _showManagedLabelsEmptyDialog(
        title: title,
        description: addMorePrompt,
      );
      return null;
    }

    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: LectureVaultColors.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        final activeValue = currentValue?.trim() ?? '';

        return SafeArea(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 420),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(title, style: lvHeading(20, weight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text(
                    description,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: normalizedLabels
                        .map(
                          (label) => ChoiceChip(
                            label: Text(label),
                            selected: label == activeValue,
                            showCheckmark: false,
                            onSelected: (_) =>
                                Navigator.pop(sheetContext, label),
                            labelStyle: lvMono(
                              11,
                              color: label == activeValue
                                  ? Colors.white
                                  : LectureVaultColors.textMuted,
                              weight: FontWeight.w600,
                            ),
                            selectedColor: LectureVaultColors.purple
                                .withValues(alpha: 0.34),
                            backgroundColor: Colors.transparent,
                            side: BorderSide(
                              color: label == activeValue
                                  ? LectureVaultColors.purpleBright
                                  : Colors.white.withValues(alpha: 0.16),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                          ),
                        )
                        .toList(growable: false),
                  ),
                  const SizedBox(height: 18),
                  InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () =>
                        Navigator.pop(sheetContext, _clearSelectionValue),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.layers_clear_rounded,
                            color: Colors.white.withValues(alpha: 0.75),
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '清除目前標籤',
                            style: lvMono(11,
                                color: Colors.white.withValues(alpha: 0.75)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      _openSettingsScreen();
                    },
                    icon: const Icon(
                      Icons.settings_outlined,
                      color: LectureVaultColors.blueElectric,
                    ),
                    label: Text(
                      '管理標籤清單',
                      style: lvMono(12, color: LectureVaultColors.blueElectric),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _editLectureLabel(List<String> lectureLabels) async {
    final selection = await _showLabelPickerSheet(
      title: '課程標籤',
      description: '從設定頁維護的課程標籤清單中選一個套用到這堂課。',
      labels: lectureLabels,
      currentValue: _lecture.tag,
      addMorePrompt: '設定頁目前沒有可用的課程標籤，先到設定裡建立清單後就能回來套用。',
    );

    if (!mounted || selection == null) {
      return;
    }

    final nextTag = selection == _clearSelectionValue ? '' : selection.trim();
    if (nextTag == _lecture.tag.trim()) {
      return;
    }

    await _persistLecture(
      _lecture.copyWith(tag: nextTag),
      successMessage: nextTag.isEmpty ? '已清除課程標籤' : '已更新課程標籤',
    );
  }

  Future<void> _editTimelineLabel(
    int index,
    List<String> timelineLabels,
  ) async {
    final entries = _buildTimelineEntries();
    if (index < 0 || index >= entries.length) {
      return;
    }

    final selection = await _showLabelPickerSheet(
      title: '時間軸標籤',
      description: '替這個時間點套用設定頁維護的時間軸標籤。',
      labels: timelineLabels,
      currentValue: entries[index].label,
      addMorePrompt: '設定頁目前沒有可用的時間軸標籤，先建立清單後就能標記這些段落。',
    );

    if (!mounted || selection == null) {
      return;
    }

    final updatedEntries = List<LectureTimelineEntry>.from(entries);
    if (selection == _clearSelectionValue) {
      updatedEntries[index] = updatedEntries[index].copyWith(clearLabel: true);
    } else {
      updatedEntries[index] =
          updatedEntries[index].copyWith(label: selection.trim());
    }

    await _persistLecture(
      _lecture.copyWith(timeline: updatedEntries),
      successMessage:
          selection == _clearSelectionValue ? '已清除時間軸標籤' : '已套用時間軸標籤',
    );
  }

  Future<void> _shareLectureBundle() async {
    if (_isSharingBundle || _isSharingNotes) {
      return;
    }

    setState(() => _isSharingBundle = true);
    try {
      await _lectureShareService.shareLectureBundle(_lecture);
    } on LectureShareException catch (error) {
      _showMessage(error.message);
    } finally {
      if (mounted) {
        setState(() => _isSharingBundle = false);
      }
    }
  }

  Future<void> _shareLectureNotes() async {
    if (_isSharingBundle || _isSharingNotes) {
      return;
    }

    setState(() => _isSharingNotes = true);
    try {
      await _lectureShareService.shareLectureNotes(_lecture);
    } on LectureShareException catch (error) {
      _showMessage(error.message);
    } finally {
      if (mounted) {
        setState(() => _isSharingNotes = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final timeline = _buildTimelineEntries();
    final transcriptionState = _lecture.id == null
        ? null
        : ref.watch(
            transcriptionProvider.select((states) => states[_lecture.id!]),
          );
    final settingsState = ref.watch(appSettingsProvider);
    final settings = settingsState.asData?.value;
    final lectureLabels = settings?.lectureLabels ??
        (settingsState.isLoading
            ? AppSettings.defaultLectureLabels
            : const <String>[]);
    final timelineLabels = settings?.timelineLabels ??
        (settingsState.isLoading
            ? AppSettings.defaultTimelineLabels
            : const <String>[]);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: LectureVaultBackground(
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              floating: true,
              pinned: false,
              backgroundColor: LectureVaultColors.bgDeep.withValues(alpha: 0.8),
              leading: IconButton(
                icon: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 40),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  Text(
                    _analysisTitle(_lecture.title),
                    style: lvHeading(22, weight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Generated by Local Neural Engine v3.2',
                    style: lvMono(11, color: LectureVaultColors.textMuted),
                  ),
                  const SizedBox(height: 18),
                  _buildLectureLabelCard(lectureLabels),
                  const SizedBox(height: 18),
                  _buildPlayerCard(),
                  if (transcriptionState != null) ...[
                    const SizedBox(height: 18),
                    _buildTranscriptionProgress(transcriptionState),
                  ],
                  const SizedBox(height: 18),
                  _buildShareCard(),
                  const SizedBox(height: 22),
                  _buildGlassSummary(),
                  const SizedBox(height: 28),
                  Text(
                    'SMART TIMELINE',
                    style: lvMono(
                      11,
                      color: LectureVaultColors.textMuted,
                      weight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '時間點可直接套用設定裡管理的自訂標籤。',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.62),
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildTimelineBlock(timeline, timelineLabels),
                  const SizedBox(height: 28),
                  Text(
                    'TRANSCRIPT',
                    style: lvMono(
                      11,
                      color: LectureVaultColors.textMuted,
                      weight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildTranscriptBox(),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLectureLabelCard(List<String> lectureLabels) {
    final currentTag = _lecture.tag.trim();
    final hasManagedLabels = lectureLabels.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: LectureVaultColors.bgCard.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'LECTURE LABEL',
                  style: lvMono(10, color: LectureVaultColors.textMuted),
                ),
                const SizedBox(height: 8),
                if (currentTag.isNotEmpty)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
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
                      '#$currentTag',
                      style: lvMono(11, color: LectureVaultColors.blueElectric),
                    ),
                  )
                else
                  Text(
                    '尚未分類',
                    style: lvMono(12, color: LectureVaultColors.textMuted),
                  ),
                const SizedBox(height: 10),
                Text(
                  hasManagedLabels
                      ? '目前可選 ${lectureLabels.length} 個課程標籤。'
                      : '設定頁目前沒有可用的課程標籤。',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.66),
                    fontSize: 12,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          TextButton.icon(
            onPressed: () => _editLectureLabel(lectureLabels),
            icon: const Icon(
              Icons.sell_outlined,
              size: 18,
              color: LectureVaultColors.purpleBright,
            ),
            label: Text(
              '編輯',
              style: lvMono(12, color: LectureVaultColors.purpleBright),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            LectureVaultColors.blueElectric.withValues(alpha: 0.18),
            LectureVaultColors.purple.withValues(alpha: 0.2),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          IconButton(
            iconSize: 52,
            icon: Icon(
              _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
              color: Colors.white,
            ),
            onPressed: _togglePlayback,
          ),
          Expanded(
            child: Column(
              children: [
                Slider(
                  activeColor: LectureVaultColors.purpleBright,
                  inactiveColor: Colors.white12,
                  value: _position.inSeconds.toDouble().clamp(
                        0,
                        _duration.inSeconds.toDouble() > 0
                            ? _duration.inSeconds.toDouble()
                            : 1.0,
                      ),
                  max: _duration.inSeconds.toDouble() > 0
                      ? _duration.inSeconds.toDouble()
                      : 1.0,
                  onChanged: (value) =>
                      _audioPlayer.seek(Duration(seconds: value.toInt())),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_formatHms(_position.inSeconds), style: lvMono(10)),
                      Text(_formatHms(_duration.inSeconds), style: lvMono(10)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShareCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: LectureVaultColors.bgCard.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: LectureVaultColors.blueElectric.withValues(alpha: 0.1),
            blurRadius: 22,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'EXPORT & SHARE',
            style: lvMono(10, color: LectureVaultColors.textMuted),
          ),
          const SizedBox(height: 8),
          Text('把這堂課帶去其他 App', style: lvHeading(18, weight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
            '可直接分享原始音檔與一份整理好的摘要 / 逐字稿文字檔，也能只匯出文字筆記。',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.68),
              fontSize: 13,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _ShareActionButton(
                  icon: Icons.ios_share_rounded,
                  label: _isSharingBundle ? '準備中…' : '分享音檔＋筆記',
                  accentColor: LectureVaultColors.blueElectric,
                  onTap: (_isSharingBundle || _isSharingNotes)
                      ? null
                      : _shareLectureBundle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ShareActionButton(
                  icon: Icons.note_alt_outlined,
                  label: _isSharingNotes ? '準備中…' : '匯出文字筆記',
                  accentColor: LectureVaultColors.purpleBright,
                  onTap: (_isSharingBundle || _isSharingNotes)
                      ? null
                      : _shareLectureNotes,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGlassSummary() {
    final paragraph = _summaryParagraph();
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: const Color(0xFF2D1B4E).withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            boxShadow: [
              BoxShadow(
                color: LectureVaultColors.purple.withValues(alpha: 0.15),
                blurRadius: 32,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('✨', style: lvHeading(16)),
                  const SizedBox(width: 8),
                  Text(
                    'AI 核心摘要',
                    style: lvHeading(16, weight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                paragraph,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.88),
                  fontSize: 14,
                  height: 1.65,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTranscriptionProgress(TranscriptionState transcriptionState) {
    final isError = transcriptionState.status == TranscriptionStatus.error;
    final progress = transcriptionState.progress.clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isError
            ? LectureVaultColors.stopRed.withValues(alpha: 0.12)
            : LectureVaultColors.blueElectric.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isError
              ? LectureVaultColors.stopRed.withValues(alpha: 0.24)
              : LectureVaultColors.blueElectric.withValues(alpha: 0.24),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isError
                ? '背景轉錄失敗，請稍後再試。'
                : 'AI 正在背景轉錄 ${(progress * 100).round()}%',
            style: lvMono(
              12,
              color: isError
                  ? LectureVaultColors.stopRed
                  : LectureVaultColors.blueElectric,
              weight: FontWeight.w600,
            ),
          ),
          if (!isError) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 10,
                backgroundColor: Colors.white.withValues(alpha: 0.08),
                valueColor: const AlwaysStoppedAnimation<Color>(
                  LectureVaultColors.blueElectric,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '完成後會自動更新摘要、逐字稿與時間軸。',
              style: lvMono(11, color: LectureVaultColors.textMuted),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTimelineBlock(
    List<LectureTimelineEntry> items,
    List<String> timelineLabels,
  ) {
    if (items.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: LectureVaultColors.bgCard.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Text(
          _lecture.transcript.trim().isEmpty ? '尚無可用時間軸，請先完成語音轉錄。' : '尚無時間軸資料。',
          style: lvMono(12, color: LectureVaultColors.textMuted),
        ),
      );
    }

    return Column(
      children: List.generate(items.length, (index) {
        final item = items[index];
        final isLast = index == items.length - 1;
        final dotColor = index.isEven
            ? LectureVaultColors.purpleBright
            : LectureVaultColors.blueElectric;
        final itemLabel = item.label?.trim() ?? '';

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 22,
                child: Column(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: dotColor,
                        boxShadow: [
                          BoxShadow(
                            color: dotColor.withValues(alpha: 0.45),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                    ),
                    if (!isLast)
                      Expanded(
                        child: Container(
                          width: 2,
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                dotColor.withValues(alpha: 0.7),
                                LectureVaultColors.blueElectric
                                    .withValues(alpha: 0.35),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(bottom: isLast ? 0 : 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            _formatHms((item.startMs / 1000).floor()),
                            style: lvMono(
                              12,
                              color: dotColor,
                              weight: FontWeight.w600,
                            ),
                          ),
                          if (itemLabel.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: dotColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: dotColor.withValues(alpha: 0.28),
                                ),
                              ),
                              child: Text(
                                itemLabel,
                                style: lvMono(10,
                                    color: dotColor, weight: FontWeight.w600),
                              ),
                            ),
                          ActionChip(
                            onPressed: () =>
                                _editTimelineLabel(index, timelineLabels),
                            avatar: Icon(
                              Icons.sell_outlined,
                              size: 15,
                              color: Colors.white.withValues(alpha: 0.72),
                            ),
                            label: Text(itemLabel.isEmpty ? '套用標籤' : '改標籤'),
                            labelStyle: lvMono(10,
                                color: Colors.white.withValues(alpha: 0.72)),
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.05),
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.1),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ],
                      ),
                      if (item.isEstimated) ...[
                        const SizedBox(height: 6),
                        Text(
                          '估算時間點',
                          style:
                              lvMono(10, color: LectureVaultColors.textMuted),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        item.text,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.82),
                          fontSize: 14,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildTranscriptBox() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: LectureVaultColors.bgCard.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Text(
        _lecture.transcript.isEmpty ? '尚無轉錄內容' : _lecture.transcript,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.72),
          fontSize: 14,
          height: 1.6,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _dbChangesSub?.cancel();
    for (final subscription in _playerSubscriptions) {
      subscription.cancel();
    }
    _audioPlayer.dispose();
    super.dispose();
  }
}

class _ShareActionButton extends StatelessWidget {
  const _ShareActionButton({
    required this.icon,
    required this.label,
    required this.accentColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color accentColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: onTap == null ? 0.08 : 0.14),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: accentColor.withValues(alpha: 0.24)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: accentColor, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style:
                      lvMono(11, color: accentColor, weight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
