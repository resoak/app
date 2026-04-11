import 'dart:io';
import 'dart:async';
import 'dart:ui';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../models/lecture.dart';
import '../services/db_service.dart';
import '../theme/lecture_vault_theme.dart';

class LectureDetailScreen extends StatefulWidget {
  final Lecture lecture;
  const LectureDetailScreen({super.key, required this.lecture});

  @override
  State<LectureDetailScreen> createState() => _LectureDetailScreenState();
}

class _LectureDetailScreenState extends State<LectureDetailScreen> {
  final DbService _dbService = DbService();
  late AudioPlayer _audioPlayer;
  late Lecture _lecture;
  final List<StreamSubscription<dynamic>> _playerSubscriptions = [];
  StreamSubscription<void>? _dbChangesSub;
  bool _isPlaying = false;
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
      if (mounted) setState(() => _isPlaying = state == PlayerState.playing);
    }));
    _playerSubscriptions
        .add(_audioPlayer.onDurationChanged.listen((newDuration) {
      if (mounted) setState(() => _duration = newDuration);
    }));
    _playerSubscriptions
        .add(_audioPlayer.onPositionChanged.listen((newPosition) {
      if (mounted) setState(() => _position = newPosition);
    }));
  }

  Future<void> _refreshLecture(int id) async {
    final updated = await _dbService.getLectureById(id);
    if (!mounted || updated == null) return;
    setState(() {
      _lecture = updated;
    });
  }

  Future<void> _togglePlayback() async {
    if (_isPlaying) {
      await _audioPlayer.pause();
    } else {
      final file = File(_lecture.audioPath);
      final exists = await file.exists();

      if (!exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('找不到音檔：${_lecture.audioPath}')),
          );
        }
        return;
      }
      await _audioPlayer.play(DeviceFileSource(_lecture.audioPath));
    }
  }

  String _analysisTitle(String title) {
    final t = title.trim();
    if (t.toLowerCase().endsWith('analysis')) return t;
    return '$t Analysis';
  }

  List<_TimelineItem> _buildTimeline() {
    final l = _lecture;
    if (l.timeline.isNotEmpty) {
      return l.timeline
          .map(
            (entry) => _TimelineItem(
              _formatHms((entry.startMs / 1000).floor()),
              entry.text,
              isEstimated: entry.isEstimated,
            ),
          )
          .toList(growable: false);
    }
    if (l.transcript.trim().isEmpty) {
      return const [
        _TimelineItem('00:00:00', '尚無可用時間軸，請先完成語音轉錄。'),
      ];
    }
    final parts = l.transcript
        .split(RegExp(r'[\n。．!?！？]+'))
        .map((s) => s.trim())
        .where((s) => s.length > 4)
        .take(12)
        .toList();
    if (parts.isEmpty) {
      return const [
        _TimelineItem('00:00:00', '尚無時間軸資料'),
      ];
    }
    final totalSec = l.durationSeconds > 0 ? l.durationSeconds : 3600;
    final step = totalSec / (parts.length + 1);
    return List.generate(parts.length, (i) {
      final sec = ((i + 1) * step).round().clamp(0, totalSec);
      final text =
          parts[i].length > 100 ? '${parts[i].substring(0, 97)}…' : parts[i];
      return _TimelineItem(_formatHms(sec), text, isEstimated: true);
    });
  }

  String _formatHms(int seconds) {
    final h = (seconds ~/ 3600).toString().padLeft(2, '0');
    final m = ((seconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String _summaryParagraph() {
    final s = _lecture.summary.trim();
    if (s.isEmpty) {
      return '尚無摘要。';
    }
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final timeline = _buildTimeline();

    return Scaffold(
      backgroundColor: LectureVaultColors.bgDeep,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            pinned: false,
            backgroundColor: LectureVaultColors.bgDeep.withValues(alpha: 0.92),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white, size: 20),
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
                const SizedBox(height: 22),
                _buildPlayerCard(),
                const SizedBox(height: 22),
                _buildGlassSummary(),
                const SizedBox(height: 28),
                Text(
                  'SMART TIMELINE',
                  style: lvMono(11,
                      color: LectureVaultColors.textMuted,
                      weight: FontWeight.w600),
                ),
                const SizedBox(height: 16),
                _buildTimelineBlock(timeline),
                const SizedBox(height: 28),
                Text(
                  'TRANSCRIPT',
                  style: lvMono(11,
                      color: LectureVaultColors.textMuted,
                      weight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                _buildTranscriptBox(),
              ]),
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

  Widget _buildTimelineBlock(List<_TimelineItem> items) {
    return Column(
      children: List.generate(items.length, (i) {
        final item = items[i];
        final isLast = i == items.length - 1;
        final dotColor = i.isEven
            ? LectureVaultColors.purpleBright
            : LectureVaultColors.blueElectric;
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
                      Text(
                        item.time,
                        style: lvMono(12,
                            color: dotColor, weight: FontWeight.w600),
                      ),
                      if (item.isEstimated) ...[
                        const SizedBox(height: 4),
                        Text(
                          '估算時間點',
                          style:
                              lvMono(10, color: LectureVaultColors.textMuted),
                        ),
                      ],
                      const SizedBox(height: 6),
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

class _TimelineItem {
  const _TimelineItem(this.time, this.text, {this.isEstimated = false});
  final String time;
  final String text;
  final bool isEstimated;
}
