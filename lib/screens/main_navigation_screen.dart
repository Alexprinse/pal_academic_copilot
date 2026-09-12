import 'package:flutter/material.dart';
import 'dashboard_screen.dart';
import 'voice_notes_screen.dart';
import 'pal_brain_screen.dart';
import 'tasks_screen.dart';
import 'quiz_screen.dart';
import 'study_vault_screen.dart';
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
    // If index 4 requested (old vault / brain index), map appropriately
    int target = index;
    if (index >= 4) {
      target = 2; // Ask AI
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

  void _openVaultModal() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StudyVaultScreen(onNavigateToBrain: _switchTab),
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
          _openVaultModal();
        } else {
          _switchTab(idx);
        }
      }),
      VoiceNotesScreen(onNavigateToBrain: _switchTab),
      PalBrainScreen(key: _brainKey),
      TasksScreen(onNavigateToTab: _switchTab),
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
          selectedItemColor: AppTheme.textPrimary,
          unselectedItemColor: AppTheme.textInactive,
          selectedFontSize: 12,
          unselectedFontSize: 12,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700),
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
              icon: Icon(Icons.check_circle_outline),
              activeIcon: Icon(Icons.check_circle),
              label: 'Tasks',
            ),
          ],
        ),
      ),
    );
  }
}
