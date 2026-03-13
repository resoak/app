import 'package:flutter/material.dart';
import '../models/lecture.dart';
import '../services/db_service.dart';
import 'recording_screen.dart';
import 'lecture_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Lecture> _lectures = [];
  bool _loading = true;

  static const Color _bg       = Color(0xFF020617);
  static const Color _card     = Color(0xFF1E293B);
  static const Color _purple   = Color(0xFF7C3AED);
  static const Color _purpleD  = Color(0xFF4C1D95);
  static const Color _purpleL  = Color(0xFFC4B5FD);
  static const Color _green    = Color(0xFF4ADE80);
  static const Color _slate400 = Color(0xFF94A3B8);
  static const Color _slate500 = Color(0xFF64748B);
  static const Color _slate700 = Color(0xFF334155);
  static const Color _white    = Color(0xFFF1F5F9);

  @override
  void initState() {
    super.initState();
    _loadLectures();
  }

  Future<void> _loadLectures() async {
    final lectures = await DbService().getAllLectures();
    setState(() { _lectures = lectures; _loading = false; });
  }

  Future<void> _startNewLecture() async {
    final ctrl = TextEditingController(
      text: '課程 ${DateTime.now().month}/${DateTime.now().day}',
    );
    final title = await showDialog<String>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: _card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('NEW SESSION', style: TextStyle(color: _purpleL, fontSize: 11, letterSpacing: 3, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              const Text('課程名稱', style: TextStyle(color: _white, fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 20),
              TextField(
                controller: ctrl,
                autofocus: true,
                style: const TextStyle(color: _white, fontSize: 15),
                decoration: InputDecoration(
                  hintText: '輸入課程名稱',
                  hintStyle: const TextStyle(color: _slate500),
                  filled: true,
                  fillColor: _bg,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _purple, width: 1.5)),
                ),
              ),
              const SizedBox(height: 24),
              Row(children: [
                Expanded(child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消', style: TextStyle(color: _slate400)))),
                const SizedBox(width: 12),
                Expanded(child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, ctrl.text.trim()),
                  style: ElevatedButton.styleFrom(backgroundColor: _purple, foregroundColor: _white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: const Text('開始錄音', style: TextStyle(fontWeight: FontWeight.bold)),
                )),
              ]),
            ],
          ),
        ),
      ),
    );
    if (title == null || title.isEmpty || !mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => RecordingScreen(lectureTitle: title)));
    await _loadLectures();
  }

  Future<void> _deleteLecture(Lecture lecture) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: _card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('刪除課程', style: TextStyle(color: _white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text('確定刪除「${lecture.title}」？', style: const TextStyle(color: _slate400), textAlign: TextAlign.center),
            const SizedBox(height: 24),
            Row(children: [
              Expanded(child: TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消', style: TextStyle(color: _slate400)))),
              Expanded(child: ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: _white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: const Text('刪除'),
              )),
            ]),
          ]),
        ),
      ),
    );
    if (confirm == true && lecture.id != null) {
      await DbService().deleteLecture(lecture.id!);
      await _loadLectures();
    }
  }

  String _formatDuration(int s) {
    final m = s ~/ 60;
    final sec = s % 60;
    if (m == 0) return '${sec}s';
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('LectureVault', style: TextStyle(color: _white, fontSize: 28, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 4),
                        Row(children: [
                          Container(width: 7, height: 7, decoration: const BoxDecoration(color: _green, shape: BoxShape.circle)),
                          const SizedBox(width: 6),
                          const Text('OFFLINE_AI_READY', style: TextStyle(color: _purpleL, fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.bold)),
                        ]),
                      ],
                    ),
                  ),
                  Container(
                    width: 42, height: 42,
                    decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(12), border: Border.all(color: _slate700)),
                    child: const Icon(Icons.tune_rounded, color: _slate400, size: 20),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _startNewLecture,
        backgroundColor: _purple,
        foregroundColor: _white,
        child: const Icon(Icons.add_rounded, size: 30),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _purple));
    }
    if (_lectures.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(color: _purpleD, borderRadius: BorderRadius.circular(24)),
            child: const Icon(Icons.mic_none_rounded, size: 40, color: _purpleL),
          ),
          const SizedBox(height: 20),
          const Text('還沒有課程筆記', style: TextStyle(color: _white, fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text('點下方按鈕開始錄音', style: TextStyle(color: _slate400, fontSize: 13)),
        ]),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 100),
      itemCount: _lectures.length,
      itemBuilder: (context, i) => _buildCard(_lectures[i]),
    );
  }

  Widget _buildCard(Lecture lecture) {
    final hasSummary = lecture.summary.isNotEmpty;
    return GestureDetector(
      onTap: () async {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => LectureDetailScreen(lecture: lecture)));
        await _loadLectures();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _slate700),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 4,
                decoration: const BoxDecoration(
                  color: _purple,
                  borderRadius: BorderRadius.only(topLeft: Radius.circular(16), bottomLeft: Radius.circular(16)),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(lecture.date, style: const TextStyle(color: _slate500, fontSize: 11)),
                      const SizedBox(height: 6),
                      Row(children: [
                        Expanded(
                          child: Text(lecture.title, style: const TextStyle(color: _white, fontSize: 16, fontWeight: FontWeight.w700)),
                        ),
                        GestureDetector(
                          onTap: () => _deleteLecture(lecture),
                          child: const Icon(Icons.more_horiz, color: _slate500, size: 20),
                        ),
                      ]),
                      const SizedBox(height: 10),
                      Row(children: [
                        const Icon(Icons.mic_rounded, size: 13, color: _slate500),
                        const SizedBox(width: 4),
                        Text(_formatDuration(lecture.durationSeconds), style: const TextStyle(color: _slate400, fontSize: 12)),
                        const SizedBox(width: 10),
                        if (hasSummary)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(color: _purpleD, borderRadius: BorderRadius.circular(6)),
                            child: const Text('已總結', style: TextStyle(color: _purpleL, fontSize: 10, fontWeight: FontWeight.bold)),
                          ),
                      ]),
                      if (hasSummary) ...[
                        const SizedBox(height: 10),
                        Text(
                          lecture.summary.split('\n').where((l) => l.trim().isNotEmpty).first.replaceFirst('• ', ''),
                          style: const TextStyle(color: _slate400, fontSize: 12, height: 1.5),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}