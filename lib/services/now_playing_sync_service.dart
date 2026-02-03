import 'dart:io';
import 'package:dio/dio.dart';
import 'package:music_library_app/models/media_item.dart';
import 'package:music_library_app/services/sync_service.dart';

class NowPlayingSyncService {
  static final Dio _dio = Dio();
  static const String _baseUrl = 'https://m.juicewrldapi.com';

  static int _lastSentAtMs = 0;
  static String _lastKey = '';

  static String? _albumArtUrlFor(MediaItem item) {
    final cloudId = item.cloudId;
    if (cloudId != null && cloudId.isNotEmpty) {
      final encoded = Uri.encodeComponent(cloudId);
      return '$_baseUrl/album-art?filepath=$encoded';
    }

    final path = item.filePath;
    if (path.isEmpty) return null;
    final lower = path.toLowerCase();
    final isServerPath =
        lower.startsWith('audio/') || lower.startsWith('studio_sessions/') || lower.startsWith('studio-sessions/');
    if (!isServerPath) return null;
    final encodedPath = Uri.encodeComponent(path);
    return '$_baseUrl/album-art?filepath=$encodedPath';
  }

  static Future<void> updateNowPlaying({
    required MediaItem item,
    required bool isPlaying,
    required Duration position,
    Duration? duration,
    required bool isShuffle,
    required String repeatMode,
    bool force = false,
  }) async {
    final headers = await SyncService.getAuthHeaders();
    if (headers.isEmpty) return;

    final trackName = item.title;
    final artistName = item.artist;
    final albumName = item.album;
    final durationMs = (duration ?? Duration(seconds: item.duration > 0 ? item.duration : 0)).inMilliseconds;
    final positionMs = position.inMilliseconds;
    final isRepeat = repeatMode != 'off';
    final artUrl = _albumArtUrlFor(item) ?? '';

    final key =
        '${item.id}|$isPlaying|$positionMs|$durationMs|$isRepeat|$isShuffle|$trackName|$artistName|$albumName|$artUrl';
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (!force) {
      if (_lastKey == key) return;
      if (nowMs - _lastSentAtMs < 15000 && _lastKey.startsWith('${item.id}|$isPlaying|')) return;
    }

    _lastKey = key;
    _lastSentAtMs = nowMs;

    await _dio.post(
      '$_baseUrl/analytics/now-playing/update',
      options: Options(headers: headers),
      data: {
        'track_name': trackName,
        'artist_name': artistName,
        'album_name': albumName,
        'album_art_url': artUrl,
        'track_id': item.id,
        'duration_ms': durationMs,
        'position_ms': positionMs,
        'is_playing': isPlaying,
        'is_repeat': isRepeat,
        'is_shuffle': isShuffle,
        'device_name': 'Mobile-${Platform.operatingSystem}',
      },
    );
  }

  static Future<void> stopNowPlaying() async {
    final headers = await SyncService.getAuthHeaders();
    if (headers.isEmpty) return;

    await _dio.post(
      '$_baseUrl/analytics/now-playing/stop/',
      options: Options(headers: headers),
      data: {'device_name': 'Mobile-${Platform.operatingSystem}'},
    );
  }
}

