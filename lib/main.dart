import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:music_library_app/screens/home_screen.dart';
import 'package:music_library_app/services/audio_service.dart';
import 'package:music_library_app/services/system_audio_handler.dart';
import 'package:music_library_app/services/storage_service.dart';
import 'package:music_library_app/services/auto_sync_service.dart';
import 'package:music_library_app/utils/permissions.dart';
import 'package:desktop_window/desktop_window.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      print('FlutterError: ${details.exceptionAsString()}\n${details.stack}');
    };

    ErrorWidget.builder = (details) {
      final message = details.exceptionAsString();
      return Directionality(
        textDirection: TextDirection.ltr,
        child: ColoredBox(
          color: Colors.black,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                message,
                style: const TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      print('Uncaught error: $error\n$stack');
      return true;
    };

    try {
      await StorageService.initialize();
    } catch (e) {
      print('Storage initialization error: $e');
    }

    if (Platform.isIOS) {
      _setupSiriPlaybackHandler();
    }

    runApp(const MusicLibraryApp());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeInBackground();
    });
  }, (error, stack) {
    print('Zone error: $error\n$stack');
  });
}

void _setupSiriPlaybackHandler() {
  const channel = MethodChannel('siri_playback');
  channel.setMethodCallHandler((call) async {
    if (call.method == 'play') {
      final args = call.arguments as Map<dynamic, dynamic>?;
      final itemId = args?['itemId'] as String?;
      if (itemId != null) {
        _handleSiriPlayback(itemId);
      }
    }
  });
}

Future<void> _handleSiriPlayback(String itemId) async {
  try {
    final item = await StorageService.getMediaItem(itemId);
    if (item != null) {
      await AudioService.play(item);
    }
  } catch (e) {
    print('Error handling Siri playback: $e');
  }
}

Future<void> _initializeInBackground() async {
  try {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      try {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
      } catch (e) {
        print('Database factory error: $e');
      }
    }

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      try {
        await DesktopWindow.setMinWindowSize(const Size(800, 600));
        await DesktopWindow.setWindowSize(const Size(1200, 800));
      } catch (e) {
        print('Window size error: $e');
      }
    }

    if (Platform.isAndroid || Platform.isIOS) {
      try {
        await AudioService.initialize();
      } catch (e) {
        print('Audio initialization error: $e');
      }

      try {
        await initSystemAudioHandler();
      } catch (e) {
        print('System audio handler initialization error: $e');
      }
    }

    if (Platform.isAndroid) {
      try {
        await Permissions.requestStoragePermission();
      } catch (e) {
        print('Permission error: $e');
      }
    }
    try {
      await AutoSyncService.initialize();
    } catch (e) {
      print('Auto sync initialization error: $e');
    }
  } catch (e) {
    print('Background initialization error: $e');
  }
}

class MusicLibraryApp extends StatelessWidget {
  const MusicLibraryApp({super.key});

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF00AEEF);
    const secondaryColor = Color(0xFFFFD200);
    const backgroundColor = Color(0xFF050509);
    const surfaceColor = Color(0xFF11131A);

    final colorScheme = const ColorScheme.dark().copyWith(
      primary: primaryColor,
      secondary: secondaryColor,
      tertiary: const Color(0xFF1DE9B6),
      background: backgroundColor,
      surface: surfaceColor,
      onPrimary: Colors.black,
      onSecondary: Colors.black,
      onTertiary: Colors.black,
      onBackground: Colors.white,
      onSurface: Colors.white,
    );

    return MaterialApp(
      title: 'JuiceWRLD API Mobile',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: backgroundColor,
        appBarTheme: const AppBarTheme(
          backgroundColor: surfaceColor,
          foregroundColor: Colors.white,
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: surfaceColor,
          selectedItemColor: secondaryColor,
          unselectedItemColor: Colors.grey,
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: secondaryColor,
          foregroundColor: Colors.black,
        ),
      ),
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
