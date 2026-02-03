import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_library_app/models/media_item.dart';
import 'package:music_library_app/models/playlist.dart';
import 'package:music_library_app/services/storage_service.dart';
import 'package:music_library_app/utils/restricted.dart';

class SyncService {
  static final Dio _dio = Dio();
  static const String _baseUrl = 'https://m.juicewrldapi.com';
  static const String _tokenKey = 'sync_token';
  static const String _tokenExpiresAtKey = 'sync_token_expires_at';
  static const String _lastSyncKey = 'last_sync';

  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    if (token == null || token.trim().isEmpty) return false;
    final expiresAtMs = prefs.getInt(_tokenExpiresAtKey);
    if (expiresAtMs == null) return true;
    return DateTime.now().millisecondsSinceEpoch < expiresAtMs;
  }

  static Future<bool> pairWithCode(String code, {String deviceName = 'Mobile App'}) async {
    try {
      final normalized = code.trim().toUpperCase();
      if (normalized.isEmpty) return false;

      final response = await _dio.post(
        '$_baseUrl/auth/pairing/redeem',
        data: {
          'code': normalized,
          'device_name': deviceName,
        },
      );

      if (response.statusCode == 200) {
        final token = response.data['refresh_token'];
        final prefs = await SharedPreferences.getInstance();
        if (token is! String || token.trim().isEmpty) return false;
        await prefs.setString(_tokenKey, token);
        final expiresAtRaw = response.data['expires_at'];
        if (expiresAtRaw is String) {
          final dt = DateTime.tryParse(expiresAtRaw);
          if (dt != null) {
            await prefs.setInt(_tokenExpiresAtKey, dt.millisecondsSinceEpoch);
          }
        }
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> refreshAuthToken() async {
    try {
      final token = await _getToken();
      if (token == null || token.trim().isEmpty) return false;

      final response = await _dio.post(
        '$_baseUrl/auth/refresh',
        data: {'refresh_token': token},
      );

      if (response.statusCode != 200) return false;
      final newToken = response.data['refresh_token'];
      if (newToken is! String || newToken.trim().isEmpty) return false;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, newToken);

      final expiresAtRaw = response.data['expires_at'];
      if (expiresAtRaw is String) {
        final dt = DateTime.tryParse(expiresAtRaw);
        if (dt != null) {
          await prefs.setInt(_tokenExpiresAtKey, dt.millisecondsSinceEpoch);
        }
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_tokenExpiresAtKey);
    await prefs.remove(_lastSyncKey);
  }

  static Future<DateTime?> getLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp = prefs.getInt(_lastSyncKey);
    return timestamp != null ? DateTime.fromMillisecondsSinceEpoch(timestamp) : null;
  }

  static Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  static Future<String?> getToken() async {
    return _getToken();
  }

  static Future<Map<String, String>> getAuthHeaders() async {
    final token = await _getToken();
    if (token == null || token.trim().isEmpty) return const {};
    final prefs = await SharedPreferences.getInstance();
    final expiresAtMs = prefs.getInt(_tokenExpiresAtKey);
    if (expiresAtMs != null && DateTime.now().millisecondsSinceEpoch >= expiresAtMs) {
      final refreshed = await refreshAuthToken();
      if (!refreshed) return const {};
      final refreshedToken = await _getToken();
      if (refreshedToken == null || refreshedToken.trim().isEmpty) return const {};
      return {'Authorization': 'Token $refreshedToken'};
    }
    return {'Authorization': 'Token $token'};
  }

  static Future<void> syncMediaItems() async {
    final headers = await getAuthHeaders();
    final auth = headers['Authorization'];
    if (auth == null || auth.isEmpty) return;
    final token = auth.replaceFirst('Token ', '');

    try {
      final localItems = await StorageService.getAllMediaItems();
      final lastSync = await _getLastSyncTime();

      final response = await _dio.get(
        '$_baseUrl/media/items',
        queryParameters: {
          'since': lastSync?.millisecondsSinceEpoch,
        },
        options: Options(
          headers: headers,
        ),
      );

      if (response.statusCode == 200) {
        final remoteItems = (response.data['items'] as List)
            .map((item) => MediaItem.fromMap(item))
            .where((item) => !isRestrictedMediaItem(item))
            .toList();

        for (final remoteItem in remoteItems) {
          final localItem = await StorageService.getMediaItem(remoteItem.id);
          if (localItem == null) {
            await StorageService.insertMediaItem(remoteItem);
          } else if (remoteItem.lastModified.isAfter(localItem.lastModified)) {
            await StorageService.updateMediaItem(remoteItem);
          }
        }

        await _uploadLocalChanges(localItems, token);
        await _setLastSyncTime(DateTime.now());
      }
    } catch (e) {
      print('Sync error: $e');
    }
  }

  static Future<void> syncPlaylists() async {
    final headers = await getAuthHeaders();
    final auth = headers['Authorization'];
    if (auth == null || auth.isEmpty) return;
    final token = auth.replaceFirst('Token ', '');

    try {
      final localPlaylists = await StorageService.getAllPlaylists();

      final response = await _dio.get(
        '$_baseUrl/playlists',
        options: Options(
          headers: headers,
        ),
      );

      if (response.statusCode == 200) {
        final remotePlaylists = (response.data['playlists'] as List)
            .map((playlist) => Playlist.fromMap(playlist))
            .toList();

        for (final remotePlaylist in remotePlaylists) {
          final localPlaylist = await StorageService.getPlaylist(remotePlaylist.id);
          if (localPlaylist == null) {
            await StorageService.insertPlaylist(remotePlaylist);
          } else if (remotePlaylist.lastModified.isAfter(localPlaylist.lastModified)) {
            await StorageService.updatePlaylist(remotePlaylist);
          }
        }

        await _uploadPlaylistChanges(localPlaylists, token);
      }
    } catch (e) {
      print('Playlist sync error: $e');
    }
  }

  static Future<void> _uploadLocalChanges(List<MediaItem> localItems, String token) async {
    final unsyncedItems = localItems
        .where((item) => !item.isSynced)
        .where((item) => !isRestrictedMediaItem(item))
        .toList();

    for (final item in unsyncedItems) {
      try {
        await _dio.post(
          '$_baseUrl/media/items',
          data: item.toMap(),
          options: Options(
            headers: {'Authorization': 'Token $token'},
          ),
        );

        final syncedItem = item.copyWith(isSynced: true);
        await StorageService.updateMediaItem(syncedItem);
      } catch (e) {
        print('Upload error for item ${item.id}: $e');
      }
    }
  }

  static Future<void> _uploadPlaylistChanges(List<Playlist> localPlaylists, String token) async {
    final unsyncedPlaylists = localPlaylists.where((playlist) => !playlist.isSynced).toList();

    for (final playlist in unsyncedPlaylists) {
      try {
        await _dio.post(
          '$_baseUrl/playlists',
          data: playlist.toMap(),
          options: Options(
            headers: {'Authorization': 'Token $token'},
          ),
        );

        final syncedPlaylist = playlist.copyWith(isSynced: true);
        await StorageService.updatePlaylist(syncedPlaylist);
      } catch (e) {
        print('Playlist upload error for ${playlist.id}: $e');
      }
    }
  }

  static Future<DateTime?> _getLastSyncTime() async {
    return getLastSyncTime();
  }

  static Future<void> _setLastSyncTime(DateTime time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastSyncKey, time.millisecondsSinceEpoch);
  }

  static Future<void> fullSync() async {
    await syncMediaItems();
    await syncPlaylists();
  }
}
