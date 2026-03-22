import 'dart:async';
import 'package:flutter/material.dart';
import '../services/stt_service.dart';
import '../services/recording_service.dart';
import '../services/db_service.dart';
import '../models/lecture.dart';

class RecordingScreen extends StatefulWidget {
  const RecordingScreen({super.key});
  @override
  State<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends State<RecordingScreen> {
  final SttService _sttService = SttService();
  late RecordingService _recordingService;
  final DbService _dbService = DbService();

  String _transcript = "";
  String _summary = "";
  int _seconds = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _recordingService = RecordingService(sttService: _sttService);
    _startEverything();
  }

  void _startEverything() async {
    await _sttService.initialize();
    _sttService.resetStream();

    _sttService.transcriptStream.listen((text) {
      if (mounted) setState(() => _transcript = text);
    });

    // 監聽即時重點
    _sttService.summaryStream.listen((summary) {
      if (mounted) setState(() => _summary = summary);
    });

    await _recordingService.start();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (mounted) setState(() => _seconds++);
    });
  }

  Future<void> _handleSave() async {
    final path = await _recordingService.stop();
    _timer?.cancel();

    final newLecture = Lecture(
      title: "課程錄音 ${DateTime.now().hour}:${DateTime.now().minute}",
      date: "${DateTime.now().year}.${DateTime.now().month}.${DateTime.now().day}",
      audioPath: path ?? '',
      transcript: _transcript,
      summary: _summary,      // 存入最終重點
      durationSeconds: _seconds,
      tag: '一般',
    );

    await _dbService.insertLecture(newLecture);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "正在錄音...",
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    _formatTime(_seconds),
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
            // 即時逐字稿
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: SingleChildScrollView(
                  reverse: true,
                  child: Text(
                    _transcript.isEmpty ? "等待語音輸入..." : _transcript,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                      height: 1.6,
                    ),
                  ),
                ),
              ),
            ),
            // 即時重點區塊
            if (_summary.isNotEmpty)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.purpleAccent.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.auto_awesome,
                            color: Colors.purpleAccent, size: 14),
                        SizedBox(width: 6),
                        Text(
                          "即時重點",
                          style: TextStyle(
                            color: Colors.purpleAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _summary,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        height: 1.6,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            // 停止按鈕
            Center(
              child: GestureDetector(
                onTap: _handleSave,
                child: Container(
                  height: 100,
                  width: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.red.withValues(alpha: 0.2),
                    border: Border.all(color: Colors.red, width: 4),
                  ),
                  child: const Icon(Icons.stop, color: Colors.red, size: 48),
                ),
              ),
            ),
            const SizedBox(height: 60),
          ],
        ),
      ),
    );
  }

  String _formatTime(int seconds) {
    final mins = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return "$mins:$secs";
  }
}