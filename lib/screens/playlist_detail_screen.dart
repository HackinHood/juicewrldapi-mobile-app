import 'package:flutter/material.dart';
import 'package:music_library_app/models/media_item.dart';
import 'package:music_library_app/models/playlist.dart';
import 'package:music_library_app/screens/playlist_song_picker_screen.dart';
import 'package:music_library_app/services/audio_service.dart';
import 'package:music_library_app/services/storage_service.dart';
import 'package:music_library_app/widgets/media_item_card.dart';
import 'package:music_library_app/widgets/playlist_editor_dialog.dart';

class PlaylistDetailScreen extends StatefulWidget {
  final String playlistId;
  const PlaylistDetailScreen({super.key, required this.playlistId});

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  bool _loading = true;
  Playlist? _playlist;
  List<MediaItem> _songs = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
    });
    final playlist = await StorageService.getPlaylist(widget.playlistId);
    if (playlist == null) {
      if (!mounted) return;
      setState(() {
        _playlist = null;
        _songs = [];
        _loading = false;
      });
      return;
    }
    final songs = await StorageService.getMediaItemsByIds(playlist.mediaItemIds);
    if (!mounted) return;
    setState(() {
      _playlist = playlist;
      _songs = songs;
      _loading = false;
    });
  }

  Future<void> _savePlaylist(Playlist updated) async {
    await StorageService.updatePlaylist(updated);
    if (!mounted) return;
    setState(() {
      _playlist = updated;
    });
  }

  Future<String?> _coverFromFirstSong(List<String> ids) async {
    if (ids.isEmpty) return null;
    final items = await StorageService.getMediaItemsByIds([ids.first]);
    if (items.isEmpty) return null;
    final art = items.first.coverArtPath;
    if (art == null || art.isEmpty) return null;
    return art;
  }

  Future<void> _edit() async {
    final p = _playlist;
    if (p == null) return;
    final updated = await showPlaylistEditorDialog(context, playlist: p);
    if (updated == null) return;
    await _savePlaylist(updated);
  }

  Future<void> _delete() async {
    final p = _playlist;
    if (p == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete playlist'),
        content: Text('Delete "${p.name}"?'),
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
    await StorageService.deletePlaylist(p.id);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _addSongs() async {
    final p = _playlist;
    if (p == null) return;
    final selected = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (_) => PlaylistSongPickerScreen(
          initiallySelectedIds: p.mediaItemIds.toSet(),
        ),
      ),
    );
    if (selected == null) return;
    final cover = await _coverFromFirstSong(selected);
    final updated = p.copyWith(
      mediaItemIds: selected,
      coverArtPath: cover,
      lastModified: DateTime.now(),
    );
    await _savePlaylist(updated);
    await _load();
  }

  Future<void> _play({required bool shuffle}) async {
    if (_songs.isEmpty) return;
    await AudioService.playQueue(_songs, shuffle: shuffle);
  }

  Future<void> _playFromIndex(int index) async {
    if (index < 0 || index >= _songs.length) return;
    await AudioService.playPlaylist(_songs, index);
  }

  Future<void> _removeSong(int index) async {
    final p = _playlist;
    if (p == null) return;
    if (index < 0 || index >= p.mediaItemIds.length) return;
    final ids = p.mediaItemIds.toList();
    ids.removeAt(index);
    final cover = await _coverFromFirstSong(ids);
    final updated = p.copyWith(
      mediaItemIds: ids,
      coverArtPath: cover,
      lastModified: DateTime.now(),
    );
    await _savePlaylist(updated);
    await _load();
  }

  void _showSongMenu(MediaItem item, int index) {
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
              ListTile(
                leading: const Icon(Icons.playlist_remove),
                title: const Text('Remove from playlist'),
                onTap: () async {
                  Navigator.of(context).pop();
                  await _removeSong(index);
                  if (!mounted) return;
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    const SnackBar(content: Text('Removed from playlist')),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    final p = _playlist;
    if (p == null) return;
    final ids = p.mediaItemIds.toList();
    if (oldIndex < 0 || oldIndex >= ids.length) return;
    if (newIndex < 0 || newIndex > ids.length) return;
    if (oldIndex < newIndex) newIndex -= 1;
    final moved = ids.removeAt(oldIndex);
    ids.insert(newIndex, moved);
    final cover = await _coverFromFirstSong(ids);
    final updated = p.copyWith(
      mediaItemIds: ids,
      coverArtPath: cover,
      lastModified: DateTime.now(),
    );
    await _savePlaylist(updated);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final p = _playlist;
    return Scaffold(
      appBar: AppBar(
        title: Text(p?.name ?? 'Playlist'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _loading ? null : _addSongs,
          ),
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: _loading || p == null ? null : _edit,
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: _loading || p == null ? null : _delete,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : p == null
              ? const Center(child: Text('Playlist not found'))
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _songs.isEmpty ? null : () => _play(shuffle: false),
                              icon: const Icon(Icons.play_arrow),
                              label: const Text('Play'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _songs.isEmpty ? null : () => _play(shuffle: true),
                              icon: const Icon(Icons.shuffle),
                              label: const Text('Shuffle'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _songs.isEmpty
                          ? const Center(child: Text('No songs in this playlist'))
                          : ReorderableListView.builder(
                              onReorder: (oldIndex, newIndex) => _reorder(oldIndex, newIndex),
                              itemCount: _songs.length,
                              itemBuilder: (context, index) {
                                final item = _songs[index];
                                return Dismissible(
                                  key: ValueKey('${p.id}:${item.id}'),
                                  direction: DismissDirection.endToStart,
                                  background: Container(
                                    color: Colors.red,
                                    alignment: Alignment.centerRight,
                                    padding: const EdgeInsets.only(right: 16),
                                    child: const Icon(Icons.delete, color: Colors.white),
                                  ),
                                  confirmDismiss: (_) async => true,
                                  onDismissed: (_) => _removeSong(index),
                                  child: MediaItemCard(
                                    mediaItem: item,
                                    onTap: () => _playFromIndex(index),
                                    onMore: () => _showSongMenu(item, index),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
    );
  }
}


