import 'package:flutter/material.dart';
import 'package:music_library_app/services/master_server_service.dart';
import 'package:music_library_app/services/server_root_prefs.dart';

class ServerRootsScreen extends StatefulWidget {
  const ServerRootsScreen({super.key});

  @override
  State<ServerRootsScreen> createState() => _ServerRootsScreenState();
}

class _ServerRootsScreenState extends State<ServerRootsScreen> {
  bool _loading = true;
  List<String> _available = [];
  Set<String>? _selected;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
    });
    final selected = await ServerRootPrefs.getSelectedRoots();
    final available = await MasterServerService.fetchRootFolders();
    if (!mounted) return;
    setState(() {
      _selected = selected;
      _available = available;
      _loading = false;
    });
  }

  bool _isSelected(String root) {
    final s = _selected;
    if (s == null) return true;
    return s.contains(root);
  }

  void _toggleRoot(String root) {
    setState(() {
      final s = _selected;
      if (s == null) {
        _selected = _available.toSet();
      }
      final next = _selected ?? <String>{};
      if (next.contains(root)) {
        next.remove(root);
      } else {
        next.add(root);
      }
      _selected = next;
    });
  }

  void _selectAll() {
    setState(() {
      _selected = null;
    });
  }

  Future<void> _save() async {
    final selection = _selected;
    final resolved = selection == null ? null : selection.toSet();
    if (resolved != null && resolved.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one folder')),
      );
      return;
    }
    await ServerRootPrefs.setSelectedRoots(resolved);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    final subtitle = selected == null ? 'All folders' : '${selected.length} selected';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Server folders'),
        actions: [
          TextButton(
            onPressed: _loading ? null : _selectAll,
            child: const Text('All'),
          ),
          TextButton(
            onPressed: _loading ? null : _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _available.isEmpty
              ? const Center(
                  child: Text('No folders found'),
                )
              : ListView(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.folder),
                      title: const Text('Sync selection'),
                      subtitle: Text(subtitle),
                    ),
                    const Divider(height: 1),
                    for (final root in _available)
                      CheckboxListTile(
                        value: _isSelected(root),
                        onChanged: (_) => _toggleRoot(root),
                        title: Text(root),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                  ],
                ),
    );
  }
}


