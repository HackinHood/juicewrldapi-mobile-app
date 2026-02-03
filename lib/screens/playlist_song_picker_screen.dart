import 'package:flutter/material.dart';
import 'package:music_library_app/models/media_item.dart';
import 'package:music_library_app/services/storage_service.dart';
import 'package:music_library_app/utils/restricted.dart';

class PlaylistSongPickerScreen extends StatefulWidget {
  final Set<String> initiallySelectedIds;
  const PlaylistSongPickerScreen({super.key, required this.initiallySelectedIds});

  @override
  State<PlaylistSongPickerScreen> createState() => _PlaylistSongPickerScreenState();
}

class _PlaylistSongPickerScreenState extends State<PlaylistSongPickerScreen> {
  bool _loading = true;
  List<MediaItem> _songs = [];
  Set<String> _selected = {};
  String _query = '';

  @override
  void initState() {
    super.initState();
    _selected = widget.initiallySelectedIds.toSet();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
    });
    final all = await StorageService.getAllMediaItems();
    final songs = all
        .where((m) => m.isDownloaded && !isRestrictedMediaItem(m))
        .toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    if (!mounted) return;
    setState(() {
      _songs = songs;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final visible = q.isEmpty
        ? _songs
        : _songs
            .where((m) =>
                m.title.toLowerCase().contains(q) ||
                m.artist.toLowerCase().contains(q) ||
                m.album.toLowerCase().contains(q))
            .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add songs'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(_selected.toList()),
            child: const Text('Done'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search songs',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      final item = visible[index];
                      final checked = _selected.contains(item.id);
                      return CheckboxListTile(
                        value: checked,
                        onChanged: (_) {
                          setState(() {
                            if (checked) {
                              _selected.remove(item.id);
                            } else {
                              _selected.add(item.id);
                            }
                          });
                        },
                        title: Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          item.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}


