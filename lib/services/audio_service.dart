import 'dart:io';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:music_library_app/models/media_item.dart';
import 'package:music_library_app/services/now_playing_sync_service.dart';
import 'package:music_library_app/services/storage_service.dart';
import 'package:music_library_app/services/system_audio_handler.dart' show systemAudioHandler, SystemAudioHandler, initSystemAudioHandler;

class AudioService {
  static AudioPlayer? _audioPlayer;
  static MediaItem? _currentItem;
  static List<MediaItem> _playlist = [];
  static int _currentIndex = 0;
  static bool _supported = true;
  static String _repeatMode = 'off';
  static bool _shuffleEnabled = false;
  static List<MediaItem> _originalPlaylist = [];
  static final _queueController = StreamController<List<MediaItem>>.broadcast();
  static final _currentIndexController = StreamController<int>.broadcast();
  static final _nowPlayingController = StreamController<MediaItem?>.broadcast();
  static StreamSubscription<Duration>? _positionNowPlayingSub;
  static StreamSubscription<PlayerState>? _playerStateNowPlayingSub;

  static Future<void> initialize() async {
    try {
      _audioPlayer = AudioPlayer();
      _setupAudioPlayer();
      _repeatModeController.add(_repeatMode);
      _shuffleController.add(_shuffleEnabled);
    } on MissingPluginException catch (e) {
      _supported = false;
      print('AudioService unsupported on this platform: $e');
    } catch (e) {
      _supported = false;
      print('AudioService initialization error: $e');
    }
  }

