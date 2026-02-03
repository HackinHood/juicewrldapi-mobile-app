import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_library_app/models/media_item.dart';
import 'package:music_library_app/services/download_service.dart';
import 'package:music_library_app/services/master_server_service.dart';
import 'package:music_library_app/services/server_root_prefs.dart';
import 'package:music_library_app/services/storage_service.dart';
import 'package:music_library_app/utils/restricted.dart';

class ServerDownloadSyncState {
  final bool running;
  final int total;
  final int completed;
  final int failed;
  const ServerDownloadSyncState({
    required this.running,
    required this.total,
    required this.completed,
    required this.failed,
  });
}

class ServerDownloadSyncService {
  static const String _lastServerSyncKey = 'last_server_download_sync';
  static bool _running = false;
  static bool _cancelRequested = false;
  static final _stateController = StreamController<ServerDownloadSyncState>.broadcast();
  static ServerDownloadSyncState _state = const ServerDownloadSyncState(
    running: false,
    total: 0,
    completed: 0,
    failed: 0,
  );

  static bool get isRunning => _running;
  static ServerDownloadSyncState get state => _state;
  static Stream<ServerDownloadSyncState> get stateStream => _stateController.stream;

  static Future<DateTime?> getLastRunTime() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_lastServerSyncKey);
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  static void start({int concurrency = 3}) {
    if (_running) return;
    _cancelRequested = false;
    _running = true;
    _setState(const ServerDownloadSyncState(running: true, total: 0, completed: 0, failed: 0));
    Future<void>(() async {
      try {
        final granted = await DownloadService.requestStoragePermission();
        if (!granted) {
          _setState(const ServerDownloadSyncState(running: false, total: 0, completed: 0, failed: 0));
          return;
        }

        await MasterServerService.fetchServerFiles();
        final included = await ServerRootPrefs.getIncludedPrefixes();
        final excluded = await ServerRootPrefs.getExcludedPrefixes();
        final serverItems = await StorageService.getCachedServerItems();

        final missing = serverItems
            .where((m) => !isRestrictedMediaItem(m))
            .where((m) => !m.isDownloaded)
            .where((m) => ServerRootPrefs.isAllowedPath(m.filePath, included, excluded))
            .toList();

        _setState(ServerDownloadSyncState(
          running: true,
          total: missing.length,
          completed: 0,
          failed: 0,
        ));

        if (missing.isEmpty) {
          await _setLastRunTime();
          _setState(const ServerDownloadSyncState(running: false, total: 0, completed: 0, failed: 0));
          return;
        }

        final limit = concurrency < 1 ? 1 : concurrency;
        int completed = 0;
        int failed = 0;
        int index = 0;

        Future<void> runOne(MediaItem item) async {
          try {
            if (_cancelRequested) return;
            await DownloadService.downloadMediaItem(item);
            completed += 1;
          } catch (_) {
            failed += 1;
          } finally {
            _setState(ServerDownloadSyncState(
              running: true,
              total: missing.length,
              completed: completed,
              failed: failed,
            ));
          }
        }

        final active = <Future<void>>[];
        while (index < missing.length && !_cancelRequested) {
          while (active.length < limit && index < missing.length && !_cancelRequested) {
            final item = missing[index++];
            final f = runOne(item);
            active.add(f);
            f.whenComplete(() {
              active.remove(f);
            });
          }
          if (active.isEmpty) break;
          await Future.any(active);
        }

        if (active.isNotEmpty) {
          await Future.wait(active);
        }

        await _setLastRunTime();
      } finally {
        _running = false;
        _cancelRequested = false;
        _setState(const ServerDownloadSyncState(running: false, total: 0, completed: 0, failed: 0));
      }
    });
  }

  static void cancel() {
    _cancelRequested = true;
  }

  static void _setState(ServerDownloadSyncState next) {
    _state = next;
    if (!_stateController.isClosed) {
      _stateController.add(next);
    }
  }

  static Future<void> _setLastRunTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastServerSyncKey, DateTime.now().millisecondsSinceEpoch);
  }
}


