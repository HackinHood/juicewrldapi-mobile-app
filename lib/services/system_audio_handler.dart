import 'dart:async';
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:music_library_app/models/media_item.dart' as app_models;
import 'package:music_library_app/services/audio_service.dart' as app_audio;

class SystemAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  StreamSubscription? _positionSubscription;
  StreamSubscription? _playerStateSubscription;
  StreamSubscription? _durationSubscription;
  Duration _currentDuration = Duration.zero;

  SystemAudioHandler() {
    _setupStreams();
  }

  void _setupStreams() {
    _playerStateSubscription = app_audio.AudioService.playerStateStream.listen((state) {
      _updatePlaybackState();
    });

    _positionSubscription = app_audio.AudioService.positionStream.listen((position) {
      _updatePlaybackState();
    });

    _durationSubscription = app_audio.AudioService.durationStream.listen((duration) {
      if (duration != null) {
        _currentDuration = duration;
        _updatePlaybackState();
      }
    });

    _updatePlaybackState();
  }

  void _updatePlaybackState() {
    try {
      final playing = app_audio.AudioService.isPlaying;
      final position = app_audio.AudioService.position;
      final duration = _currentDuration.inMilliseconds > 0 ? _currentDuration : app_audio.AudioService.duration;
      
      final currentState = playbackState.value;
      playbackState.add(
        currentState.copyWith(
          controls: [
            MediaControl.skipToPrevious,
            playing ? MediaControl.pause : MediaControl.play,
            MediaControl.skipToNext,
            MediaControl.stop,
          ],
          systemActions: const {MediaAction.seek},
          androidCompactActionIndices: const [0, 1, 2],
          processingState: AudioProcessingState.ready,
          playing: playing,
          updatePosition: position,
          bufferedPosition: duration,
          speed: 1.0,
        ),
      );
    } catch (e) {
      print('SystemAudioHandler: Error updating playback state: $e');
    }
  }

  Future<void> updateNowPlaying(app_models.MediaItem item) async {
    String? artUri;

    final localArtPath = item.coverArtPath;
    if (localArtPath != null && localArtPath.isNotEmpty) {
      final file = File(localArtPath);
      if (await file.exists()) {
        artUri = file.uri.toString();
      }
    }

    if (artUri != null) {
      final durationSeconds = item.duration > 0 ? item.duration : 0;
      final duration = Duration(seconds: durationSeconds);
      _currentDuration = duration;

      String title = item.title;
      String artist = item.artist;
      String album = item.album;

      if (artist == 'Server' && album == 'Server Library') {
        final parts = title.split(' - ');
        if (parts.length >= 2) {
          artist = parts.first.trim();
          title = parts.sublist(1).join(' - ').trim();
        }
      }

      if (title.isEmpty) title = 'Unknown Title';
      if (artist.isEmpty) artist = 'Unknown Artist';
      if (album.isEmpty) album = 'Unknown Album';

      final audioItem = MediaItem(
        id: item.id,
        title: title,
        artist: artist,
        album: album,
        duration: duration,
        artUri: Uri.parse(artUri),
        genre: item.genre,
        extras: {
          if (item.year != null) 'year': item.year,
        },
      );

      print('SystemAudioHandler: Updating media item - Title: ${item.title}, Artist: ${item.artist}, Album: ${item.album}, Duration: $duration, ArtUri: $artUri');
      mediaItem.add(audioItem);
      _updatePlaybackState();
      return;
    }

    final cloudId = item.cloudId;
    if (cloudId != null && cloudId.isNotEmpty) {
      final encoded = Uri.encodeComponent(cloudId);
      artUri = 'https://m.juicewrldapi.com/album-art?filepath=$encoded';
    } else {
      final path = item.filePath;
      final lower = path.toLowerCase();
      final isServerPath = lower.startsWith('audio/') ||
          lower.startsWith('studio_sessions/') ||
          lower.startsWith('studio-sessions/');
      if (isServerPath) {
        final encodedPath = Uri.encodeComponent(path);
        artUri = 'https://m.juicewrldapi.com/album-art?filepath=$encodedPath';
      }
    }

    final durationSeconds = item.duration > 0 ? item.duration : 0;
    final duration = Duration(seconds: durationSeconds);
    _currentDuration = duration;

    String title = item.title;
    String artist = item.artist;
    String album = item.album;

    if (artist == 'Server' && album == 'Server Library') {
      final parts = title.split(' - ');
      if (parts.length >= 2) {
        artist = parts.first.trim();
        title = parts.sublist(1).join(' - ').trim();
      }
    }

    if (title.isEmpty) title = 'Unknown Title';
    if (artist.isEmpty) artist = 'Unknown Artist';
    if (album.isEmpty) album = 'Unknown Album';

    final audioItem = MediaItem(
      id: item.id,
      title: title,
      artist: artist,
      album: album,
      duration: duration,
      artUri: artUri != null ? Uri.parse(artUri) : null,
      genre: item.genre,
      extras: {
        if (item.year != null) 'year': item.year,
      },
    );
    
    print('SystemAudioHandler: Updating media item - Title: ${item.title}, Artist: ${item.artist}, Album: ${item.album}, Duration: $duration, ArtUri: $artUri');
    mediaItem.add(audioItem);
    _updatePlaybackState();
  }

  @override
  Future<void> dispose() async {
    await _positionSubscription?.cancel();
    await _playerStateSubscription?.cancel();
    await _durationSubscription?.cancel();
  }

  @override
  Future<void> play() {
    return app_audio.AudioService.resume();
  }

  @override
  Future<void> pause() {
    return app_audio.AudioService.pause();
  }

  @override
  Future<void> stop() {
    return app_audio.AudioService.stop();
  }

  @override
  Future<void> skipToNext() {
    return app_audio.AudioService.next();
  }

  @override
  Future<void> skipToPrevious() {
    return app_audio.AudioService.previous();
  }

  @override
  Future<void> seek(Duration position) {
    return app_audio.AudioService.seek(position);
  }
}

AudioHandler? systemAudioHandler;

Future<void> initSystemAudioHandler() async {
  try {
    systemAudioHandler = await AudioService.init(
      builder: () => SystemAudioHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.juicewrldapi.musicapp.audio',
        androidNotificationChannelName: 'Audio Playback',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
      ),
    );
    print('SystemAudioHandler: Initialized successfully');
  } catch (e) {
    print('SystemAudioHandler: Initialization failed: $e');
    systemAudioHandler = null;
  }
}



