import 'dart:io';
import 'package:flutter/material.dart';
import 'package:music_library_app/models/media_item.dart';
import 'package:music_library_app/services/storage_service.dart';
import 'package:music_library_app/services/audio_service.dart';
import 'package:music_library_app/services/download_service.dart';
import 'package:music_library_app/widgets/media_item_card.dart';
import 'package:music_library_app/widgets/artist_album_grid.dart';
import 'package:music_library_app/screens/album_songs_screen.dart';
import 'package:music_library_app/utils/restricted.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> with TickerProviderStateMixin {
  late TabController _tabController;
  List<MediaItem> _mediaItems = [];
  List<String> _artists = [];
  List<String> _albums = [];
  Map<String, String?> _albumCoverArt = {};
  bool _isLoading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!mounted) return;
      setState(() {});
    });
    _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    try {
      final allMediaItems = await StorageService.getAllMediaItems();
      if (!mounted) return;
      final downloadedItems = allMediaItems
          .where((m) => m.isDownloaded && !_isServerPath(m.filePath) && !isRestrictedMediaItem(m))
          .toList();
      
      final downloadedArtists = downloadedItems
          .map((m) => m.artist)
          .where((a) => a.isNotEmpty && a != 'Server')
          .toSet()
          .toList()
        ..sort();

      final downloadedAlbums = downloadedItems
          .map((m) => m.album)
          .where((a) => a.isNotEmpty && a != 'Server Library')
          .toSet()
          .toList()
        ..sort();

      final albumCoverArt = <String, String?>{};
      for (final album in downloadedAlbums) {
        final albumSongs = downloadedItems.where((m) => m.album == album).toList();
        if (albumSongs.isEmpty) continue;
        
        final songWithArt = albumSongs.firstWhere(
          (song) => song.coverArtPath != null && song.coverArtPath!.isNotEmpty,
          orElse: () => albumSongs.first,
        );
        
        String? coverArt;
        final localArt = songWithArt.coverArtPath;
        if (localArt != null && localArt.isNotEmpty) {
          final file = File(localArt);
          if (file.existsSync()) {
            coverArt = localArt;
          }
        }
        if (coverArt == null || coverArt.isEmpty) {
          final candidate = songWithArt.cloudId ?? songWithArt.id;
          if (candidate.isNotEmpty) {
            coverArt = candidate;
          }
        }
        
        albumCoverArt[album] = coverArt;
      }

      if (!mounted) return;
      setState(() {
        _mediaItems = downloadedItems;
        _artists = downloadedArtists;
        _albums = downloadedAlbums;
        _albumCoverArt = albumCoverArt;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  bool _isServerPath(String path) {
    final lower = path.toLowerCase();
    if (lower.startsWith('/audio/')) return true;
    if (lower.startsWith('audio/')) return true;
    if (lower.startsWith('/studio_sessions/') || lower.startsWith('/studio-sessions/')) return true;
    if (lower.startsWith('studio_sessions/') || lower.startsWith('studio-sessions/')) return true;
    return false;
  }

  List<MediaItem> get _filteredItems {
    if (_query.trim().isEmpty) {
      return _mediaItems;
    }
    final lower = _query.toLowerCase();
    return _mediaItems.where((m) {
      return m.title.toLowerCase().contains(lower) ||
          m.artist.toLowerCase().contains(lower) ||
          m.album.toLowerCase().contains(lower);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final canQueueSongs = !_isLoading && _filteredItems.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Local Library'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(112),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search local library',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  onChanged: (value) {
                    setState(() {
                      _query = value;
                    });
                  },
                ),
              ),
              TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(text: 'Songs'),
                  Tab(text: 'Artists'),
                  Tab(text: 'Albums'),
                ],
              ),
            ],
          ),
        ),
        actions: [
          if (_tabController.index == 0) ...[
            IconButton(
              icon: const Icon(Icons.play_arrow),
              onPressed: canQueueSongs ? () => AudioService.playQueue(_filteredItems, shuffle: false) : null,
            ),
            IconButton(
              icon: const Icon(Icons.shuffle),
              onPressed: canQueueSongs ? () => AudioService.playQueue(_filteredItems, shuffle: true) : null,
            ),
          ],
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildSongsTab(),
          _buildArtistsTab(),
          _buildAlbumsTab(),
        ],
      ),
    );
  }

  Widget _buildSongsTab() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final items = _filteredItems;

    if (items.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.music_off, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('No music found', style: TextStyle(fontSize: 18)),
            Text('Add some music to get started', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return MediaItemCard(
          mediaItem: item,
          onTap: () => AudioService.play(item),
          onDownload: () => _downloadItem(item),
          onMore: () => _showSongMenu(item),
        );
      },
    );
  }

  Widget _buildArtistsTab() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final query = _query.trim().toLowerCase();
    final artists = query.isEmpty
        ? _artists
        : _artists.where((a) => a.toLowerCase().contains(query)).toList();

    if (artists.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_off, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('No artists found', style: TextStyle(fontSize: 18)),
          ],
        ),
      );
    }

    return ArtistAlbumGrid(
      items: artists,
      type: 'artist',
      onItemTap: (artist) => _showArtistSongs(artist),
    );
  }

  Widget _buildAlbumsTab() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final query = _query.trim().toLowerCase();
    final albums = query.isEmpty
        ? _albums
        : _albums.where((a) => a.toLowerCase().contains(query)).toList();
    final coverArt = query.isEmpty
        ? _albumCoverArt
        : Map<String, String?>.fromEntries(
            _albumCoverArt.entries.where((e) => albums.contains(e.key)),
          );

    if (albums.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.album, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('No albums found', style: TextStyle(fontSize: 18)),
          ],
        ),
      );
    }

    return ArtistAlbumGrid(
      items: albums,
      type: 'album',
      onItemTap: (album) => _showAlbumSongs(album),
      albumCoverArt: coverArt,
    );
  }

  void _showSongMenu(MediaItem item) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.play_arrow),
                title: const Text('Play'),
                onTap: () async {
                  Navigator.of(context).pop();
                  await AudioService.play(item);
                },
              ),
              ListTile(
                leading: const Icon(Icons.skip_next),
                title: const Text('Play next'),
                onTap: () {
                  Navigator.of(context).pop();
                  AudioService.playNext(item);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Added to play next')),
                    );
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.queue_music),
                title: const Text('Add to queue'),
                onTap: () {
                  Navigator.of(context).pop();
                  AudioService.addToQueue(item);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Added to queue')),
                    );
                  }
                },
              ),
              if (item.isDownloaded)
                ListTile(
                  leading: const Icon(Icons.delete),
                  title: const Text('Remove download'),
                  onTap: () async {
                    Navigator.of(context).pop();
                    await DownloadService.deleteDownloadedFile(item);
                    final updated = item.copyWith(
                      isDownloaded: false,
                      filePath: item.id,
                    );
                    await StorageService.updateMediaItem(updated);
                    if (!mounted) return;
                    await _loadData();
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  void _downloadItem(MediaItem item) {
  }

  void _showArtistSongs(String artist) {
  }

  void _showAlbumSongs(String album) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AlbumSongsScreen(album: album),
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
}
