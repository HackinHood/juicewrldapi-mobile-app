import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class ArtistAlbumGrid extends StatelessWidget {
  final List<String> items;
  final String type;
  final Function(String) onItemTap;
  final Map<String, String?>? albumCoverArt;

  const ArtistAlbumGrid({
    super.key,
    required this.items,
    required this.type,
    required this.onItemTap,
    this.albumCoverArt,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.8,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final coverArtPath = type == 'album' && albumCoverArt != null 
            ? albumCoverArt![item] 
            : null;
        return _buildItemCard(context, item, coverArtPath);
      },
    );
  }

  Widget _buildItemCard(BuildContext context, String item, String? coverArtPath) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onItemTap(item),
        borderRadius: BorderRadius.circular(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: _buildCoverArt(context, item, coverArtPath),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                item,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCoverArt(BuildContext context, String item, String? coverArtPath) {
    if (type == 'album' && coverArtPath != null && coverArtPath.isNotEmpty) {
      final file = File(coverArtPath);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: BoxFit.cover,
          width: double.infinity,
          errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
        );
      }

      final lower = coverArtPath.toLowerCase();
      final isServerPath = lower.startsWith('audio/') ||
          lower.startsWith('studio_sessions/') ||
          lower.startsWith('studio-sessions/') ||
          lower.startsWith('compilation/');
      if (isServerPath) {
        final encodedPath = Uri.encodeComponent(coverArtPath);
        final url = 'https://m.juicewrldapi.com/album-art?filepath=$encodedPath';
        return CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          width: double.infinity,
          placeholder: (context, url) => _buildPlaceholder(),
          errorWidget: (context, url, error) => _buildPlaceholder(),
        );
      }
    }

    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.grey[800],
      ),
      child: Icon(
        type == 'artist' ? Icons.person : Icons.album,
        size: 48,
        color: Colors.grey[600],
      ),
    );
  }
}
