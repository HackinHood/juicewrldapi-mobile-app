import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:music_library_app/models/media_item.dart';
import 'package:music_library_app/services/download_service.dart';
import 'package:music_library_app/services/master_server_service.dart';
import 'package:music_library_app/services/storage_service.dart';
import 'package:music_library_app/services/server_root_prefs.dart';

class ServerFilesScreen extends StatefulWidget {
  final ValueListenable<int> currentIndexListenable;
  const ServerFilesScreen({super.key, required this.currentIndexListenable});

  @override
  State<ServerFilesScreen> createState() => _ServerFilesScreenState();
}

class _ServerFilesScreenState extends State<ServerFilesScreen> {
  bool _loading = true;
  bool _refreshing = false;
  List<MediaItem> _items = [];
  String _query = '';
  bool _hasLoadedOnce = false;
  late final VoidCallback _indexListener;

  @override
  void initState() {
    super.initState();
    _indexListener = () {
      if (_hasLoadedOnce) return;
      if (widget.currentIndexListenable.value == 1) {
        _hasLoadedOnce = true;
        _loadCached();
      }
    };
    widget.currentIndexListenable.addListener(_indexListener);
    _indexListener();
  }

  Future<void> _loadCached() async {
    setState(() {
      _loading = true;
    });

    try {
      final cached = await StorageService.getCachedServerItems();
      final included = await ServerRootPrefs.getIncludedPrefixes();
      final excluded = await ServerRootPrefs.getExcludedPrefixes();
      final filtered = (included == null && excluded.isEmpty)
          ? cached
          : cached.where((m) => ServerRootPrefs.isAllowedPath(m.id, included, excluded)).toList();
      if (!mounted) return;

      setState(() {
        _items = filtered;
        _loading = false;
      });

      if (filtered.isEmpty) {
        await _refreshFromServer(showErrors: true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
      await _refreshFromServer(showErrors: true);
    }
  }

  Future<void> _refreshFromServer({required bool showErrors}) async {
    if (mounted) {
      setState(() {
        _refreshing = true;
        if (_items.isEmpty) {
          _loading = true;
        }
      });
    }

    try {
      final serverItems = await MasterServerService.fetchServerFiles();

      if (!mounted) return;

      setState(() {
        _items = serverItems;
        _loading = false;
        _refreshing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _refreshing = false;
      });
      if (showErrors) {
        if (e is DioException && e.response?.statusCode == 401) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Unauthorized (401). Server rejected the request.')),
          );
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load server files: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    widget.currentIndexListenable.removeListener(_indexListener);
    super.dispose();
  }

  Future<void> _downloadItem(MediaItem item) async {
    final granted = await DownloadService.requestStoragePermission();
    if (!granted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Storage permission required for download')),
      );
      return;
    }

    try {
      await DownloadService.downloadMediaItem(
        item,
        onProgress: (received, total) {},
        onComplete: () {
          _refreshFromServer(showErrors: false);
        },
        onError: (error) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Download failed: $error')),
          );
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Download started')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download failed: $e')),
      );
    }
  }

  List<MediaItem> get _filteredItems {
    final query = _query.trim();
    if (query.isEmpty) {
      return _items;
    }
    final lowerQuery = query.toLowerCase();
    return _items.where((m) {
      return (m.title.isNotEmpty && m.title.toLowerCase().contains(lowerQuery)) ||
          (m.artist.isNotEmpty && m.artist.toLowerCase().contains(lowerQuery)) ||
          (m.album.isNotEmpty && m.album.toLowerCase().contains(lowerQuery));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Server Files'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshing ? null : () => _refreshFromServer(showErrors: true),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search server library',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              enabled: !_refreshing,
              onChanged: (value) {
                setState(() {
                  _query = value;
                });
              },
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _refreshFromServer(showErrors: false),
              child: _buildList(),
            ),
    );
  }

  Widget _buildList() {
    final items = _filteredItems;

    if (items.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('No server files available', style: TextStyle(fontSize: 18)),
            Text('Run a sync from Settings to import your library', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: items.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return _refreshing
              ? const LinearProgressIndicator(minHeight: 2)
              : const SizedBox(height: 2);
        }

        final item = items[index - 1];
        return ListTile(
          leading: const Icon(Icons.cloud_download),
          title: Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${item.artist} • ${item.album}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: IconButton(
            icon: const Icon(Icons.download),
            onPressed: () => _downloadItem(item),
          ),
        );
      },
    );
  }
}


