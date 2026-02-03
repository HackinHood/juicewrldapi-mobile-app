import 'package:flutter/material.dart';
import 'package:music_library_app/models/playlist.dart';
import 'package:music_library_app/screens/playlist_detail_screen.dart';
import 'package:music_library_app/services/storage_service.dart';
import 'package:music_library_app/widgets/playlist_card.dart';
import 'package:music_library_app/widgets/playlist_editor_dialog.dart';

class PlaylistsScreen extends StatefulWidget {
  const PlaylistsScreen({super.key});

  @override
  State<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends State<PlaylistsScreen> {
  List<Playlist> _playlists = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPlaylists();
  }

  Future<void> _loadPlaylists() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final playlists = await StorageService.getAllPlaylists();
      setState(() {
        _playlists = playlists;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Playlists'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _createPlaylist,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadPlaylists,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _playlists.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.playlist_add, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text('No playlists found', style: TextStyle(fontSize: 18)),
                      Text('Create your first playlist', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.8,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: _playlists.length,
                  itemBuilder: (context, index) {
                    final playlist = _playlists[index];
                    return PlaylistCard(
                      playlist: playlist,
                      onTap: () => _openPlaylist(playlist),
                      onEdit: () => _editPlaylist(playlist),
                      onDelete: () => _deletePlaylist(playlist),
                    );
                  },
                ),
    );
  }

  void _createPlaylist() {
    showPlaylistEditorDialog(context).then((playlist) async {
      if (playlist == null) return;
      await StorageService.insertPlaylist(playlist);
      if (!mounted) return;
      setState(() {
        _playlists.insert(0, playlist);
      });
    });
  }

  void _openPlaylist(Playlist playlist) {
    Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PlaylistDetailScreen(playlistId: playlist.id),
      ),
    ).then((changed) {
      if (changed == true) {
        _loadPlaylists();
      }
    });
  }

  void _editPlaylist(Playlist playlist) {
    showPlaylistEditorDialog(context, playlist: playlist).then((updated) async {
      if (updated == null) return;
      await StorageService.updatePlaylist(updated);
      if (!mounted) return;
      setState(() {
        final index = _playlists.indexWhere((p) => p.id == playlist.id);
        if (index != -1) {
          _playlists[index] = updated;
        }
      });
    });
  }

  void _deletePlaylist(Playlist playlist) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Playlist'),
        content: Text('Are you sure you want to delete "${playlist.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              StorageService.deletePlaylist(playlist.id);
              setState(() {
                _playlists.removeWhere((p) => p.id == playlist.id);
              });
              Navigator.pop(context);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
