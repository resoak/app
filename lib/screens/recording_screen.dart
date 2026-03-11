import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/stt_service.dart';
import '../services/recording_service.dart';
import '../services/db_service.dart';
import '../models/lecture.dart';
import '../utils/text_rank.dart';

class RecordingScreen extends StatefulWidget {
  final String lectureTitle;
  const RecordingScreen({super.key, required this.lectureTitle});

  @override
  State<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends State<RecordingScreen> {
  late final SttService _sttService;
  late final RecordingService _recordingService;

  final _transcriptController = ScrollController();
  StreamSubscription? _transcriptSub;
  StreamSubscription? _durationSub;

  final List<String> _sentences = [];
  String _interimText = '';
  List<String> _keyPoints = [];

  int _durationSeconds = 0;
  bool _isInitializing = true;
  bool _isSaving = false;
  int _lastUpdatedAt = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _sttService = SttService();
    _recordingService = RecordingService(sttService: _sttService);
    await _sttService.initialize();

    _transcriptSub = _sttService.transcriptStream.listen((text) {
      setState(() {
        if (_sentences.isNotEmpty && _sentences.last == _interimText) {
          _sentences.removeLast();
        }
        _interimText = text;
        _sentences.add(text);
      });

      final confirmed = _sentences.where((s) => s != _interimText).length;
      if (confirmed - _lastUpdatedAt >= 3) {
        _updateKeyPoints();
        _lastUpdatedAt = confirmed;
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_transcriptController.hasClients) {
          _transcriptController.animateTo(
            _transcriptController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    });

    _durationSub = _recordingService.durationStream.listen((s) {
      setState(() => _durationSeconds = s);
    });

    await _recordingService.start();
    setState(() => _isInitializing = false);
  }

  Future<void> _updateKeyPoints() async {
    final confirmed = _sentences.where((s) => s != _interimText).toList();
    if (confirmed.isEmpty) return;
    final points = await TextRank.extractKeyPoints(confirmed, topN: 6, windowSize: 20);
    if (mounted) setState(() => _keyPoints = points);
  }

  String _formatDuration(int s) {
    final m = s ~/ 60;
    final sec = s % 60;
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  Future<void> _stopAndSave() async {
    setState(() => _isSaving = true);
    await _recordingService.stop();
    await _updateKeyPoints();

    final transcript = _sentences.where((s) => s != _interimText).join('。\n');
    final summary = _keyPoints.map((p) => '• $p').join('\n');
    final now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

    final lecture = Lecture(
      title: widget.lectureTitle,
      date: now,
      audioPath: _recordingService.currentFilePath ?? '',
      transcript: transcript,
      summary: summary,
      durationSeconds: _durationSeconds,
    );

    final id = await DbService().insertLecture(lecture);
    if (mounted) {
      setState(() => _isSaving = false);
      Navigator.pop(context, id);
    }
  }

  @override
  void dispose() {
    _transcriptSub?.cancel();
    _durationSub?.cancel();
    _transcriptController.dispose();
    _recordingService.dispose();
    _sttService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('載入語音模型中...'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        foregroundColor: Colors.white,
        title: Text(widget.lectureTitle, style: const TextStyle(fontSize: 16)),
        actions: [
          if (!_isSaving)
            TextButton.icon(
              onPressed: _stopAndSave,
              icon: const Icon(Icons.stop_circle_outlined, color: Colors.redAccent),
              label: const Text('結束', style: TextStyle(color: Colors.redAccent)),
            ),
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
        ],
      ),
      body: Column(
        children: [
          _buildStatusBar(),
          Expanded(
            child: Row(
              children: [
                Expanded(flex: 5, child: _buildTranscriptPanel()),
                const VerticalDivider(width: 1, color: Color(0xFF334155)),
                Expanded(flex: 4, child: _buildKeyPointsPanel()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    return Container(
      color: const Color(0xFF1E293B),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const _PulsingDot(),
          const SizedBox(width: 8),
          const Text('錄音中', style: TextStyle(color: Color(0xB3FFFFFF), fontSize: 13)),
          const Spacer(),
          Text(
            _formatDuration(_durationSeconds),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTranscriptPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Text('逐字稿', style: TextStyle(color: Color(0x80FFFFFF), fontSize: 12)),
        ),
        Expanded(
          child: ListView.builder(
            controller: _transcriptController,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
            itemCount: _sentences.length,
            itemBuilder: (context, i) {
              final isInterim = _sentences[i] == _interimText;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  _sentences[i],
                  style: TextStyle(
                    color: isInterim ? const Color(0x60FFFFFF) : const Color(0xDEFFFFFF),
                    fontSize: 14,
                    height: 1.6,
                    fontStyle: isInterim ? FontStyle.italic : FontStyle.normal,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildKeyPointsPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Text('✨ 即時重點', style: TextStyle(color: Color(0x80FFFFFF), fontSize: 12)),
        ),
        Expanded(
          child: _keyPoints.isEmpty
              ? const Center(
                  child: Text(
                    '累積更多內容後\n自動顯示重點',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0x40FFFFFF), fontSize: 13),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                  itemCount: _keyPoints.length,
                  itemBuilder: (context, i) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('•  ', style: TextStyle(color: Color(0xFF60A5FA), fontSize: 14)),
                          Expanded(
                            child: Text(
                              _keyPoints[i],
                              style: const TextStyle(color: Color(0xDEFFFFFF), fontSize: 13, height: 1.5),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot();
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _ctrl,
      child: Container(
        width: 10, height: 10,
        decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
      ),
    );
  }
}