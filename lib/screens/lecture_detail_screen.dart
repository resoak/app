import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../models/lecture.dart';

class LectureDetailScreen extends StatefulWidget {
  final Lecture lecture;
  const LectureDetailScreen({super.key, required this.lecture});
  @override
  State<LectureDetailScreen> createState() => _LectureDetailScreenState();
}

class _LectureDetailScreenState extends State<LectureDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  static const _bg = Color(0xFF020617);
  static const _surface = Color(0xFF0F172A);
  static const _card = Color(0xFF1E293B);
  static const _purple = Color(0xFF7C3AED);
  static const _purpleLight = Color(0xFFA78BFA);

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  void _export() {
    final content =
        '📚 ${widget.lecture.title}\n📅 ${widget.lecture.date}\n\n── 重點筆記 ──\n${widget.lecture.summary}\n\n── 完整逐字稿 ──\n${widget.lecture.transcript}';
    Share.share(content, subject: widget.lecture.title);
  }

  String _formatDuration(int s) {
    final m = s ~/ 60;
    final sec = s % 60;
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildMeta(),
            _buildTabBar(),
            Expanded(
              child: TabBarView(
                controller: _tabCtrl,
                children: [_buildSummaryTab(), _buildTranscriptTab()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: _card.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 18),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              widget.lecture.title,
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _export,
            child: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: _card.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: const Icon(Icons.ios_share_outlined, color: Color(0x80FFFFFF), size: 18),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMeta() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _purple.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _purple.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome_rounded, color: _purpleLight, size: 16),
          const SizedBox(width: 8),
          const Text('Local Neural Engine', style: TextStyle(
            color: _purpleLight,
            fontSize: 10,
            fontFamily: 'monospace',
            letterSpacing: 1.5,
            fontWeight: FontWeight.bold,
          )),
          const Spacer(),
          const Icon(Icons.calendar_today_outlined, size: 12, color: Color(0x60FFFFFF)),
          const SizedBox(width: 6),
          Text(widget.lecture.date, style: const TextStyle(
            color: Color(0x80FFFFFF), fontSize: 11, fontFamily: 'monospace',
          )),
          const SizedBox(width: 12),
          const Icon(Icons.mic_rounded, size: 12, color: Color(0x60FFFFFF)),
          const SizedBox(width: 6),
          Text(_formatDuration(widget.lecture.durationSeconds), style: const TextStyle(
            color: Color(0x80FFFFFF), fontSize: 11, fontFamily: 'monospace',
          )),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: TabBar(
        controller: _tabCtrl,
        labelColor: Colors.white,
        unselectedLabelColor: const Color(0x60FFFFFF),
        labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal, fontSize: 13),
        indicator: BoxDecoration(
          color: _purple,
          borderRadius: BorderRadius.circular(12),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        padding: const EdgeInsets.all(4),
        tabs: const [
          Tab(text: '✨ AI 重點筆記'),
          Tab(text: '📄 完整逐字稿'),
        ],
      ),
    );
  }

  Widget _buildSummaryTab() {
    final points = widget.lecture.summary
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .toList();

    if (points.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              color: _purple.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.auto_awesome_outlined, color: _purpleLight, size: 28),
          ),
          const SizedBox(height: 16),
          const Text('沒有重點筆記', style: TextStyle(color: Color(0x60FFFFFF), fontSize: 14)),
        ]),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      itemCount: points.length + 1,
      itemBuilder: (context, i) {
        // Header card
        if (i == 0) {
          return Container(
            margin: const EdgeInsets.only(bottom: 20),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF312E81).withValues(alpha: 0.8),
                  const Color(0xFF4C1D95).withValues(alpha: 0.8),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _purpleLight.withValues(alpha: 0.2)),
            ),
            child: Row(children: [
              const Icon(Icons.auto_awesome_rounded, color: _purpleLight, size: 16),
              const SizedBox(width: 8),
              const Text('AI 核心摘要', style: TextStyle(
                color: _purpleLight,
                fontSize: 11,
                fontFamily: 'monospace',
                letterSpacing: 2,
                fontWeight: FontWeight.bold,
              )),
              const Spacer(),
              Text('${points.length} 個重點', style: const TextStyle(
                color: Color(0x80FFFFFF), fontSize: 11,
              )),
            ]),
          );
        }

        final text = points[i - 1].replaceFirst('• ', '').trim();
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _card.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(16),
            border: Border(
              left: const BorderSide(color: _purpleLight, width: 2),
              top: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
              right: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
              bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 2, right: 12),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _purple.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  i.toString().padLeft(2, '0'),
                  style: const TextStyle(
                    color: _purpleLight,
                    fontSize: 10,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Expanded(
                child: Text(text, style: const TextStyle(
                  color: Color(0xE6FFFFFF),
                  fontSize: 14,
                  height: 1.65,
                )),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTranscriptTab() {
    if (widget.lecture.transcript.isEmpty) {
      return const Center(
        child: Text('沒有逐字稿', style: TextStyle(color: Color(0x60FFFFFF), fontSize: 14)),
      );
    }

    final sentences = widget.lecture.transcript
        .split('\n')
        .where((s) => s.trim().isNotEmpty)
        .toList();

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      itemCount: sentences.length,
      itemBuilder: (context, i) {
        return Container(
          margin: const EdgeInsets.only(bottom: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 時間軸線
              Column(children: [
                Container(
                  width: 2, height: 8,
                  color: i == 0 ? _purple : Colors.transparent,
                ),
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i % 5 == 0 ? _purple : const Color(0xFF1E293B),
                    border: Border.all(
                      color: i % 5 == 0 ? _purple : const Color(0xFF334155),
                      width: 1.5,
                    ),
                  ),
                ),
                Container(
                  width: 2,
                  height: 32,
                  color: const Color(0xFF1E293B),
                ),
              ]),
              const SizedBox(width: 14),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 12),
                  child: SelectableText(
                    sentences[i],
                    style: const TextStyle(
                      color: Color(0xB3FFFFFF),
                      fontSize: 14,
                      height: 1.7,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}