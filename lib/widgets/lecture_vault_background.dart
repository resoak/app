import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/lecture_vault_theme.dart';

class LectureVaultBackground extends ConsumerWidget {
  const LectureVaultBackground({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final palette = theme.lectureVaultPalette;
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      // 直接使用主題底色，確保切換時百分之百同步，消除閃爍
      color: palette.backgroundBase,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (isDark)
            _BackgroundGradient(palette: palette),
          child,
        ],
      ),
    );
  }
}

class _BackgroundGradient extends StatelessWidget {
  const _BackgroundGradient({required this.palette});
  final LectureVaultPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 1.4,
          colors: [
            palette.surface,        // 中心：較淡的深藍色 (Slate 900)
            palette.backgroundBase, // 邊緣：極深色 (Slate 950)
          ],
          stops: const [0.0, 0.9],
        ),
      ),
    );
  }
}