  static void _setupAudioPlayer() {
    _audioPlayer?.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        if (_repeatMode == 'one') {
          final item = _currentItem;
          if (item != null) {
            play(item);
          }
        } else {
          next();
        }
      }
    });

    _positionNowPlayingSub?.cancel();
    _positionNowPlayingSub = _audioPlayer?.positionStream.listen((pos) async {
      final item = _currentItem;
      if (item == null) return;
      if (!isPlaying) return;
      try {
        await NowPlayingSyncService.updateNowPlaying(
          item: item,
          isPlaying: true,
          position: pos,
          duration: _audioPlayer?.duration,
          isShuffle: _shuffleEnabled,
          repeatMode: _repeatMode,
          force: false,
        );
      } catch (_) {}
    });

    _playerStateNowPlayingSub?.cancel();
    _playerStateNowPlayingSub = _audioPlayer?.playerStateStream.listen((state) async {
      final item = _currentItem;
      if (item == null) return;
      final playing = state.playing;
      try {
        await NowPlayingSyncService.updateNowPlaying(
          item: item,
          isPlaying: playing,
          position: _audioPlayer?.position ?? Duration.zero,
          duration: _audioPlayer?.duration,
          isShuffle: _shuffleEnabled,
          repeatMode: _repeatMode,
          force: true,
        );
      } catch (_) {}
    });
  }

  static Future<void> play(MediaItem item) async {
    if (!_supported) {
      throw Exception('Audio not supported on this platform');
    }
    if (_audioPlayer == null) {
      await initialize();
    }

    final latestItem = await StorageService.getMediaItem(item.id);
    if (latestItem == null) {
      throw Exception('Media item not found in database');
    }

    print('AudioService: Fetched item from database - filePath: ${latestItem.filePath}, isDownloaded: ${latestItem.isDownloaded}');

    if (!latestItem.isDownloaded) {
      throw Exception('Media item not downloaded');
    }

    _currentItem = latestItem;

    final existingIndex = _playlist.indexWhere((m) => m.id == latestItem.id);
    if (existingIndex != -1) {
      _currentIndex = existingIndex;
    } else {
      _shuffleEnabled = false;
      _shuffleController.add(_shuffleEnabled);
      _playlist = [latestItem];
      _originalPlaylist = [latestItem];
      _currentIndex = 0;
    }
    _emitQueue();
    _emitCurrentIndex();
    _emitNowPlaying();

    if (latestItem.filePath.isEmpty) {
      throw Exception('Media file path is empty');
    }

    final file = File(latestItem.filePath);
    final exists = await file.exists();
    print('AudioService: File exists check: $exists at path: ${latestItem.filePath}');
    
    if (!exists) {
      print('AudioService: Item ID: ${latestItem.id}');
      print('AudioService: Item isDownloaded: ${latestItem.isDownloaded}');
      throw Exception('Media file does not exist at path: ${latestItem.filePath}');
    }

    try {
      print('AudioService: Attempting to play file: ${latestItem.filePath}');
      await _audioPlayer?.setFilePath(latestItem.filePath);
      
      try {
        if (systemAudioHandler == null) {
          await initSystemAudioHandler();
        }
        final handler = systemAudioHandler;
        if (handler is SystemAudioHandler) {
          await handler.updateNowPlaying(latestItem);
        }
      } catch (e) {
        print('AudioService: Error updating system audio handler: $e');
      }
      
      await _audioPlayer?.play();

      try {
        await NowPlayingSyncService.updateNowPlaying(
          item: latestItem,
          isPlaying: true,
          position: _audioPlayer?.position ?? Duration.zero,
          duration: _audioPlayer?.duration,
          isShuffle: _shuffleEnabled,
          repeatMode: _repeatMode,
          force: true,
        );
      } catch (_) {}
      
      await Future.delayed(const Duration(milliseconds: 500));
      
      final actualDuration = _audioPlayer?.duration;
      if (actualDuration != null && actualDuration.inSeconds > 0 && latestItem.duration == 0) {
        final updatedItem = latestItem.copyWith(duration: actualDuration.inSeconds);
        try {
          final handler = systemAudioHandler;
          if (handler is SystemAudioHandler) {
            await handler.updateNowPlaying(updatedItem);
          }
        } catch (e) {
          print('AudioService: Error updating system audio handler with duration: $e');
        }
      }
      
      print('AudioService: Successfully started playback');
    } catch (e) {
      print('AudioService: Error playing file: $e');
      rethrow;
    }

    await _updateLastPlayed(latestItem);
  }

  static Future<void> playPlaylist(List<MediaItem> playlist, int index) async {
    if (!_supported) {
      throw Exception('Audio not supported on this platform');
    }
    _originalPlaylist = List.from(playlist);
    if (_shuffleEnabled) {
      _playlist = _shufflePlaylist(playlist, index);
      _currentIndex = 0;
    } else {
      _playlist = playlist;
      _currentIndex = index;
    }
    _emitQueue();
    _emitCurrentIndex();
    
    if (_currentIndex < _playlist.length) {
      await play(_playlist[_currentIndex]);
    }
  }

  static List<MediaItem> _shufflePlaylist(List<MediaItem> playlist, int currentIndex) {
    final shuffled = List<MediaItem>.from(playlist);
    final currentItem = shuffled.removeAt(currentIndex);
    shuffled.shuffle();
    shuffled.insert(0, currentItem);
    return shuffled;
  }

  static Future<void> pause() async {
    if (!_supported) return;
    await _audioPlayer?.pause();
    final item = _currentItem;
    if (item == null) return;
    try {
      await NowPlayingSyncService.updateNowPlaying(
        item: item,
        isPlaying: false,
        position: _audioPlayer?.position ?? Duration.zero,
        duration: _audioPlayer?.duration,
        isShuffle: _shuffleEnabled,
        repeatMode: _repeatMode,
        force: true,
      );
    } catch (_) {}
  }

  static Future<void> resume() async {
    if (!_supported) return;
    await _audioPlayer?.play();
    final item = _currentItem;
    if (item == null) return;
    try {
      await NowPlayingSyncService.updateNowPlaying(
        item: item,
        isPlaying: true,
        position: _audioPlayer?.position ?? Duration.zero,
        duration: _audioPlayer?.duration,
        isShuffle: _shuffleEnabled,
        repeatMode: _repeatMode,
        force: true,
      );
    } catch (_) {}
  }

  static Future<void> stop() async {
    if (!_supported) return;
    await _audioPlayer?.stop();
    try {
      await NowPlayingSyncService.stopNowPlaying();
    } catch (_) {}
  }

  static Future<void> next() async {
    if (!_supported) return;
    if (_playlist.isEmpty) return;

    if (_repeatMode == 'all' && _currentIndex >= _playlist.length - 1) {
      _currentIndex = 0;
    } else if (_currentIndex < _playlist.length - 1) {
      _currentIndex++;
    } else {
      return;
    }

    await play(_playlist[_currentIndex]);
  }

  static Future<void> previous() async {
    if (!_supported) return;
    if (_playlist.isEmpty) return;

    final currentPosition = _audioPlayer?.position ?? Duration.zero;
    if (currentPosition.inMilliseconds > 3000) {
      await seek(Duration.zero);
      return;
    }

    if (_repeatMode == 'all' && _currentIndex <= 0) {
      _currentIndex = _playlist.length - 1;
    } else if (_currentIndex > 0) {
      _currentIndex--;
    } else {
      return;
    }

    await play(_playlist[_currentIndex]);
  }

  static Future<void> seek(Duration position) async {
    if (!_supported) return;
    await _audioPlayer?.seek(position);
  }

  static Future<void> setVolume(double volume) async {
    if (!_supported) return;
    await _audioPlayer?.setVolume(volume);
  }

  static Future<void> setSpeed(double speed) async {
    if (!_supported) return;
    await _audioPlayer?.setSpeed(speed);
  }

  static bool get isPlaying => _audioPlayer?.playing ?? false;
  static Duration get position => _audioPlayer?.position ?? Duration.zero;
  static Duration get duration => _audioPlayer?.duration ?? Duration.zero;
  static MediaItem? get currentItem => _currentItem;
  static List<MediaItem> get currentPlaylist => _playlist;
  static int get currentIndex => _currentIndex;
  static List<MediaItem> get currentQueue {
    if (_playlist.isEmpty) return const <MediaItem>[];
    final start = (_currentIndex + 1).clamp(0, _playlist.length);
    if (start >= _playlist.length) return const <MediaItem>[];
    return List.unmodifiable(_playlist.sublist(start));
  }
  static Stream<List<MediaItem>> get queueStream => _queueController.stream;
  static Stream<int> get currentIndexStream => _currentIndexController.stream;
  static Stream<MediaItem?> get nowPlayingStream => _nowPlayingController.stream;

  static Stream<PlayerState> get playerStateStream =>
      _supported && _audioPlayer != null
          ? _audioPlayer!.playerStateStream
          : const Stream.empty();

  static Stream<Duration> get positionStream =>
      _supported && _audioPlayer != null
          ? _audioPlayer!.positionStream
          : const Stream.empty();

  static Stream<Duration?> get durationStream =>
      _supported && _audioPlayer != null
          ? _audioPlayer!.durationStream
          : const Stream.empty();

  static final _repeatModeController = StreamController<String>.broadcast();
  static final _shuffleController = StreamController<bool>.broadcast();

  static Stream<String> get repeatModeStream => _repeatModeController.stream;

  static Stream<bool> get shuffleStream => _shuffleController.stream;

  static void _emitQueue() {
    if (_queueController.isClosed) return;
    _queueController.add(currentQueue);
  }

  static void _emitCurrentIndex() {
    if (_currentIndexController.isClosed) return;
    _currentIndexController.add(_currentIndex);
  }

  static void _emitNowPlaying() {
    if (_nowPlayingController.isClosed) return;
    _nowPlayingController.add(_currentItem);
  }

  static Future<void> playQueue(List<MediaItem> items, {bool shuffle = false}) async {
    if (!_supported) {
      throw Exception('Audio not supported on this platform');
    }
    _shuffleEnabled = shuffle;
    _shuffleController.add(_shuffleEnabled);
    _originalPlaylist = List.from(items);
    if (shuffle) {
      _playlist = List<MediaItem>.from(items);
      _playlist.shuffle();
      _currentIndex = 0;
    } else {
      _playlist = List.from(items);
      _currentIndex = 0;
    }
    _emitQueue();
    _emitCurrentIndex();
    if (_playlist.isNotEmpty) {
      await play(_playlist[_currentIndex]);
    }
  }

  static Future<void> playFromQueue(int index) async {
    if (!_supported) return;
    if (_playlist.isEmpty) return;
    final start = (_currentIndex + 1).clamp(0, _playlist.length);
    final absIndex = start + index;
    if (index < 0) return;
    if (absIndex < 0 || absIndex >= _playlist.length) return;
    _currentIndex = absIndex;
    _emitQueue();
    _emitCurrentIndex();
    await play(_playlist[_currentIndex]);
  }

  static void addToQueue(MediaItem item) {
    if (!_supported) return;
    if (_playlist.isEmpty) {
      _originalPlaylist = [item];
      _playlist = [item];
      _currentIndex = 0;
      _emitQueue();
      _emitCurrentIndex();
      return;
    }
    _originalPlaylist.add(item);
    _playlist.add(item);
    _emitQueue();
  }

  static void playNext(MediaItem item) {
    if (!_supported) return;
    if (_playlist.isEmpty) {
      addToQueue(item);
      return;
    }
    final currentItem = _playlist[_currentIndex];
    final insertAt = (_currentIndex + 1).clamp(0, _playlist.length);
    _playlist.insert(insertAt, item);
    final originalIndex = _originalPlaylist.indexWhere((m) => m.id == currentItem.id);
    if (originalIndex == -1) {
      _originalPlaylist.add(item);
    } else {
      _originalPlaylist.insert(originalIndex + 1, item);
    }
    _emitQueue();
  }

  static Future<void> removeFromQueue(int index) async {
    if (!_supported) return;
    if (_playlist.isEmpty) return;
    final start = (_currentIndex + 1).clamp(0, _playlist.length);
    final absIndex = start + index;
    if (index < 0) return;
    if (absIndex < 0 || absIndex >= _playlist.length) return;
    final removed = _playlist.removeAt(absIndex);
    _originalPlaylist.removeWhere((m) => m.id == removed.id);
    _emitQueue();
  }

  static void clearQueue() {
    if (!_supported) return;
    if (_playlist.isEmpty) {
      _emitQueue();
      return;
    }
    if (_currentIndex < 0 || _currentIndex >= _playlist.length) {
      _playlist = [];
      _originalPlaylist = [];
      _currentIndex = 0;
      _emitQueue();
      _emitCurrentIndex();
      return;
    }
    final current = _playlist[_currentIndex];
    _playlist = [current];
    _originalPlaylist = [current];
    _currentIndex = 0;
    _emitQueue();
    _emitCurrentIndex();
  }

  static void reorderQueue(int oldIndex, int newIndex) {
    if (!_supported) return;
    if (_playlist.isEmpty) return;
    final start = (_currentIndex + 1).clamp(0, _playlist.length);
    final upcomingLen = _playlist.length - start;
    if (upcomingLen <= 0) return;
    if (oldIndex < 0 || oldIndex >= upcomingLen) return;
    if (newIndex < 0 || newIndex > upcomingLen) return;

    if (_shuffleEnabled) {
      _shuffleEnabled = false;
      _shuffleController.add(_shuffleEnabled);
    }

    if (oldIndex < newIndex) {
      newIndex -= 1;
    }

    final absOld = start + oldIndex;
    final absNew = start + newIndex;
    final item = _playlist.removeAt(absOld);
    _playlist.insert(absNew, item);
    _originalPlaylist = List.from(_playlist);

    _emitQueue();
    _emitCurrentIndex();
  }

  static void toggleRepeat() {
    switch (_repeatMode) {
      case 'off':
        _repeatMode = 'all';
        break;
      case 'all':
        _repeatMode = 'one';
        break;
      case 'one':
        _repeatMode = 'off';
        break;
    }
    _repeatModeController.add(_repeatMode);
  }

  static void toggleShuffle() {
    _shuffleEnabled = !_shuffleEnabled;
    if (_shuffleEnabled && _playlist.isNotEmpty) {
      final currentItem = _playlist[_currentIndex];
      _playlist = _shufflePlaylist(_originalPlaylist, _originalPlaylist.indexOf(currentItem));
      _currentIndex = 0;
    } else if (!_shuffleEnabled && _originalPlaylist.isNotEmpty) {
      final currentItem = _playlist[_currentIndex];
      _playlist = _originalPlaylist;
      _currentIndex = _originalPlaylist.indexOf(currentItem);
      if (_currentIndex == -1) _currentIndex = 0;
    }
    _shuffleController.add(_shuffleEnabled);
    _emitQueue();
    _emitCurrentIndex();
  }

  static Future<void> _updateLastPlayed(MediaItem item) async {
    final updatedItem = item.copyWith(
      lastPlayed: DateTime.now(),
      playCount: item.playCount + 1,
    );
    await StorageService.updateMediaItem(updatedItem);
  }

  static Future<void> dispose() async {
    if (!_supported) return;
    await _audioPlayer?.dispose();
    await _repeatModeController.close();
    await _shuffleController.close();
    await _queueController.close();
    await _currentIndexController.close();
    await _nowPlayingController.close();
  }
}
