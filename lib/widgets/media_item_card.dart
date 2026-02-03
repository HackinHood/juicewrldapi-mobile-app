import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:music_library_app/models/media_item.dart';

class MediaItemCard extends StatelessWidget {
  final MediaItem mediaItem;
  final VoidCallback? onTap;
  final VoidCallback? onDownload;
  final VoidCallback? onMore;

  const MediaItemCard({
    super.key,
    required this.mediaItem,
    this.onTap,
    this.onDownload,
    this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: _buildCoverArt(),
        title: Text(
          mediaItem.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              mediaItem.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (mediaItem.album.isNotEmpty)
              Text(
                mediaItem.album,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey[600],
                ),
              ),
          ],
        ),
        trailing: _buildTrailingWidgets(),
        onTap: onTap,
      ),
    );
  }

  Widget _buildCoverArt() {
    final localArtPath = mediaItem.coverArtPath;
    if (localArtPath != null && localArtPath.isNotEmpty) {
      final file = File(localArtPath);
      if (file.existsSync()) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Image.file(
            file,
            fit: BoxFit.cover,
            width: 48,
            height: 48,
            errorBuilder: (context, error, stackTrace) => _buildDefaultIcon(),
          ),
        );
      }
    }

    final coverUrl = _buildCoverUrl();
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(4),
      ),
      child: coverUrl != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: CachedNetworkImage(
                imageUrl: coverUrl,
                fit: BoxFit.cover,
                errorWidget: (context, url, error) => _buildDefaultIcon(),
                placeholder: (context, url) => _buildDefaultIcon(),
              ),
            )
          : _buildDefaultIcon(),
    );
  }

  Widget _buildDefaultIcon() {
    return const Icon(
      Icons.music_note,
      color: Colors.grey,
    );
  }

  String? _buildCoverUrl() {
    final cloudId = mediaItem.cloudId;
    if (cloudId != null && cloudId.isNotEmpty) {
      final encoded = Uri.encodeComponent(cloudId);
      return 'https://m.juicewrldapi.com/album-art?filepath=$encoded';
    }

    final path = mediaItem.filePath;
    final lower = path.toLowerCase();
    final isServerPath = lower.startsWith('audio/') ||
        lower.startsWith('studio_sessions/') ||
        lower.startsWith('studio-sessions/');
    if (!isServerPath) return null;

    final encodedPath = Uri.encodeComponent(path);
    return 'https://m.juicewrldapi.com/album-art?filepath=$encodedPath';
  }

  Widget _buildTrailingWidgets() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!mediaItem.isDownloaded)
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: onDownload,
            tooltip: 'Download',
          ),
        IconButton(
          icon: const Icon(Icons.more_vert),
          onPressed: onMore,
          tooltip: 'More options',
        ),
      ],
    );
  }
}
