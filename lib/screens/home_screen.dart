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
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('新課程', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: '輸入課程名稱',
            hintStyle: TextStyle(color: Color(0x60FFFFFF)),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0x40FFFFFF))),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF60A5FA))),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消', style: TextStyle(color: Color(0x80FFFFFF)))),
          TextButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('開始錄音', style: TextStyle(color: Color(0xFF60A5FA)))),
        ],
      ),
    );

    if (title == null || title.isEmpty || !mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => RecordingScreen(lectureTitle: title)));
    await _loadLectures();
  }

  Future<void> _deleteLecture(Lecture lecture) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('刪除課程', style: TextStyle(color: Colors.white)),
        content: Text('確定刪除「${lecture.title}」？', style: const TextStyle(color: Color(0xB3FFFFFF))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消', style: TextStyle(color: Color(0x80FFFFFF)))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('刪除', style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (confirm == true && lecture.id != null) {
      await DbService().deleteLecture(lecture.id!);
      await _loadLectures();
    }
  }

  String _formatDuration(int s) {
    final m = s ~/ 60;
    return m < 60 ? '$m 分 ${s % 60} 秒' : '${m ~/ 60} 時 ${m % 60} 分';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        title: const Row(children: [
          Icon(Icons.school_rounded, color: Color(0xFF60A5FA), size: 22),
          SizedBox(width: 10),
          Text('LectureVault', style: TextStyle(color: Colors.white, fontSize: 18)),
        ]),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _lectures.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.mic_none_rounded, size: 72, color: Colors.white.withValues(alpha: 0.15)),
                    const SizedBox(height: 16),
                    const Text('還沒有課程筆記', style: TextStyle(color: Color(0x60FFFFFF), fontSize: 16)),
                    const SizedBox(height: 8),
                    const Text('點下方按鈕開始錄音', style: TextStyle(color: Color(0x40FFFFFF), fontSize: 13)),
                  ]),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _lectures.length,
                  itemBuilder: (context, i) {
                    final lecture = _lectures[i];
                    return Card(
                      color: const Color(0xFF1E293B),
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () async {
                          await Navigator.push(context, MaterialPageRoute(builder: (_) => LectureDetailScreen(lecture: lecture)));
                          await _loadLectures();
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Expanded(child: Text(lecture.title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600))),
                              IconButton(icon: const Icon(Icons.delete_outline, color: Color(0x40FFFFFF), size: 20), onPressed: () => _deleteLecture(lecture), padding: EdgeInsets.zero, constraints: const BoxConstraints()),
                            ]),
                            const SizedBox(height: 6),
                            Row(children: [
                              const Icon(Icons.calendar_today_outlined, size: 12, color: Color(0x60FFFFFF)),
                              const SizedBox(width: 4),
                              Text(lecture.date, style: const TextStyle(color: Color(0x60FFFFFF), fontSize: 12)),
                              const SizedBox(width: 16),
                              const Icon(Icons.timer_outlined, size: 12, color: Color(0x60FFFFFF)),
                              const SizedBox(width: 4),
                              Text(_formatDuration(lecture.durationSeconds), style: const TextStyle(color: Color(0x60FFFFFF), fontSize: 12)),
                            ]),
                            if (lecture.summary.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Text(lecture.summary.split('\n').first, style: const TextStyle(color: Color(0x80FFFFFF), fontSize: 13, height: 1.4), maxLines: 2, overflow: TextOverflow.ellipsis),
                            ],
                          ]),
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _startNewLecture,
        backgroundColor: const Color(0xFF60A5FA),
        foregroundColor: Colors.black,
        icon: const Icon(Icons.mic_rounded),
        label: const Text('開始錄音', style: TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }
}