import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/app_settings.dart';
import 'providers/app_settings_provider.dart';
import 'screens/home_screen.dart';
import 'theme/lecture_vault_theme.dart';

void main() async {
  // 確保 Flutter 引擎初始化
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

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

    return MaterialApp(
      title: 'LectureVault',
      debugShowCheckedModeBanner: false,
      theme: buildLectureVaultTheme(backgroundStyle),
      home: const HomeScreen(),
    );
  }
}
