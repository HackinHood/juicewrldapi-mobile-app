import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:music_library_app/models/media_item.dart';
import 'package:music_library_app/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_library_app/services/server_root_prefs.dart';

List<Map<String, dynamic>> _extractServerEntriesInBackground(String body) {
  final decoded = jsonDecode(body);
  if (decoded is! Map<String, dynamic>) return const [];
  final files = decoded['files'];
  if (files is! List) return const [];

  const restrictedTokens = [
    'session edits',
    'studio sessions',
    'studio-sessions',
    'studio_sessions',
  ];

  String titleFromPath(String path) {
    final parts = path.split('/');
    final filename = parts.isNotEmpty ? parts.last : path;
    final dotIndex = filename.lastIndexOf('.');
    if (dotIndex > 0) return filename.substring(0, dotIndex);
    return filename;
  }

  final result = <Map<String, dynamic>>[];
  for (final raw in files) {
    if (raw is! Map<String, dynamic>) continue;
    final filepath = raw['filepath'];
    if (filepath is! String || filepath.isEmpty) continue;

    final lower = filepath.toLowerCase();
    bool isRestricted = false;
    for (final token in restrictedTokens) {
      if (lower.contains(token)) {
        isRestricted = true;
        break;
      }
    }
    if (isRestricted) continue;

    final timestampRaw = raw['timestamp'];
    int tsMs = DateTime.now().millisecondsSinceEpoch;
    if (timestampRaw is String) {
      final dt = DateTime.tryParse(timestampRaw);
      if (dt != null) tsMs = dt.millisecondsSinceEpoch;
    }

    result.add({
      'id': filepath,
      'title': titleFromPath(filepath),
      'timestampMs': tsMs,
    });
  }

  return result;
}

class MasterServerService {
  static final Dio _dio = Dio();
  static const String _baseUrl = 'https://m.juicewrldapi.com';
  static const String _lastCommitPrefsKey = 'server_latest_commit_id';
  static const String _lastRootsPrefsKey = 'server_latest_roots_key';

