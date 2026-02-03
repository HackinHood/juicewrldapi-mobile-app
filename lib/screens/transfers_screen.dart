import 'dart:async';

import 'package:flutter/material.dart';
import 'package:music_library_app/models/media_item.dart';
import 'package:music_library_app/services/download_service.dart';
import 'package:music_library_app/services/storage_service.dart';
import 'package:music_library_app/utils/restricted.dart';

class TransfersScreen extends StatefulWidget {
  const TransfersScreen({super.key});

  @override
  State<TransfersScreen> createState() => _TransfersScreenState();
}

class _TransfersScreenState extends State<TransfersScreen> {
  bool _loading = true;
  List<MediaItem> _items = [];
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _loadTransfers();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadTransfers() async {
    setState(() {
      _loading = true;
    });

    final all = await StorageService.getAllMediaItems();

    final transfers = all
        .where((m) => !isRestrictedMediaItem(m))
        .where((m) {
          final isDownloading = DownloadService.isDownloading(m.id);
          return isDownloading || m.isDownloaded;
        })
        .toList()
      ..sort((a, b) {
        final aDownloading = DownloadService.isDownloading(a.id);
        final bDownloading = DownloadService.isDownloading(b.id);
        if (aDownloading && !bDownloading) return -1;
        if (!aDownloading && bDownloading) return 1;
        return b.dateAdded.compareTo(a.dateAdded);
      });

    if (!mounted) return;

    setState(() {
      _items = transfers;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transfers'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _loadTransfers,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadTransfers,
              child: _buildList(),
            ),
    );
  }

  Widget _buildList() {
    if (_items.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.downloading, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('No transfers yet', style: TextStyle(fontSize: 18)),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _items.length,
      itemBuilder: (context, index) {
        final item = _items[index];
        final isDownloading = DownloadService.isDownloading(item.id);
        final status = isDownloading
            ? 'Downloading'
            : item.isDownloaded
                ? 'Completed'
                : 'Pending';

        return ListTile(
          leading: Icon(
            isDownloading
                ? Icons.downloading
                : item.isDownloaded
                    ? Icons.download_done
                    : Icons.download,
          ),
          title: Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${item.artist} • $status',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: isDownloading
              ? IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    DownloadService.cancelDownload(item.id);
                  },
                )
              : null,
        );
      },
    );
  }
}


