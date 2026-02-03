import 'package:flutter/material.dart';
import 'package:music_library_app/models/media_item.dart';
import 'package:music_library_app/services/audio_service.dart';
import 'package:music_library_app/services/download_service.dart';
import 'package:music_library_app/services/storage_service.dart';
import 'package:music_library_app/screens/queue_screen.dart';
import 'package:music_library_app/utils/restricted.dart';
import 'package:music_library_app/widgets/media_item_card.dart';

class AlbumSongsScreen extends StatefulWidget {
  final String album;
  const AlbumSongsScreen({super.key, required this.album});

  @override
  State<AlbumSongsScreen> createState() => _AlbumSongsScreenState();
}

class _AlbumSongsScreenState extends State<AlbumSongsScreen> {
  bool _loading = true;
  List<MediaItem> _songs = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool _isServerPath(String path) {
    final lower = path.toLowerCase();
    if (lower.startsWith('/audio/')) return true;
    if (lower.startsWith('audio/')) return true;
    if (lower.startsWith('/studio_sessions/') || lower.startsWith('/studio-sessions/')) return true;
    if (lower.startsWith('studio_sessions/') || lower.startsWith('studio-sessions/')) return true;
    return false;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
    });
    try {
      final items = await StorageService.getMediaItemsByAlbum(widget.album);
      if (!mounted) return;
      final filtered = items.where((m) {
        return m.isDownloaded && !_isServerPath(m.filePath) && !isRestrictedMediaItem(m);
      }).toList();
      setState(() {
        _songs = filtered;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _playFromList(int index) async {
    try {
      await AudioService.playPlaylist(_songs, index);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to play: ${e.toString()}')),
      );
    }
  }

  Future<void> _playAlbum({required bool shuffle}) async {
    if (_songs.isEmpty) return;
    try {
      await AudioService.playQueue(_songs, shuffle: shuffle);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to play: ${e.toString()}')),
      );
    }
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
                    await _load();
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.album),
        actions: [
          IconButton(
            icon: const Icon(Icons.play_arrow),
            onPressed: _loading ? null : () => _playAlbum(shuffle: false),
          ),
          IconButton(
            icon: const Icon(Icons.shuffle),
            onPressed: _loading ? null : () => _playAlbum(shuffle: true),
          ),
          IconButton(
            icon: const Icon(Icons.queue_music),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const QueueScreen()),
              );
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _songs.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.music_off, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text('No songs found', style: TextStyle(fontSize: 18)),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _songs.length,
                  itemBuilder: (context, index) {
                    final item = _songs[index];
                    return MediaItemCard(
                      mediaItem: item,
                      onTap: () => _playFromList(index),
                      onMore: () => _showSongMenu(item),
                    );
                  },
                ),
    );
  }
}


