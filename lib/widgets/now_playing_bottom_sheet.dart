import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:music_library_app/services/audio_service.dart';
import 'package:music_library_app/services/storage_service.dart';
import 'package:music_library_app/screens/queue_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

class NowPlayingBottomSheet extends StatefulWidget {
  const NowPlayingBottomSheet({super.key});

  @override
  State<NowPlayingBottomSheet> createState() => _NowPlayingBottomSheetState();
}

class _NowPlayingBottomSheetState extends State<NowPlayingBottomSheet> {
  Set<String> _favorites = {};
  bool _isFavorite = false;
  StreamSubscription? _nowPlayingSubscription;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
    _nowPlayingSubscription = AudioService.nowPlayingStream.listen((_) {
      if (!mounted) return;
      setState(() {
        _setFavoriteForCurrent(AudioService.currentItem);
      });
    });
  }

  Future<void> _loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final favoriteIds = prefs.getStringList('favorites') ?? [];
    setState(() {
      _favorites = favoriteIds.toSet();
      _setFavoriteForCurrent(AudioService.currentItem);
    });
  }

  void _setFavoriteForCurrent(currentItem) {
    final id = currentItem?.id as String?;
    _isFavorite = id != null && _favorites.contains(id);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    setState(() {
      _setFavoriteForCurrent(AudioService.currentItem);
    });
  }

  Future<void> _toggleFavorite() async {
    final currentItem = AudioService.currentItem;
    if (currentItem == null) return;

    final prefs = await SharedPreferences.getInstance();
    final favoriteIds = prefs.getStringList('favorites') ?? [];
    final favoritesSet = favoriteIds.toSet();

    if (_isFavorite) {
      favoritesSet.remove(currentItem.id);
    } else {
      favoritesSet.add(currentItem.id);
    }

    await prefs.setStringList('favorites', favoritesSet.toList());
    setState(() {
      _favorites = favoritesSet;
      _isFavorite = favoritesSet.contains(currentItem.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          _buildHandle(),
          _buildNowPlayingContent(),
        ],
      ),
    );
  }

  Widget _buildHandle() {
    final theme = Theme.of(context);
    return Container(
      width: 40,
      height: 4,
      margin: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withOpacity(0.3),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _buildNowPlayingContent() {
    return StreamBuilder(
      stream: AudioService.nowPlayingStream,
      initialData: AudioService.currentItem,
      builder: (context, snapshot) {
        final currentItem = snapshot.data;
        if (currentItem == null) {
          final theme = Theme.of(context);
          return Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.music_off, size: 64, color: theme.colorScheme.onSurface.withOpacity(0.5)),
                  const SizedBox(height: 16),
                  Text('No music playing', style: TextStyle(fontSize: 18, color: theme.colorScheme.onSurface)),
                ],
              ),
            ),
          );
        }

        return Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildCoverArt(currentItem),
                const SizedBox(height: 24),
                _buildTrackInfo(currentItem),
                const SizedBox(height: 32),
                _buildProgressBar(),
                const SizedBox(height: 24),
                _buildControls(),
                const SizedBox(height: 24),
                _buildAdditionalControls(),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _nowPlayingSubscription?.cancel();
    super.dispose();
  }

  Widget _buildCoverArt(mediaItem) {
    final theme = Theme.of(context);
    String? localArtPath;
    try {
      localArtPath = mediaItem.coverArtPath as String?;
    } catch (_) {
      localArtPath = null;
    }

    if (localArtPath != null && localArtPath.isNotEmpty) {
      final file = File(localArtPath);
      if (file.existsSync()) {
        return Container(
          width: 200,
          height: 200,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              file,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => _buildDefaultIcon(),
            ),
          ),
        );
      }
    }

    final coverUrl = _buildCoverUrl(mediaItem);
    return Container(
      width: 200,
      height: 200,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: coverUrl != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedNetworkImage(
                imageUrl: coverUrl,
                fit: BoxFit.cover,
                errorWidget: (context, url, error) => _buildDefaultIcon(),
                placeholder: (context, url) => _buildDefaultIcon(),
              ),
            )
          : _buildDefaultIcon(),
    );
  }

  Widget _buildDefaultIcon() {
    final theme = Theme.of(context);
    return Icon(
      Icons.music_note,
      size: 64,
      color: theme.colorScheme.onSurface.withOpacity(0.5),
    );
  }

  String? _buildCoverUrl(mediaItem) {
    final cloudId = mediaItem.cloudId as String?;
    if (cloudId != null && cloudId.isNotEmpty) {
      final encoded = Uri.encodeComponent(cloudId);
      return 'https://m.juicewrldapi.com/album-art?filepath=$encoded';
    }

    final path = mediaItem.filePath as String? ?? '';
    final lower = path.toLowerCase();
    final isServerPath = lower.startsWith('audio/') ||
        lower.startsWith('studio_sessions/') ||
        lower.startsWith('studio-sessions/');
    if (!isServerPath) return null;

    final encodedPath = Uri.encodeComponent(path);
    return 'https://m.juicewrldapi.com/album-art?filepath=$encodedPath';
  }

  Widget _buildTrackInfo(mediaItem) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          mediaItem.title,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          mediaItem.artist,
          style: TextStyle(
            fontSize: 18,
            color: theme.colorScheme.onSurface.withOpacity(0.7),
          ),
          textAlign: TextAlign.center,
        ),
        if (mediaItem.album.isNotEmpty)
          Text(
            mediaItem.album,
            style: TextStyle(
              fontSize: 16,
              color: theme.colorScheme.onSurface.withOpacity(0.6),
            ),
            textAlign: TextAlign.center,
          ),
      ],
    );
  }

  Widget _buildProgressBar() {
    final theme = Theme.of(context);
    return StreamBuilder<Duration>(
      stream: AudioService.positionStream,
      builder: (context, snapshot) {
        final rawPosition = snapshot.data ?? Duration.zero;
        final rawDuration = AudioService.duration;

        int totalMs = rawDuration.inMilliseconds;
        if (totalMs < 0) totalMs = 0;
        final safeMaxMs = totalMs > 0 ? totalMs : 1;

        int positionMs = rawPosition.inMilliseconds;
        if (positionMs < 0) positionMs = 0;
        final clampedPositionMs = positionMs.clamp(0, safeMaxMs);

        final sliderValue = clampedPositionMs.toDouble();
        final sliderMax = safeMaxMs.toDouble();

        final finalValue = (sliderValue.isNaN || sliderValue.isInfinite || sliderValue < 0) ? 0.0 : sliderValue.clamp(0.0, sliderMax);
        final finalMax = (sliderMax.isNaN || sliderMax.isInfinite || sliderMax <= 0) ? 1.0 : sliderMax;

        return Column(
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: theme.colorScheme.primary,
                inactiveTrackColor: theme.colorScheme.onSurface.withOpacity(0.2),
                thumbColor: theme.colorScheme.primary,
                overlayColor: theme.colorScheme.primary.withOpacity(0.2),
              ),
              child: Slider(
                value: finalValue,
                max: finalMax,
                onChanged: (value) {
                  if (value.isNaN || value.isInfinite) return;
                  AudioService.seek(Duration(milliseconds: value.toInt()));
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatDuration(Duration(milliseconds: clampedPositionMs)),
                    style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.7)),
                  ),
                  Text(
                    _formatDuration(rawDuration),
                    style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.7)),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildControls() {
    final theme = Theme.of(context);
    final playlist = AudioService.currentPlaylist;
    final currentIndex = AudioService.currentIndex;
    final hasPrevious = playlist.isNotEmpty && currentIndex > 0;
    final hasNext = playlist.isNotEmpty && currentIndex < playlist.length - 1;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          icon: const Icon(Icons.skip_previous),
          iconSize: 32,
          color: hasPrevious ? theme.colorScheme.onSurface : theme.colorScheme.onSurface.withOpacity(0.3),
          onPressed: hasPrevious ? AudioService.previous : null,
        ),
        StreamBuilder<bool>(
          stream: AudioService.playerStateStream.map((state) => state.playing),
          builder: (context, snapshot) {
            final isPlaying = snapshot.data ?? false;
            return IconButton(
              icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
              iconSize: 48,
              color: theme.colorScheme.primary,
              onPressed: isPlaying ? AudioService.pause : AudioService.resume,
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.skip_next),
          iconSize: 32,
          color: hasNext ? theme.colorScheme.onSurface : theme.colorScheme.onSurface.withOpacity(0.3),
          onPressed: hasNext ? AudioService.next : null,
        ),
      ],
    );
  }

  Widget _buildAdditionalControls() {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        StreamBuilder<String>(
          stream: AudioService.repeatModeStream,
          builder: (context, snapshot) {
            final repeatMode = snapshot.data ?? 'off';
            IconData icon;
            Color? color;
            switch (repeatMode) {
              case 'one':
                icon = Icons.repeat_one;
                color = theme.colorScheme.primary;
                break;
              case 'all':
                icon = Icons.repeat;
                color = theme.colorScheme.primary;
                break;
              default:
                icon = Icons.repeat;
                color = theme.colorScheme.onSurface.withOpacity(0.7);
            }
            return IconButton(
              icon: Icon(icon),
              color: color,
              onPressed: AudioService.toggleRepeat,
            );
          },
        ),
        StreamBuilder<bool>(
          stream: AudioService.shuffleStream,
          builder: (context, snapshot) {
            final isShuffled = snapshot.data ?? false;
            return IconButton(
              icon: const Icon(Icons.shuffle),
              color: isShuffled ? theme.colorScheme.primary : theme.colorScheme.onSurface.withOpacity(0.7),
              onPressed: AudioService.toggleShuffle,
            );
          },
        ),
        IconButton(
          icon: Icon(_isFavorite ? Icons.favorite : Icons.favorite_border),
          color: _isFavorite ? Colors.red : theme.colorScheme.onSurface.withOpacity(0.7),
          onPressed: _toggleFavorite,
        ),
        IconButton(
          icon: const Icon(Icons.queue_music),
          color: theme.colorScheme.onSurface.withOpacity(0.7),
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const QueueScreen()),
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.more_vert),
          color: theme.colorScheme.onSurface.withOpacity(0.7),
          onPressed: () => _showMoreOptions(context),
        ),
      ],
    );
  }

  void _showMoreOptions(BuildContext context) {
    final currentItem = AudioService.currentItem;
    if (currentItem == null) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Track Info'),
              onTap: () {
                Navigator.pop(context);
                _showTrackInfo(context, currentItem);
              },
            ),
            if (currentItem.isDownloaded)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Remove Download'),
                onTap: () {
                  Navigator.pop(context);
                  _removeDownload(context, currentItem);
                },
              ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Close'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  void _showTrackInfo(BuildContext context, currentItem) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text('Track Info', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow('Title', currentItem.title),
            _buildInfoRow('Artist', currentItem.artist),
            if (currentItem.album.isNotEmpty) _buildInfoRow('Album', currentItem.album),
            if (currentItem.genre != null) _buildInfoRow('Genre', currentItem.genre!),
            if (currentItem.year != null) _buildInfoRow('Year', currentItem.year.toString()),
            _buildInfoRow('Duration', _formatDuration(Duration(seconds: currentItem.duration))),
            _buildInfoRow('Play Count', currentItem.playCount.toString()),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: theme.colorScheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _removeDownload(BuildContext context, currentItem) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text('Remove Download', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
        content: Text(
          'Are you sure you want to remove this download?',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final file = File(currentItem.filePath);
        if (await file.exists()) {
          await file.delete();
        }

        final updatedItem = currentItem.copyWith(
          filePath: currentItem.cloudId ?? currentItem.id,
          isDownloaded: false,
        );
        await StorageService.updateMediaItem(updatedItem);

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Download removed')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error removing download: $e')),
          );
        }
      }
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final safeDuration = duration.isNegative ? Duration.zero : duration;
    final totalSeconds = safeDuration.inSeconds;
    final minutes = twoDigits((totalSeconds ~/ 60).clamp(0, 99));
    final seconds = twoDigits((totalSeconds % 60).clamp(0, 59));
    return '$minutes:$seconds';
  }
}
