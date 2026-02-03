import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_library_app/services/server_download_sync_service.dart';

class AutoSyncService {
  static const String _enabledKey = 'auto_sync_enabled';
  static Timer? _timer;

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? false;
  }

  static Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);
    if (enabled) {
      _start();
    } else {
      _stop();
    }
  }

  static Future<void> initialize() async {
    final enabled = await isEnabled();
    if (enabled) {
      _start();
    }
  }

  static Future<void> runNow() async {
    ServerDownloadSyncService.start();
  }

  static void _start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 15), (_) {
      runNow();
    });
    runNow();
  }

  static void _stop() {
    _timer?.cancel();
    _timer = null;
  }
}


