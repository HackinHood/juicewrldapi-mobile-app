import 'package:flutter/material.dart';
import 'package:music_library_app/services/master_server_service.dart';
import 'package:music_library_app/services/server_root_prefs.dart';

class _FolderNode {
  final String name;
  final String path;
  final Map<String, _FolderNode> children;
  _FolderNode(this.name, this.path, this.children);
}

_FolderNode _buildTree(List<String> filePaths) {
  final root = _FolderNode('', '', {});
  for (final raw in filePaths) {
    final p = raw.trim();
    if (p.isEmpty) continue;
    final parts = p.split('/');
    if (parts.isEmpty) continue;
    _FolderNode current = root;
    String acc = '';
    for (int i = 0; i < parts.length - 1; i++) {
      final part = parts[i].trim();
      if (part.isEmpty) continue;
      acc = acc.isEmpty ? part : '$acc/$part';
      final existing = current.children[part];
      if (existing != null) {
        current = existing;
      } else {
        final node = _FolderNode(part, acc, {});
        current.children[part] = node;
        current = node;
      }
    }
  }
  return root;
}

enum _Tri { off, on, mixed }

class ServerFolderTreeScreen extends StatefulWidget {
  const ServerFolderTreeScreen({super.key});

  @override
  State<ServerFolderTreeScreen> createState() => _ServerFolderTreeScreenState();
}

class _ServerFolderTreeScreenState extends State<ServerFolderTreeScreen> {
  bool _loading = true;
  _FolderNode? _tree;
  Set<String>? _include;
  Set<String> _exclude = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
    });
    final include = await ServerRootPrefs.getIncludedPrefixes();
    final exclude = await ServerRootPrefs.getExcludedPrefixes();
    final paths = await MasterServerService.fetchAllFilePaths();
    final tree = _buildTree(paths);
    if (!mounted) return;
    setState(() {
      _include = include;
      _exclude = exclude;
      _tree = tree;
      _loading = false;
    });
  }

  bool _isExcluded(String folderPath) {
    for (final ex in _exclude) {
      if (ex == folderPath) return true;
      if (folderPath.startsWith('$ex/')) return true;
    }
    return false;
  }

  bool _isIncludedByAncestor(String folderPath) {
    final inc = _include;
    if (inc == null) return true;
    for (final p in inc) {
      if (p == folderPath) return true;
      if (folderPath.startsWith('$p/')) return true;
    }
    return false;
  }

  _Tri _stateForNode(_FolderNode node) {
    if (node.path.isEmpty) return _Tri.mixed;
    if (_isExcluded(node.path)) return _Tri.off;
    final inc = _include;
    if (inc == null) {
      bool anyExcluded = false;
      for (final child in node.children.values) {
        final s = _stateForNode(child);
        if (s != _Tri.on) {
          anyExcluded = true;
          break;
        }
      }
      return anyExcluded ? _Tri.mixed : _Tri.on;
    }
    final selfIncluded = _isIncludedByAncestor(node.path);
    if (selfIncluded) {
      bool anyMixed = false;
      for (final child in node.children.values) {
        final s = _stateForNode(child);
        if (s != _Tri.on) {
          anyMixed = true;
          break;
        }
      }
      return anyMixed ? _Tri.mixed : _Tri.on;
    }
    bool anyOn = false;
    bool anyOff = false;
    for (final child in node.children.values) {
      final s = _stateForNode(child);
      if (s == _Tri.on || s == _Tri.mixed) anyOn = true;
      if (s == _Tri.off || s == _Tri.mixed) anyOff = true;
    }
    if (anyOn && anyOff) return _Tri.mixed;
    return anyOn ? _Tri.mixed : _Tri.off;
  }

  void _removeExcludedUnder(String folderPath) {
    _exclude.removeWhere((e) => e == folderPath || e.startsWith('$folderPath/'));
  }

  void _removeIncludedUnder(String folderPath) {
    final inc = _include;
    if (inc == null) return;
    inc.removeWhere((e) => e == folderPath || e.startsWith('$folderPath/'));
  }

  void _toggleNode(_FolderNode node) {
    if (node.path.isEmpty) return;
    final tri = _stateForNode(node);
    setState(() {
      if (tri == _Tri.on) {
        final inc = _include;
        if (inc == null) {
          _exclude.add(node.path);
        } else {
          _removeIncludedUnder(node.path);
        }
      } else {
        _removeExcludedUnder(node.path);
        final inc = _include;
        if (inc != null) {
          inc.add(node.path);
        }
      }
    });
  }

  void _selectAll() {
    setState(() {
      _include = null;
      _exclude = {};
    });
  }

  Future<void> _save() async {
    final include = _include;
    final resolvedInclude = include?.toSet();
    if (resolvedInclude != null && resolvedInclude.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one folder')),
      );
      return;
    }
    await ServerRootPrefs.setFolderRules(
      includedPrefixes: resolvedInclude,
      excludedPrefixes: _exclude.toSet(),
    );
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Widget _buildNodeTile(_FolderNode node) {
    final tri = _stateForNode(node);
    final checked = tri == _Tri.on ? true : tri == _Tri.off ? false : null;
    final children = node.children.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    if (children.isEmpty) {
      return CheckboxListTile(
        value: checked,
        tristate: true,
        onChanged: (_) => _toggleNode(node),
        title: Text(node.name),
        controlAffinity: ListTileControlAffinity.leading,
      );
    }

    return ExpansionTile(
      key: PageStorageKey(node.path),
      leading: Checkbox(
        value: checked,
        tristate: true,
        onChanged: (_) => _toggleNode(node),
      ),
      title: Text(node.name),
      children: [
        for (final child in children) _buildNodeTile(child),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tree = _tree;
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
          : tree == null
              ? const Center(child: Text('No folders found'))
              : ListView(
                  children: [
                    for (final child in (tree.children.values.toList()
                      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()))))
                      _buildNodeTile(child),
                  ],
                ),
    );
  }
}


