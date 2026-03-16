import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/embedding_service.dart';
import 'screens/home_screen.dart';

void main() async {
  // 確保 Flutter 引擎初始化
  WidgetsFlutterBinding.ensureInitialized();
  
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // 僅預載輕量服務
  try {
    await EmbeddingService().initialize();
  } catch (e) {
    debugPrint('Embedding init failed: $e');
  }

  runApp(const LectureVaultApp());
}

class LectureVaultApp extends StatelessWidget {
  const LectureVaultApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LectureVault',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF7C3AED),
          surface: Color(0xFF1E293B),
        ),
        scaffoldBackgroundColor: const Color(0xFF020617),
      ),
      home: const HomeScreen(),
    );
  }
}