import 'package:flutter/material.dart';
import '../services/db_service.dart';
import '../models/lecture.dart';
import 'recording_screen.dart';
import 'lecture_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final DbService _dbService = DbService();
  List<Lecture> _lectures = [];

  @override
  void initState() {
    super.initState();
    _refreshData();
  }

  Future<void> _refreshData() async {
    final data = await _dbService.getAllLectures();
    setState(() => _lectures = data);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              const Text('LectureVault', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
              Text('• LOCAL_AI_READY', style: TextStyle(color: Colors.blueGrey[400], fontSize: 10, letterSpacing: 1)),
              const SizedBox(height: 30),
              Expanded(
                child: ListView.builder(
                  itemCount: _lectures.length,
                  itemBuilder: (context, index) => _buildLectureCard(_lectures[index]),
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: _buildFab(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }

  Widget _buildLectureCard(Lecture lecture) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LectureDetailScreen(lecture: lecture))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(24)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(lecture.date, style: const TextStyle(color: Colors.grey, fontSize: 10)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  // 修正：使用 withValues 替代 withOpacity
                  decoration: BoxDecoration(color: Colors.purpleAccent.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
                  child: Text(lecture.tag, style: const TextStyle(color: Colors.purpleAccent, fontSize: 10)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(lecture.title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text("${lecture.durationSeconds ~/ 60} min", style: const TextStyle(color: Colors.blueAccent, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildFab() {
    return Container(
      height: 64, width: 64,
      decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [Colors.blueAccent, Colors.purpleAccent])),
      child: FloatingActionButton(
        onPressed: () async {
          final res = await Navigator.push(context, MaterialPageRoute(builder: (_) => const RecordingScreen()));
          if (res == true) _refreshData();
        },
        backgroundColor: Colors.transparent, elevation: 0,
        child: const Icon(Icons.add, color: Colors.white, size: 32),
      ),
    );
  }
}