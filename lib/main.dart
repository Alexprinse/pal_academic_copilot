import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/main_navigation_screen.dart';
import 'services/conversation_service.dart';
import 'services/deadline_service.dart';
import 'services/lecture_recording_service.dart';
import 'services/llm_service.dart';
import 'services/ocr_service.dart';
import 'services/pal_notification_service.dart';
import 'services/profile_service.dart';
import 'services/rag_service.dart';
import 'services/recording_scheduler.dart';
import 'services/stt_service.dart';
import 'services/timetable_service.dart';
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

  // Initialize notifications & recording scheduler
  PalNotificationService.instance.init();

  // Initialize core on-device engines in parallel
  await Future.wait([
    DeadlineService.instance.init(),
    ProfileService.instance.init(),
    TimetableService.instance.init(),
    LectureRecordingService.instance.init(),
    RagService.instance.init(),
    ConversationService.instance.init(),
    Future.microtask(() => OcrService.instance.init()),
  ]);

  // Start background timetable recording scheduler
  RecordingScheduler.instance.start();

  // Reconcile scheduled notification reminders with loaded classes & deadlines
  PalNotificationService.instance.setNavigatorKey(PalApp.navigatorKey);
  PalNotificationService.instance.reconcileSchedules(
    classes: TimetableService.instance.entries,
    deadlines: DeadlineService.instance.deadlines,
  );

  // Non-blocking initialization of heavy native AI services
  SttService.instance.init();
  LlmService.instance.init();

  runApp(const PalApp());
}

class PalApp extends StatelessWidget {
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  const PalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Pal Academic Copilot',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const MainNavigationScreen(),
    );
  }
}
