import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';

import '../models/lecture.dart';
import '../providers/transcription_provider.dart';
import '../services/db_service.dart';
import '../services/recording_service.dart';

import '../theme/lecture_vault_theme.dart';
import '../widgets/recording_waveform.dart';

class RecordingScreen extends ConsumerStatefulWidget {
  const RecordingScreen({
    super.key,
    this.whisperModel = WhisperModel.base,
  });

  final WhisperModel whisperModel;

  @override
  ConsumerState<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends ConsumerState<RecordingScreen>
    with SingleTickerProviderStateMixin {
  late RecordingService _recordingService;
  final DbService _dbService = DbService();

  String _transcript = '';
  String? _startupError;
  int _seconds = 0;
  Timer? _timer;
  late AnimationController _waveCtrl;
  bool _isRecordingActive = false;
  bool _isStopping = false;

  @override
  void initState() {
    super.initState();
    _recordingService = RecordingService();
    _waveCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _startEverything();
  }

  void _startEverything() async {
    try {
      if (mounted) {
        setState(() => _transcript = '錄音完成後將在背景轉錄…');
      }

      final started = await _recordingService.start();
      if (!started) {
        const message = '無法開始錄音，請確認已允許麥克風權限。';
        if (!mounted) return;
        setState(() {
          _startupError = message;
          _transcript = message;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(message)),
        );
        return;
      }

      _isRecordingActive = true;
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (mounted) setState(() => _seconds++);
      });
    } catch (e) {
      const message = '錄音初始化失敗，請稍後再試。';
      if (!mounted) return;
      setState(() {
        _startupError = message;
        _transcript = message;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$message\n$e')),
      );
    }
  }

  Future<void> _handleSave() async {
    if (_startupError != null) {
      if (mounted) Navigator.pop(context);
      return;
    }
    if (!_isRecordingActive || _isStopping) return;

    _isStopping = true;
    final path = await _recordingService.stop();
    _isRecordingActive = false;
    _timer?.cancel();

    if (path == null || path.isEmpty) {
      _isStopping = false;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('錄音未成功儲存，請再試一次。')),
      );
      Navigator.pop(context);
      return;
    }

    final now = DateTime.now();
    final dateLabel =
        '${now.year}.${now.month.toString().padLeft(2, '0')}.${now.day.toString().padLeft(2, '0')}';
    final timeLabel =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    final newLecture = Lecture(
      title: '課程錄音 $dateLabel $timeLabel',
      date: dateLabel,
      audioPath: path,
      transcript: '',
      summary: '背景轉錄中…',
      durationSeconds: _seconds,
      tag: '一般',
      timeline: const [],
    );

    final id = await _dbService.insertLecture(newLecture);
    final savedLecture = newLecture.copyWith(
      id: id,
      durationSeconds: _seconds,
    );

    unawaited(
      ref.read(transcriptionProvider.notifier).transcribeLecture(
            savedLecture,
            whisperModel: widget.whisperModel,
          ),
    );

    _isStopping = false;

    if (mounted) Navigator.pop(context, true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _waveCtrl.dispose();
    if (_isRecordingActive && !_isStopping) {
      _isStopping = true;
      unawaited(_recordingService.stop());
    }
    super.dispose();
  }

  String _formatHms(int seconds) {
    final h = (seconds ~/ 3600).toString().padLeft(2, '0');
    final m = ((seconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LectureVaultColors.bgDeep,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color:
                        LectureVaultColors.statusGreen.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: LectureVaultColors.statusGreen
                          .withValues(alpha: 0.35),
                    ),
                  ),
                  child: Text(
                    'SECURE_OFFLINE_RECORDING',
                    style: lvMono(10, color: LectureVaultColors.statusGreen),
                  ),
                ),
              ),
              const SizedBox(height: 36),
              Text(
                _formatHms(_seconds),
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 44,
                  fontWeight: FontWeight.w300,
                  color: Colors.white,
                  letterSpacing: 2,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'RECORDING AUDIO...',
                style: lvMono(11, color: LectureVaultColors.textMuted),
              ),
              const SizedBox(height: 28),
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      child: Center(
                        child: RecordingWaveform(
                          animation: CurvedAnimation(
                            parent: _waveCtrl,
                            curve: Curves.linear,
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        _transcript.isEmpty ? '等待語音輸入…' : _transcript,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontSize: 13,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Column(
                children: [
                  GestureDetector(
                    onTap: _handleSave,
                    child: Container(
                      height: 96,
                      width: 96,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color:
                            LectureVaultColors.stopRed.withValues(alpha: 0.15),
                        border: Border.all(
                          color: LectureVaultColors.stopRed,
                          width: 3,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: LectureVaultColors.stopRed
                                .withValues(alpha: 0.45),
                            blurRadius: 28,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(Icons.stop_rounded,
                            color: Colors.white, size: 44),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _startupError == null ? 'STOP & GENERATE NOTE' : 'CLOSE',
                    style: lvMono(10, color: LectureVaultColors.textMuted),
                  ),
                ],
              ),
              const SizedBox(height: 36),
            ],
          ),
        ),
      ),
    );
  }
}
