import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_settings.dart';
import '../providers/app_settings_provider.dart';
import '../theme/lecture_vault_theme.dart';

class LectureVaultBackground extends ConsumerWidget {
  const LectureVaultBackground({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backgroundStyle = ref.watch(
      appSettingsProvider.select(
        (state) =>
            state.asData?.value.backgroundStyle ??
            AppSettings.defaults().backgroundStyle,
      ),
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(color: LectureVaultColors.bgDeep),
        ),
        IgnorePointer(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            child: _BackgroundLayers(
              key: ValueKey(backgroundStyle),
              style: backgroundStyle,
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _BackgroundLayers extends StatelessWidget {
  const _BackgroundLayers({
    super.key,
    required this.style,
  });

  final AppBackgroundStyle style;

  @override
  Widget build(BuildContext context) {
    switch (style) {
      case AppBackgroundStyle.darkDefault:
        return const SizedBox.expand();
      case AppBackgroundStyle.aurora:
        return const Stack(
          fit: StackFit.expand,
          children: [
            _GradientWash(),
            _GlowOrb(
              alignment: Alignment(-1.1, -0.92),
              color: LectureVaultColors.purple,
              size: 300,
            ),
            _GlowOrb(
              alignment: Alignment(1.08, -0.24),
              color: LectureVaultColors.blueElectric,
              size: 280,
            ),
            _GlowOrb(
              alignment: Alignment(0.36, 1.08),
              color: LectureVaultColors.purpleBright,
              size: 240,
            ),
          ],
        );
      case AppBackgroundStyle.blueprint:
        return const Stack(
          fit: StackFit.expand,
          children: [
            _GradientWash(
              topColor: Color(0x1400E5FF),
              bottomColor: Color(0x120A1022),
            ),
            CustomPaint(painter: _BlueprintGridPainter()),
            _GlowOrb(
              alignment: Alignment(0.88, -0.92),
              color: LectureVaultColors.blueElectric,
              size: 260,
            ),
            _GlowOrb(
              alignment: Alignment(-1.0, 0.92),
              color: LectureVaultColors.purple,
              size: 220,
            ),
          ],
        );
    }
  }
}

class _GradientWash extends StatelessWidget {
  const _GradientWash({
    this.topColor = const Color(0x120F172A),
    this.bottomColor = const Color(0x44020617),
  });

  final Color topColor;
  final Color bottomColor;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [topColor, bottomColor],
        ),
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({
    required this.alignment,
    required this.color,
    required this.size,
  });

  final Alignment alignment;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: 0.2),
              color.withValues(alpha: 0.06),
              Colors.transparent,
            ],
          ),
        ),
      ),
    );
  }
}

class _BlueprintGridPainter extends CustomPainter {
  const _BlueprintGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const spacing = 36.0;
    final minorPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.035)
      ..strokeWidth = 1;
    final majorPaint = Paint()
      ..color = LectureVaultColors.blueElectric.withValues(alpha: 0.08)
      ..strokeWidth = 1.2;

    for (double dx = 0; dx <= size.width; dx += spacing) {
      final paint = ((dx / spacing).round() % 4 == 0) ? majorPaint : minorPaint;
      canvas.drawLine(Offset(dx, 0), Offset(dx, size.height), paint);
    }

    for (double dy = 0; dy <= size.height; dy += spacing) {
      final paint = ((dy / spacing).round() % 4 == 0) ? majorPaint : minorPaint;
      canvas.drawLine(Offset(0, dy), Offset(size.width, dy), paint);
    }

    final scanlinePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          LectureVaultColors.blueElectric.withValues(alpha: 0.1),
          Colors.transparent,
        ],
        stops: const [0, 0.5, 1],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height), scanlinePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
