import 'package:flutter/material.dart';
import 'package:music_library_app/models/media_item.dart';
import 'package:music_library_app/services/audio_service.dart';

class QueueScreen extends StatelessWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<MediaItem>>(
      stream: AudioService.queueStream,
      initialData: AudioService.currentQueue,
      builder: (context, queueSnapshot) {
        final queue = queueSnapshot.data ?? const <MediaItem>[];
        final nowPlaying = AudioService.currentItem;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Queue'),
            actions: [
              IconButton(
                icon: const Icon(Icons.delete_sweep),
                onPressed: queue.isEmpty
                    ? null
                    : () {
                        AudioService.clearQueue();
                        Navigator.of(context).pop();
                      },
              ),
            ],
          ),
          body: Column(
            children: [
              if (nowPlaying != null)
                ListTile(
                  leading: const Icon(Icons.play_arrow),
                  title: Text(
                    nowPlaying.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    nowPlaying.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (queue.isEmpty)
                const Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.queue_music, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text('Queue is empty', style: TextStyle(fontSize: 18)),
                      ],
                    ),
                  ),
                )
              else
                Expanded(
                  child: ReorderableListView.builder(
                    buildDefaultDragHandles: false,
                    onReorder: (oldIndex, newIndex) {
                      AudioService.reorderQueue(oldIndex, newIndex);
                    },
                    itemCount: queue.length,
                    itemBuilder: (context, index) {
                      final item = queue[index];
                      return ListTile(
                        key: ValueKey(item.id),
                        leading: ReorderableDragStartListener(
                          index: index,
                          child: const Icon(Icons.drag_handle),
                        ),
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
                        trailing: IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () async {
                            await AudioService.removeFromQueue(index);
                          },
                        ),
                        onTap: () async {
                          await AudioService.playFromQueue(index);
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}


