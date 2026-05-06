import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../theme/lecture_vault_theme.dart';

class RecordingWaveform extends StatefulWidget {
  const RecordingWaveform({
    super.key,
    required this.level,
    required this.pcmData,
    this.barCount = 42,
    this.maxHeight = 120,
    required this.animation,
  });

  final double level;
  final ValueListenable<Int16List> pcmData; // 使用基類，解決類型錯誤
  final int barCount;
  final double maxHeight;
  final Animation<double> animation;

  @override
  State<RecordingWaveform> createState() => _RecordingWaveformState();
}

class _RecordingWaveformState extends State<RecordingWaveform> {
  late List<double> _amplitudes;
  double _rollingMax = 0.1;

  @override
  void initState() {
    super.initState();
    _amplitudes = List.filled(widget.barCount, 0.05);
  }

  void _updateAmplitudes(Int16List data) {
    if (data.isEmpty) {
      // 如果沒有數據，維持微弱的隨機背景律動，看起來更生動
      for (int i = 0; i < widget.barCount; i++) {
        _amplitudes[i] = _amplitudes[i] * 0.9 + (math.Random().nextDouble() * 0.02 + 0.01) * 0.1;
      }
      return;
    }
    
    final int samplesPerBar = (data.length / widget.barCount).floor();
    if (samplesPerBar <= 0) return;

    double currentFrameMax = 0.0;
    final List<double> frameAverages = List.filled(widget.barCount, 0.0);

    for (int i = 0; i < widget.barCount; i++) {
      int start = i * samplesPerBar;
      double sum = 0;
      int count = 0;
      for (int j = 0; j < samplesPerBar; j++) {
        if (start + j < data.length) {
          double sample = data[start + j] / 32768.0;
          sum += sample.abs();
          count++;
        }
      }
      
      double avg = count > 0 ? sum / count : 0;
      frameAverages[i] = avg;
      if (avg > currentFrameMax) currentFrameMax = avg;
    }

    // 動態增益補償：記錄滾動最大值，緩慢衰減
    if (currentFrameMax > _rollingMax) {
      _rollingMax = currentFrameMax;
    } else {
      _rollingMax = _rollingMax * 0.995 + currentFrameMax * 0.005;
    }
    // 確保 rollingMax 不會過小導致雜訊放大
    double effectiveMax = math.max(_rollingMax, 0.05);

    for (int i = 0; i < widget.barCount; i++) {
      // 增加中心頻段（通常是人聲所在）的權重
      double centerDist = (i - widget.barCount / 2).abs() / (widget.barCount / 2);
      double frequencyWeight = 1.0 + (1.0 - centerDist) * 0.3;
      
      // 使用動態增益：將平均值對比滾動最大值進行縮放
      double target = (frameAverages[i] / effectiveMax * frequencyWeight).clamp(0.01, 1.0);

      // 物理動力學優化：上升極快(0.9)，下降緩衝(0.15)
      if (target > _amplitudes[i]) {
        _amplitudes[i] = _amplitudes[i] * 0.1 + target * 0.9;
      } else {
        _amplitudes[i] = _amplitudes[i] * 0.85 + target * 0.15;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Int16List>(
      valueListenable: widget.pcmData,
      builder: (context, data, _) {
        _updateAmplitudes(data);
        return CustomPaint(
          size: Size(double.infinity, widget.maxHeight + 20),
          painter: _EqualizerPainter(
            amplitudes: List.from(_amplitudes),
            maxHeight: widget.maxHeight,
          ),
        );
      },
    );
  }
}

class _EqualizerPainter extends CustomPainter {
  _EqualizerPainter({required this.amplitudes, required this.maxHeight});
  final List<double> amplitudes;
  final double maxHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final double spacing = size.width / amplitudes.length;
    final double barWidth = spacing * 0.7;
    final double midY = size.height / 2;

    for (int i = 0; i < amplitudes.length; i++) {
      final double x = i * spacing + (spacing - barWidth) / 2;
      // 使用非線性曲線 (power 0.7) 讓低能量時的跳動更明顯
      final double magnitude = math.pow(amplitudes[i], 0.7).toDouble();
      final double h = (magnitude * maxHeight).clamp(8.0, maxHeight);
      final double top = midY - h / 2;

      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            LectureVaultColors.blueElectric,
            LectureVaultColors.purpleBright,
            if (magnitude > 0.8) Colors.white else LectureVaultColors.purpleBright,
          ],
        ).createShader(Rect.fromLTWH(x, top, barWidth, h))
        ..style = PaintingStyle.fill;

      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, top, barWidth, h), const Radius.circular(3)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _EqualizerPainter oldDelegate) => true;
}
