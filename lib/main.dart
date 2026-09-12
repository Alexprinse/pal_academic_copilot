import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/main_navigation_screen.dart';
import 'services/deadline_service.dart';
import 'services/llm_service.dart';
import 'services/ocr_service.dart';
import 'services/profile_service.dart';
import 'services/rag_service.dart';
import 'services/stt_service.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set system UI overlay style for dark high-tech status bar
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppTheme.surfaceDark,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // Initialize core on-device engines in parallel
  await Future.wait([
    DeadlineService.instance.init(),
    ProfileService.instance.init(),
    RagService.instance.init(),
    Future.microtask(() => OcrService.instance.init()),
  ]);

  // Non-blocking initialization of heavy native AI services
  SttService.instance.init();
  LlmService.instance.init();

  runApp(const PalApp());
}

class PalApp extends StatelessWidget {
  const PalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pal Academic Copilot',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const MainNavigationScreen(),
    );
  }
}
