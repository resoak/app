import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/lecture_vault_theme.dart';

/// Vertical bar waveform driven by an [AnimationController] (repeat).
class RecordingWaveform extends StatelessWidget {
  const RecordingWaveform({
    super.key,
    required this.animation,
    this.barCount = 48,
    this.maxHeight = 120,
  });

  final Animation<double> animation;
  final int barCount;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite ? constraints.maxWidth : 320.0;
        return SizedBox(
          height: maxHeight + 24,
          width: width,
          child: AnimatedBuilder(
            animation: animation,
            builder: (context, child) {
              return CustomPaint(
                painter: _WavePainter(
                  t: animation.value,
                  barCount: barCount,
                  maxHeight: maxHeight,
                ),
                size: Size(width, maxHeight + 24),
              );
            },
          ),
        );
      },
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({
    required this.t,
    required this.barCount,
    required this.maxHeight,
  });

  final double t;
  final int barCount;
  final double maxHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final gap = w / barCount;
    final barW = math.max(2.0, gap * 0.45);

    for (var i = 0; i < barCount; i++) {
      final x = i * gap + (gap - barW) / 2;
      final phase = (i / barCount) * math.pi * 2 + t * math.pi * 2;
      final norm = (math.sin(phase) * 0.5 + 0.5);
      final h2 = 12 + norm * (maxHeight - 12);
      final top = (h - h2) / 2;

      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            LectureVaultColors.blueElectric.withValues(alpha: 0.85),
            LectureVaultColors.purpleBright.withValues(alpha: 0.95),
          ],
        ).createShader(Rect.fromLTWH(x, top, barW, h2))
        ..style = PaintingStyle.fill;

      final r = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, top, barW, h2),
        const Radius.circular(6),
      );
      canvas.drawRRect(r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter oldDelegate) {
    return oldDelegate.t != t ||
        oldDelegate.barCount != barCount ||
        oldDelegate.maxHeight != maxHeight;
  }
}
