import 'package:flutter/material.dart';
import 'package:music_library_app/models/media_item.dart';
import 'package:music_library_app/services/audio_service.dart';
import 'package:music_library_app/services/storage_service.dart';
import 'package:music_library_app/utils/restricted.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  bool _loading = true;
  List<MediaItem> _items = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _loading = true;
    });

    final all = await StorageService.getAllMediaItems();
    final history = all
        .where((m) => !isRestrictedMediaItem(m))
        .where((m) => m.lastPlayed != null && m.isDownloaded)
        .toList()
      ..sort((a, b) => b.lastPlayed!.compareTo(a.lastPlayed!));

    if (!mounted) return;

    setState(() {
      _items = history;
      _loading = false;
    });
  }

  Future<void> _playItem(MediaItem item) async {
    try {
      await AudioService.play(item);
    } catch (e) {
      if (!mounted) return;
      final errorMsg = e.toString().replaceAll('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to play: $errorMsg'),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _loadHistory,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadHistory,
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
            Icon(Icons.history, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('No listening history yet', style: TextStyle(fontSize: 18)),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _items.length,
      itemBuilder: (context, index) {
        final item = _items[index];
        return ListTile(
          leading: const Icon(Icons.music_note),
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
          trailing: item.lastPlayed != null
              ? Text(
                  _formatTimestamp(item.lastPlayed!),
                  style: Theme.of(context).textTheme.bodySmall,
                )
              : null,
          onTap: () => _playItem(item),
        );
      },
    );
  }

  String _formatTimestamp(DateTime time) {
    final date = '${time.year.toString().padLeft(4, '0')}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}';
    final clock = '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    return '$date $clock';
  }
}