  static Future<void> clearCacheMetadata() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_lastCommitPrefsKey);
      await prefs.remove(_lastRootsPrefsKey);
    } catch (_) {}
  }

  static Future<List<String>> fetchRootFolders() async {
    final historyResponse = await _dio.get(
      '$_baseUrl/commits/history',
      queryParameters: {'limit': 1},
    );

    if (historyResponse.statusCode != 200) {
      return const [];
    }

    final historyData = historyResponse.data;
    if (historyData is! List || historyData.isEmpty) {
      return const [];
    }

    final latestCommit = historyData.first;
    final commitId = latestCommit['id'];
    if (commitId is! String || commitId.isEmpty) {
      return const [];
    }

    final stateResponse = await _dio.get<String>(
      '$_baseUrl/commits/$commitId/state',
      options: Options(responseType: ResponseType.plain),
    );
    if (stateResponse.statusCode != 200) {
      return const [];
    }
    final stateBody = stateResponse.data;
    if (stateBody == null || stateBody.isEmpty) {
      return const [];
    }

    final entries = await compute(_extractServerEntriesInBackground, stateBody);
    if (entries.isEmpty) return const [];

    final roots = <String>{};
    for (final e in entries) {
      final id = e['id'];
      if (id is! String || id.isEmpty) continue;
      final root = ServerRootPrefs.rootFromPath(id);
      if (root == null || root.isEmpty) continue;
      roots.add(root);
    }
    final list = roots.toList()..sort();
    return list;
  }

  static Future<List<String>> fetchAllFilePaths() async {
    final historyResponse = await _dio.get(
      '$_baseUrl/commits/history',
      queryParameters: {'limit': 1},
    );
    if (historyResponse.statusCode != 200) return const [];
    final historyData = historyResponse.data;
    if (historyData is! List || historyData.isEmpty) return const [];
    final latestCommit = historyData.first;
    final commitId = latestCommit['id'];
    if (commitId is! String || commitId.isEmpty) return const [];

    final stateResponse = await _dio.get<String>(
      '$_baseUrl/commits/$commitId/state',
      options: Options(responseType: ResponseType.plain),
    );
    if (stateResponse.statusCode != 200) return const [];
    final stateBody = stateResponse.data;
    if (stateBody == null || stateBody.isEmpty) return const [];

    final entries = await compute(_extractServerEntriesInBackground, stateBody);
    if (entries.isEmpty) return const [];
    final paths = <String>[];
    for (final e in entries) {
      final id = e['id'];
      if (id is String && id.isNotEmpty) {
        paths.add(id);
      }
    }
    return paths;
  }

  static Future<List<MediaItem>> fetchServerFiles() async {
    try {
      final historyResponse = await _dio.get(
        '$_baseUrl/commits/history',
        queryParameters: {'limit': 1},
      );

      if (historyResponse.statusCode != 200) {
        final cached = await StorageService.getCachedServerItems();
        if (cached.isNotEmpty) return cached;
        throw Exception('Server returned status ${historyResponse.statusCode}');
      }

      final historyData = historyResponse.data;
      if (historyData is! List || historyData.isEmpty) {
        final cached = await StorageService.getCachedServerItems();
        if (cached.isNotEmpty) return cached;
        throw Exception('No commit history available');
      }

      final latestCommit = historyData.first;
      final commitId = latestCommit['id'];
      if (commitId is! String || commitId.isEmpty) {
        final cached = await StorageService.getCachedServerItems();
        if (cached.isNotEmpty) return cached;
        throw Exception('Invalid commit ID');
      }

      final included = await ServerRootPrefs.getIncludedPrefixes();
      final excluded = await ServerRootPrefs.getExcludedPrefixes();
      final includeKey = included == null ? 'ALL' : (included.toList()..sort()).join(',');
      final excludeKey = (excluded.toList()..sort()).join(',');
      final rootsKey = '$includeKey|$excludeKey';

      try {
        final prefs = await SharedPreferences.getInstance();
        final lastCommit = prefs.getString(_lastCommitPrefsKey);
        final lastRootsKey = prefs.getString(_lastRootsPrefsKey);
        if (lastCommit == commitId && lastRootsKey == rootsKey) {
          final cached = await StorageService.getCachedServerItems();
          if (cached.isNotEmpty) return cached;
        }
      } catch (_) {}

      final stateResponse = await _dio.get<String>(
        '$_baseUrl/commits/$commitId/state',
        options: Options(responseType: ResponseType.plain),
      );
      if (stateResponse.statusCode != 200) {
        final cached = await StorageService.getCachedServerItems();
        if (cached.isNotEmpty) return cached;
        throw Exception('Failed to fetch commit state: ${stateResponse.statusCode}');
      }
      final stateBody = stateResponse.data;
      if (stateBody == null || stateBody.isEmpty) {
        final cached = await StorageService.getCachedServerItems();
        if (cached.isNotEmpty) return cached;
        throw Exception('Empty commit state');
      }

      final entries = await compute(_extractServerEntriesInBackground, stateBody);
      if (entries.isEmpty) {
        return await StorageService.getCachedServerItems();
      }

      final filteredEntries = included == null && excluded.isEmpty
          ? entries
          : entries.where((e) {
              final id = e['id'];
              if (id is! String) return false;
              return ServerRootPrefs.isAllowedPath(id, included, excluded);
            }).toList();

      await StorageService.batchUpsertServerFileEntries(filteredEntries, baseUrl: _baseUrl);
      if (included != null || excluded.isNotEmpty) {
        await StorageService.deleteCachedServerItemsNotAllowed(
          (path) => ServerRootPrefs.isAllowedPath(path, included, excluded),
        );
      }

      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_lastCommitPrefsKey, commitId);
        await prefs.setString(_lastRootsPrefsKey, rootsKey);
      } catch (_) {}

      return await StorageService.getCachedServerItems();
    } catch (e) {
      final cached = await StorageService.getCachedServerItems();
      if (cached.isNotEmpty) return cached;
      rethrow;
    }
  }

}


