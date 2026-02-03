import 'package:music_library_app/models/media_item.dart';

bool isRestrictedMediaItem(MediaItem item) {
  final sources = <String>[];
  if (item.filePath.isNotEmpty) {
    sources.add(item.filePath);
  }
  if (item.downloadUrl != null) {
    sources.add(item.downloadUrl!);
  }
  if (item.cloudId != null) {
    sources.add(item.cloudId!);
  }
  const restrictedTokens = [
    'session edits',
    'studio sessions',
    'studio-sessions',
    'studio_sessions',
  ];
  for (final raw in sources) {
    final lower = raw.toLowerCase();
    for (final token in restrictedTokens) {
      if (lower.contains(token)) {
        return true;
      }
    }
  }
  return false;
}


