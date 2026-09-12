import 'package:flutter/material.dart';
import 'dashboard_screen.dart';
import 'study_vault_screen.dart';
import 'voice_notes_screen.dart';
import 'ocr_scanner_screen.dart';
import 'pal_brain_screen.dart';

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
    setState(() {
      _currentIndex = index;
    });

    if (index == 4 && initialQuery != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _brainKey.currentState?.setQuery(
          initialQuery,
          ragScope: filterUnit ?? filterSubject,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = [
      DashboardScreen(onNavigateTab: (idx) => _switchTab(idx)),
      StudyVaultScreen(onNavigateToBrain: _switchTab),
      VoiceNotesScreen(onNavigateToBrain: _switchTab),
      OcrScannerScreen(onNavigateToBrain: _switchTab),
      PalBrainScreen(key: _brainKey),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_outlined),
            activeIcon: Icon(Icons.dashboard),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.folder_outlined),
            activeIcon: Icon(Icons.folder),
            label: 'Vault',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.mic_none),
            activeIcon: Icon(Icons.mic),
            label: 'Voice',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.document_scanner_outlined),
            activeIcon: Icon(Icons.document_scanner),
            label: 'OCR',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.psychology_outlined),
            activeIcon: Icon(Icons.psychology),
            label: 'Brain',
          ),
        ],
      ),
    );
  }
}
