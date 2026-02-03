import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:music_library_app/models/media_item.dart';
import 'package:music_library_app/models/playlist.dart';
import 'package:music_library_app/screens/playlist_detail_screen.dart';
import 'package:music_library_app/screens/playlists_screen.dart';
import 'package:music_library_app/services/audio_service.dart';
import 'package:music_library_app/services/storage_service.dart';
import 'package:music_library_app/utils/restricted.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_library_app/widgets/playlist_card.dart';
import 'package:music_library_app/widgets/playlist_editor_dialog.dart';

class OverviewScreen extends StatefulWidget {
  const OverviewScreen({super.key});

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen> {
  bool _loading = true;
  List<MediaItem> _recentlyPlayed = [];
  List<MediaItem> _mostPlayed = [];
  List<MediaItem> _recentlyAdded = [];
  List<MediaItem> _favorites = [];
  List<Playlist> _playlists = [];

  @override
  void initState() {
    super.initState();
    _loadPersonalizedContent();
  }

  Future<void> _loadPersonalizedContent() async {
    setState(() {
      _loading = true;
    });

    try {
      final allItems = await StorageService.getAllMediaItems();
      final downloadedItems = allItems
          .where((m) => m.isDownloaded && !isRestrictedMediaItem(m))
          .toList();

      final recentlyPlayed = downloadedItems
          .where((m) => m.lastPlayed != null)
          .toList()
        ..sort((a, b) => b.lastPlayed!.compareTo(a.lastPlayed!));
      final recent20 = recentlyPlayed.take(20).toList();

      final mostPlayed = downloadedItems
          .where((m) => m.playCount > 0)
          .toList()
        ..sort((a, b) => b.playCount.compareTo(a.playCount));
      final top20 = mostPlayed.take(20).toList();

      final recentlyAdded = downloadedItems.toList()
        ..sort((a, b) => b.dateAdded.compareTo(a.dateAdded));
      final added20 = recentlyAdded.take(20).toList();

      final prefs = await SharedPreferences.getInstance();
      final favoriteIds = prefs.getStringList('favorites') ?? [];
      final favorites = downloadedItems.where((m) => favoriteIds.contains(m.id)).toList();
      List<Playlist> playlists = [];
      try {
        playlists = await StorageService.getAllPlaylists();
      } catch (_) {
        playlists = [];
      }

      if (!mounted) return;
      setState(() {
        _recentlyPlayed = recent20;
        _mostPlayed = top20;
        _recentlyAdded = added20;
        _favorites = favorites;
        _playlists = playlists;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _recentlyPlayed = [];
        _mostPlayed = [];
        _recentlyAdded = [];
        _favorites = [];
        _playlists = [];
        _loading = false;
      });
    }
  }

  Future<void> _playItem(MediaItem item) async {
    try {
      await AudioService.play(item);
    } catch (e) {
      if (!mounted) return;
      final errorMsg = e.toString().replaceAll('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to play: $errorMsg'),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Overview'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _loadPersonalizedContent,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadPersonalizedContent,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildPlaylistsSection(),
                  const SizedBox(height: 24),
                  if (_favorites.isNotEmpty) ...[
                    _buildSectionHeader('Your Favorites', Icons.favorite),
                    _buildHorizontalList(_favorites.take(10).toList()),
                    const SizedBox(height: 24),
                  ],
                  if (_recentlyPlayed.isNotEmpty) ...[
                    _buildSectionHeader('Recently Played', Icons.history),
                    _buildHorizontalList(_recentlyPlayed),
                    const SizedBox(height: 24),
                  ],
                  if (_mostPlayed.isNotEmpty) ...[
                    _buildSectionHeader('Most Played', Icons.trending_up),
                    _buildHorizontalList(_mostPlayed),
                    const SizedBox(height: 24),
                  ],
                  if (_recentlyAdded.isNotEmpty) ...[
                    _buildSectionHeader('Recently Added', Icons.add_circle_outline),
                    _buildHorizontalList(_recentlyAdded),
                    const SizedBox(height: 24),
                  ],
                  if (_recentlyPlayed.isEmpty &&
                      _mostPlayed.isEmpty &&
                      _recentlyAdded.isEmpty &&
                      _favorites.isEmpty &&
                      _playlists.isEmpty)
                    _buildEmptyState(),
                ],
              ),
            ),
    );
  }

  Widget _buildPlaylistsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.playlist_play, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              'Playlists',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () async {
                final created = await showPlaylistEditorDialog(context);
                if (created == null) return;
                await StorageService.insertPlaylist(created);
                await _loadPersonalizedContent();
              },
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PlaylistsScreen()),
                ).then((_) => _loadPersonalizedContent());
              },
              child: const Text('Manage'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_playlists.isEmpty)
          Card(
            child: ListTile(
              leading: const Icon(Icons.playlist_add),
              title: const Text('Create a playlist'),
              onTap: () async {
                final created = await showPlaylistEditorDialog(context);
                if (created == null) return;
                await StorageService.insertPlaylist(created);
                await _loadPersonalizedContent();
              },
            ),
          )
        else
          SizedBox(
            height: 260,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _playlists.length > 10 ? 10 : _playlists.length,
              itemBuilder: (context, index) {
                final playlist = _playlists[index];
                return SizedBox(
                  width: 200,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: PlaylistCard(
                      playlist: playlist,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => PlaylistDetailScreen(playlistId: playlist.id),
                          ),
                        ).then((_) => _loadPersonalizedContent());
                      },
                      onEdit: () async {
                        final updated = await showPlaylistEditorDialog(context, playlist: playlist);
                        if (updated == null) return;
                        await StorageService.updatePlaylist(updated);
                        await _loadPersonalizedContent();
                      },
                      onDelete: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Delete playlist'),
                            content: Text('Delete "${playlist.name}"?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(true),
                                child: const Text('Delete'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed != true) return;
                        await StorageService.deletePlaylist(playlist.id);
                        await _loadPersonalizedContent();
                      },
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildHorizontalList(List<MediaItem> items) {
    if (items.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 200,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return SizedBox(
            width: 160,
            child: Card(
              margin: const EdgeInsets.only(right: 12),
              child: InkWell(
                onTap: () => _playItem(item),
                borderRadius: BorderRadius.circular(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(12),
                        ),
                        child: _buildCoverArt(item),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCoverArt(MediaItem item) {
    if (item.isDownloaded && item.coverArtPath != null && item.coverArtPath!.isNotEmpty) {
      final artFile = File(item.coverArtPath!);
      return Image.file(
        artFile,
        fit: BoxFit.cover,
        width: double.infinity,
        errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
      );
    }

    if (item.cloudId != null && item.cloudId!.isNotEmpty) {
      final encoded = Uri.encodeComponent(item.cloudId!);
      final coverUrl = 'https://m.juicewrldapi.com/album-art?filepath=$encoded';
      return CachedNetworkImage(
        imageUrl: coverUrl,
        fit: BoxFit.cover,
        width: double.infinity,
        placeholder: (context, url) => _buildPlaceholder(),
        errorWidget: (context, url, error) => _buildPlaceholder(),
      );
    }

    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() {
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.surfaceVariant,
      child: Icon(
        Icons.music_note,
        size: 64,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.music_off,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'No personalized content yet',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Start playing music to see your recents and favorites here',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
