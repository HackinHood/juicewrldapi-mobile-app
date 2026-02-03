import 'package:flutter/material.dart';
import 'package:music_library_app/models/playlist.dart';

Future<Playlist?> showPlaylistEditorDialog(
  BuildContext context, {
  Playlist? playlist,
}) {
  return showDialog<Playlist?>(
    context: context,
    builder: (context) => _PlaylistEditorDialog(playlist: playlist),
  );
}

class _PlaylistEditorDialog extends StatefulWidget {
  final Playlist? playlist;
  const _PlaylistEditorDialog({this.playlist});

  @override
  State<_PlaylistEditorDialog> createState() => _PlaylistEditorDialogState();
}

class _PlaylistEditorDialogState extends State<_PlaylistEditorDialog> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final p = widget.playlist;
    if (p != null) {
      _nameController.text = p.name;
      _descriptionController.text = p.description ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.playlist == null ? 'Create Playlist' : 'Edit Playlist'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _descriptionController,
            decoration: const InputDecoration(
              labelText: 'Description',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            final name = _nameController.text.trim();
            if (name.isEmpty) return;
            final desc = _descriptionController.text.trim();
            final now = DateTime.now();
            final next = widget.playlist?.copyWith(
                  name: name,
                  description: desc.isEmpty ? null : desc,
                  lastModified: now,
                ) ??
                Playlist(
                  id: now.millisecondsSinceEpoch.toString(),
                  name: name,
                  description: desc.isEmpty ? null : desc,
                  dateCreated: now,
                  lastModified: now,
                );
            Navigator.of(context).pop(next);
          },
          child: Text(widget.playlist == null ? 'Create' : 'Save'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }
}


