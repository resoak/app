import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/app_settings.dart';
import 'providers/app_settings_provider.dart';
import 'screens/home_screen.dart';
import 'theme/lecture_vault_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 效能優化：鎖定方向並停用不需要的系統動畫
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // 停用系統 UI 以提升效能
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  runApp(
    const ProviderScope(
      child: LectureVaultApp(),
    ),
  );
}

class LectureVaultApp extends ConsumerWidget {
  const LectureVaultApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backgroundStyle = ref.watch(
      appSettingsProvider.select(
        (state) =>
            state.asData?.value.backgroundStyle ??
            AppSettings.defaults().backgroundStyle,
      ),
    );

    return AnimatedTheme(
      data: buildLectureVaultTheme(backgroundStyle),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      child: MaterialApp(
        title: 'LectureVault',
        debugShowCheckedModeBanner: false,
        // 效能優化：停用 accessibility tree
        builder: (context, child) {
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: false,
            ),
            child: child!,
          );
        },
        theme: buildLectureVaultTheme(backgroundStyle),
        home: const HomeScreen(),
      ),
    );
  }
}
