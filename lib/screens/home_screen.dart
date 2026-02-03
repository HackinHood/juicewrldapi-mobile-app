import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:music_library_app/screens/library_screen.dart';
import 'package:music_library_app/screens/overview_screen.dart';
import 'package:music_library_app/screens/server_files_screen.dart';
import 'package:music_library_app/screens/history_screen.dart';
import 'package:music_library_app/screens/settings_screen.dart';
import 'package:music_library_app/screens/transfers_screen.dart';
import 'package:music_library_app/widgets/now_playing_bottom_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 2;
  late final ValueNotifier<int> _indexNotifier = ValueNotifier<int>(_currentIndex);
  late final PageController _pageController = PageController(initialPage: _currentIndex);

  late final List<Widget> _screens = [
    const OverviewScreen(),
    ServerFilesScreen(currentIndexListenable: _indexNotifier),
    const LibraryScreen(),
    const TransfersScreen(),
    const SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView.builder(
        controller: _pageController,
        itemCount: _screens.length,
        onPageChanged: (index) {
          setState(() {
            _currentIndex = index;
          });
          _indexNotifier.value = index;
        },
        itemBuilder: (context, index) => _screens[index],
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
          _indexNotifier.value = index;
          _pageController.animateToPage(
            index,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: 'Overview',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.cloud),
            label: 'Server',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.library_music),
            label: 'Local',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.downloading),
            label: 'Transfers',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (context) => const NowPlayingBottomSheet(),
          );
        },
        child: const Icon(Icons.music_note),
      ),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _indexNotifier.dispose();
    super.dispose();
  }
}
