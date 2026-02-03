import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_library_app/models/media_item.dart';
import 'package:music_library_app/services/storage_service.dart';
import 'package:music_library_app/services/metadata_service.dart';

class DownloadService {
  static final Dio _dio = Dio();
  static final Map<String, CancelToken> _activeDownloads = {};
  static const String _downloadDirKey = 'download_directory_path';

  static Future<String> getDownloadDirectory() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_downloadDirKey);
    if (saved != null && saved.trim().isNotEmpty) {
      return saved;
    }
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}/Music';
  }

  static Future<void> setDownloadDirectory(String path) async {
    final cleaned = path.trim();
    final prefs = await SharedPreferences.getInstance();
    if (cleaned.isEmpty) {
      await prefs.remove(_downloadDirKey);
      return;
    }
    await prefs.setString(_downloadDirKey, cleaned);
  }

  static Future<String> downloadMediaItem(MediaItem item, {
    Function(int received, int total)? onProgress,
    Function()? onComplete,
    Function(String error)? onError,
  }) async {
    if (item.downloadUrl == null) {
      throw Exception('Download URL not available');
    }

    final cancelToken = CancelToken();
    _activeDownloads[item.id] = cancelToken;

    try {
      final downloadRoot = await getDownloadDirectory();
      final musicDir = Directory(downloadRoot);
      if (!await musicDir.exists()) {
        await musicDir.create(recursive: true);
      }

      final safeId = item.id.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').replaceAll(' ', '_');
      final extension = _getFileExtension(item.downloadUrl!);
      final baseFileName = safeId.endsWith('.$extension') ? safeId : '$safeId.$extension';
      final fileName = baseFileName;
      final filePath = '${musicDir.path}/$fileName';

      await _dio.download(
        item.downloadUrl!,
        filePath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (onProgress != null) {
            onProgress(received, total);
          }
        },
      );

      final downloadedFile = File(filePath);
      if (!await downloadedFile.exists()) {
        throw Exception('Downloaded file does not exist at path: $filePath');
      }

      final fileSize = await downloadedFile.length();
      if (fileSize == 0) {
        throw Exception('Downloaded file is empty');
      }

      print('DownloadService: Successfully downloaded file: $filePath (size: $fileSize bytes)');
      print('DownloadService: Original item filePath: ${item.filePath}');
      print('DownloadService: Original item isDownloaded: ${item.isDownloaded}');

      var updatedItem = item.copyWith(
        filePath: filePath,
        isDownloaded: true,
      );
      await StorageService.updateMediaItem(updatedItem);

      print('DownloadService: Updated item filePath: ${updatedItem.filePath}');
      print('DownloadService: Updated item isDownloaded: ${updatedItem.isDownloaded}');

      MetadataService.enrichFromLocalFile(updatedItem, force: true).then((enriched) async {
        try {
          await StorageService.updateMediaItem(enriched);
          print('DownloadService: Metadata enrichment completed - Artist: ${enriched.artist}, Album: ${enriched.album}');
        } catch (e) {
          print('DownloadService: Failed to update enriched metadata: $e');
        }
      }).catchError((e) {
        print('DownloadService: MetadataService enrich failed: $e');
      });

      _activeDownloads.remove(item.id);

      if (onComplete != null) {
        onComplete();
      }

      return filePath;
    } catch (e) {
      _activeDownloads.remove(item.id);
      if (onError != null) {
        onError(e.toString());
      }
      rethrow;
    }
  }

  static Future<void> cancelDownload(String itemId) async {
    final cancelToken = _activeDownloads[itemId];
    if (cancelToken != null) {
      cancelToken.cancel();
      _activeDownloads.remove(itemId);
    }
  }

  static bool isDownloading(String itemId) {
    return _activeDownloads.containsKey(itemId);
  }

  static Future<bool> requestStoragePermission() async {
    if (Platform.isIOS) return true;
    if (!Platform.isAndroid) return true;
    
    final deviceInfo = DeviceInfoPlugin();
    final androidInfo = await deviceInfo.androidInfo;
    final sdkInt = androidInfo.version.sdkInt;
    
    if (sdkInt >= 33) {
      final photos = await Permission.photos.request();
      final audio = await Permission.audio.request();
      final videos = await Permission.videos.request();
      return photos.isGranted || audio.isGranted || videos.isGranted;
    } else if (sdkInt >= 30) {
      final manageStorage = await Permission.manageExternalStorage.request();
      if (manageStorage.isGranted) return true;
      
      final storage = await Permission.storage.request();
      return storage.isGranted;
    } else {
      final storage = await Permission.storage.request();
      return storage.isGranted;
    }
  }

  static String _getFileExtension(String url) {
    final uri = Uri.parse(url);
    final path = uri.path;
    final lastDot = path.lastIndexOf('.');
    if (lastDot != -1 && lastDot < path.length - 1) {
      return path.substring(lastDot + 1);
    }
    return 'mp3';
  }

  static Future<void> deleteDownloadedFile(MediaItem item) async {
    if (item.isDownloaded && item.filePath.isNotEmpty) {
      final file = File(item.filePath);
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  static Future<Map<String, dynamic>> getDownloadProgress(String itemId) async {
    if (!_activeDownloads.containsKey(itemId)) {
      return {'isDownloading': false};
    }

    return {
      'isDownloading': true,
      'progress': 0.0,
    };
  }
}
