import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:music_library_app/models/media_item.dart';
import 'package:music_library_app/services/storage_service.dart';
import 'package:path_provider/path_provider.dart';

final MethodChannel _nativeMetadata = const MethodChannel('native_metadata');

class MetadataService {
  static bool _isPlaceholderMetadata(MediaItem item) {
    return item.artist == 'Server' || item.album == 'Server Library';
  }

  static String? _inferAlbumFromPath(String path) {
    if (path.isEmpty) return null;
    final parts = path.split('/');
    if (parts.length < 2) return null;
    final parent = parts[parts.length - 2].trim();
    if (parent.isEmpty) return null;

    final cleaned = parent
        .replaceAll('_', ' ')
        .replaceAll(RegExp(r'^\d+\.\s*'), '')
        .trim();
    return cleaned.isEmpty ? null : cleaned;
  }

  static Future<MediaItem> enrichFromLocalFile(
    MediaItem item, {
    bool force = false,
  }) async {
    if (!item.isDownloaded) return item;
    if (item.filePath.isEmpty) return item;

    final file = File(item.filePath);
    if (!await file.exists()) return item;

    if (!force && !_isPlaceholderMetadata(item)) {
      return item;
    }

    try {
      print('MetadataService: Extracting metadata from: ${item.filePath}');
      final extractedData = await _nativeMetadata.invokeMapMethod<String, dynamic>(
            'read',
            {'filePath': item.filePath},
          ) ??
          <String, dynamic>{};

      print('MetadataService: Raw extracted data: $extractedData');

      final extractedTitle = (extractedData['title'] as String?)?.trim();
      final extractedArtist = (extractedData['artist'] as String?)?.trim();
      final extractedAlbum = (extractedData['album'] as String?)?.trim();
      final extractedGenre = (extractedData['genre'] as String?)?.trim();
      final extractedYear = extractedData['year'] as int?;
      final durationMs = extractedData['durationMs'] as int?;
      final extractedDurationSeconds = durationMs != null ? (durationMs / 1000).round() : null;

      print('MetadataService: Parsed - Title: $extractedTitle, Artist: $extractedArtist, Album: $extractedAlbum, Duration: $extractedDurationSeconds');

      String? coverArtPath;
      final artworkTyped = extractedData['artworkBytes'];
      if (artworkTyped is Uint8List && artworkTyped.isNotEmpty) {
        final directory = await getApplicationDocumentsDirectory();
        final artDir = Directory('${directory.path}/AlbumArt');
        if (!await artDir.exists()) {
          await artDir.create(recursive: true);
        }
        final safeId = item.id.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').replaceAll(' ', '_');
        final artPath = '${artDir.path}/$safeId.jpg';
        final artFile = File(artPath);
        await artFile.writeAsBytes(artworkTyped);
        coverArtPath = artPath;
      }

      final inferredAlbum = _inferAlbumFromPath(item.cloudId ?? item.id);

      final shouldReplaceAlbumPlaceholder =
          (item.album.isEmpty || item.album == 'Server Library') && (inferredAlbum != null && inferredAlbum.isNotEmpty);

      final enriched = item.copyWith(
        title: (extractedTitle != null && extractedTitle.isNotEmpty) ? extractedTitle : item.title,
        artist: (extractedArtist != null && extractedArtist.isNotEmpty) ? extractedArtist : item.artist,
        album: (extractedAlbum != null && extractedAlbum.isNotEmpty)
            ? extractedAlbum
            : (shouldReplaceAlbumPlaceholder ? inferredAlbum : item.album),
        genre: (extractedGenre != null && extractedGenre.isNotEmpty) ? extractedGenre : item.genre,
        year: extractedYear ?? item.year,
        duration: extractedDurationSeconds ?? item.duration,
        coverArtPath: coverArtPath ?? item.coverArtPath,
      );

      print('MetadataService: Before enrichment - Title: ${item.title}, Artist: ${item.artist}, Album: ${item.album}');
      print('MetadataService: After enrichment - Title: ${enriched.title}, Artist: ${enriched.artist}, Album: ${enriched.album}');
      
      return enriched;
    } catch (e, stackTrace) {
      print('MetadataService: Error extracting metadata: $e');
      print('MetadataService: Stack trace: $stackTrace');
      return item;
    }
  }

  static Future<int> reEnrichAllDownloadedItems() async {
    final allItems = await StorageService.getAllMediaItems();
    final downloadedWithPlaceholders = allItems.where((item) =>
        item.isDownloaded &&
        (item.artist == 'Server' || item.album == 'Server Library')).toList();

    int enriched = 0;
    for (final item in downloadedWithPlaceholders) {
      try {
        final enrichedItem = await enrichFromLocalFile(item, force: true);
        if (enrichedItem.album != item.album || enrichedItem.artist != item.artist) {
          await StorageService.updateMediaItem(enrichedItem);
          enriched++;
        }
      } catch (e) {
      }
    }
    return enriched;
  }
}


