import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../models/lecture.dart';

class LectureDetailScreen extends StatefulWidget {
  final Lecture lecture;
  const LectureDetailScreen({super.key, required this.lecture});
  @override
  State<LectureDetailScreen> createState() => _LectureDetailScreenState();
}

class _LectureDetailScreenState extends State<LectureDetailScreen> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

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
    final content = '📚 ${widget.lecture.title}\n📅 ${widget.lecture.date}\n\n── 重點筆記 ──\n${widget.lecture.summary}\n\n── 完整逐字稿 ──\n${widget.lecture.transcript}';
    Share.share(content, subject: widget.lecture.title);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        foregroundColor: Colors.white,
        title: Text(widget.lecture.title, style: const TextStyle(fontSize: 16)),
        actions: [
          IconButton(icon: const Icon(Icons.ios_share_outlined), onPressed: _export),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: const Color(0xFF60A5FA),
          unselectedLabelColor: const Color(0x60FFFFFF),
          indicatorColor: const Color(0xFF60A5FA),
          tabs: const [Tab(text: '✨ 重點筆記'), Tab(text: '📄 完整逐字稿')],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [_buildSummaryTab(), _buildTranscriptTab()],
      ),
    );
  }

  Widget _buildSummaryTab() {
    final points = widget.lecture.summary.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (points.isEmpty) return const Center(child: Text('沒有重點筆記', style: TextStyle(color: Color(0x60FFFFFF))));
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: points.length,
      itemBuilder: (context, i) {
        final text = points[i].replaceFirst('• ', '').trim();
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(margin: const EdgeInsets.only(top: 5, right: 12), width: 8, height: 8,
                decoration: const BoxDecoration(color: Color(0xFF60A5FA), shape: BoxShape.circle)),
              Expanded(child: Text(text, style: const TextStyle(color: Color(0xDEFFFFFF), fontSize: 15, height: 1.6))),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTranscriptTab() {
    if (widget.lecture.transcript.isEmpty) return const Center(child: Text('沒有逐字稿', style: TextStyle(color: Color(0x60FFFFFF))));
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: SelectableText(widget.lecture.transcript, style: const TextStyle(color: Color(0xB3FFFFFF), fontSize: 14, height: 1.8)),
    );
  }
}