import 'package:flutter/material.dart';
import 'dashboard_screen.dart';
import 'voice_notes_screen.dart';
import 'pal_brain_screen.dart';
import 'ocr_scanner_screen.dart';
import 'tasks_screen.dart';
import 'quiz_screen.dart';
import 'study_vault_screen.dart';
import 'profile_screen.dart';
import 'timetable_screen.dart';
import '../theme/app_theme.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  final GlobalKey<PalBrainScreenState> _brainKey =
      GlobalKey<PalBrainScreenState>();

  void _switchTab(int index,
      {String? initialQuery, String? filterSubject, String? filterUnit}) {
    if (index == 96) {
      _openTasksScreen();
      return;
    }

    int target = index;
    if (index == 98) {
      target = 4; // Vault tab
    } else if (index > 4) {
      target = 2; // Ask AI fallback
    }

    setState(() {
      _currentIndex = target;
    });

    if (target == 2 && initialQuery != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _brainKey.currentState?.setQuery(
          initialQuery,
          ragScope: filterUnit ?? filterSubject,
        );
      });
    }
  }

  void _openQuizModal() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => QuizScreen(
          onOpenVaultCitations: () {
            _switchTab(2); // Ask AI
          },
        ),
      ),
    );
  }

  void _openTasksScreen() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TasksScreen(onNavigateToTab: _switchTab),
      ),
    );
  }

  void _openProfileModal() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProfileScreen(onNavigateTab: _switchTab),
      ),
    );
  }

  void _openTimetableScreen() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const TimetableScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = [
      DashboardScreen(onNavigateTab: (idx) {
        if (idx == 99) {
          _openQuizModal();
        } else if (idx == 98) {
          _switchTab(4); // Vault tab
        } else if (idx == 97) {
          _openProfileModal();
        } else if (idx == 96) {
          _openTasksScreen();
        } else if (idx == 95) {
          _openTimetableScreen();
        } else {
          _switchTab(idx);
        }
      }),
      VoiceNotesScreen(onNavigateToBrain: _switchTab),
      PalBrainScreen(key: _brainKey),
      OcrScannerScreen(onNavigateToBrain: _switchTab),
      StudyVaultScreen(onNavigateToBrain: _switchTab),
    ];

    return Scaffold(
      backgroundColor: AppTheme.canvasBg,
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppTheme.cardSurface,
          border: Border(
            top: BorderSide(color: AppTheme.cardBorder, width: 1),
          ),
          boxShadow: AppTheme.cardShadow,
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          type: BottomNavigationBarType.fixed,
          backgroundColor: AppTheme.cardSurface,
          selectedItemColor: AppTheme.primaryAccent,
          unselectedItemColor: AppTheme.textInactive,
          selectedFontSize: 11.5,
          showSelectedLabels: true,
          showUnselectedLabels: true,
          unselectedFontSize: 11,
          selectedLabelStyle:
              const TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.2),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.mic_none),
              activeIcon: Icon(Icons.mic),
              label: 'Capture',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.auto_awesome_outlined),
              activeIcon: Icon(Icons.auto_awesome),
              label: 'Ask',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.camera_alt_outlined),
              activeIcon: Icon(Icons.camera_alt),
              label: 'Camera',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.auto_stories_outlined),
              activeIcon: Icon(Icons.auto_stories),
              label: 'Vault',
            ),
          ],
        ),
      ),
    );
  }
}
