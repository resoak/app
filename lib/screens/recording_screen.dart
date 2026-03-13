import 'dart:async';
import 'package:flutter/material.dart';
// 移除未使用的 intl 匯入，改用自定義格式化
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
  StreamSubscription? _progressSub;

  final List<String> _sentences = [];
  String _interimText = '';
  List<String> _keyPoints = [];

  int _durationSeconds = 0;
  bool _isInitializing = true;
  bool _isSaving = false;
  int _lastUpdatedAt = 0;

  double _loadingProgress = 0.0;
  String _loadingMessage = '系統啟動中...';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _sttService = SttService();
    _recordingService = RecordingService(sttService: _sttService);

    _progressSub = _sttService.initProgressStream.listen((progress) {
      if (mounted) {
        setState(() {
          _loadingProgress = 0.1 + (progress * 0.8);
          _loadingMessage = progress < 1.0 
              ? '正在準備語音模型... ${(progress * 100).toInt()}%' 
              : '模型載入完成...';
        });
      }
    });

    try {
      await _sttService.initialize();
      
      _transcriptSub = _sttService.transcriptStream.listen((text) {
        if (!mounted) return;
        setState(() {
          if (_sentences.isNotEmpty && _sentences.last == _interimText) {
            _sentences.removeLast();
          }
          _interimText = text;
          _sentences.add(text);
        });

        // 每增加 3 句新話就更新一次關鍵點
        final confirmedCount = _sentences.length;
        if (confirmedCount - _lastUpdatedAt >= 3) {
          _updateKeyPoints();
          _lastUpdatedAt = confirmedCount;
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
        if (mounted) setState(() => _durationSeconds = s);
      });

      await _recordingService.start();
      if (mounted) setState(() => _isInitializing = false);
    } catch (e) {
      if (mounted) {
        setState(() => _loadingMessage = '初始化失敗: $e');
      }
    }
  }

  // 修正點：呼叫正確的 TextRank 方法名稱
  Future<void> _updateKeyPoints() async {
    if (_sentences.isEmpty) return;
    try {
      final points = await TextRank.extractKeyPoints(
        _sentences,
        topN: 5,
        windowSize: 50, // 只取最近 50 句分析，效能較好
      );
      if (mounted) {
        setState(() => _keyPoints = points);
      }
    } catch (e) {
      debugPrint('KeyPoints Error: $e');
    }
  }

  // 修正點：補上時間格式化
  String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  // 修正點：補上停止與存檔邏輯
  Future<void> _stopAndSave() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      await _recordingService.stop();
      
      final lecture = Lecture(
        title: widget.lectureTitle,
        date: DateTime.now().toString().split(' ')[0],
        durationSeconds: _durationSeconds,
        transcript: _sentences.join('\n'),
        summary: _keyPoints.map((p) => '• $p').join('\n'),
        audioPath: _recordingService.currentFilePath ?? '',
      );

      await DbService().insertLecture(lecture);
      
      if (mounted) {
        Navigator.pop(context, true); // 回到首頁並通知重新讀取
      }
    } catch (e) {
      debugPrint('Save Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('儲存失敗: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    _transcriptSub?.cancel();
    _durationSub?.cancel();
    _transcriptController.dispose();
    // 這裡不 dispose 服務，因為它們在 RecordingScreen 裡是 late final
    // 但如果有需要可以在這裡處理
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) return _buildLoadingView();
    return _buildRecordingView();
  }

  Widget _buildLoadingView() {
    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Color(0xFF7C3AED)),
            const SizedBox(height: 20),
            Text(_loadingMessage, style: const TextStyle(color: Colors.white)),
            Text('${(_loadingProgress * 100).toInt()}%', style: const TextStyle(color: Color(0xFF94A3B8))),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordingView() {
    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(widget.lectureTitle, style: const TextStyle(color: Colors.white)),
        actions: [
          IconButton(
            icon: _isSaving ? const CircularProgressIndicator() : const Icon(Icons.check, color: Colors.green),
            onPressed: _stopAndSave,
          )
        ],
      ),
      body: Column(
        children: [
          // 顯示時間
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              _formatDuration(_durationSeconds),
              style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
            ),
          ),
          // 逐字稿顯示區域
          Expanded(
            child: ListView.builder(
              controller: _transcriptController,
              padding: const EdgeInsets.all(16),
              itemCount: _sentences.length,
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_sentences[i], style: const TextStyle(color: Colors.white70, fontSize: 16)),
              ),
            ),
          ),
          // 關鍵點顯示區
          if (_keyPoints.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              color: const Color(0xFF1E293B),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('即時重點', style: TextStyle(color: Color(0xFF60A5FA), fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ..._keyPoints.take(3).map((p) => Text('• $p', style: const TextStyle(color: Colors.white, fontSize: 13))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}