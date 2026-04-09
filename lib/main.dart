import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/home_screen.dart';
import 'theme/lecture_vault_theme.dart';

void main() async {
  // 確保 Flutter 引擎初始化
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  runApp(const LectureVaultApp());
}

class LectureVaultApp extends StatelessWidget {
  const LectureVaultApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LectureVault',
      debugShowCheckedModeBanner: false,
      theme: buildLectureVaultTheme(),
      home: const HomeScreen(),
    );
  }
}
