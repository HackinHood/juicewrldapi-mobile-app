class MediaItem {
  final String id;
  final String title;
  final String artist;
  final String album;
  final String? genre;
  final int? year;
  final int duration;
  final String filePath;
  final String? coverArtPath;
  final String? downloadUrl;
  final DateTime dateAdded;
  final DateTime lastModified;
  final DateTime? lastPlayed;
  final int playCount;
  final bool isDownloaded;
  final bool isSynced;
  final String? cloudId;

  MediaItem({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    this.genre,
    this.year,
    required this.duration,
    required this.filePath,
    this.coverArtPath,
    this.downloadUrl,
    required this.dateAdded,
    required this.lastModified,
    this.lastPlayed,
    this.playCount = 0,
    this.isDownloaded = false,
    this.isSynced = false,
    this.cloudId,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'album': album,
      'genre': genre,
      'year': year,
      'duration': duration,
      'filePath': filePath,
      'coverArtPath': coverArtPath,
      'downloadUrl': downloadUrl,
      'dateAdded': dateAdded.millisecondsSinceEpoch,
      'lastModified': lastModified.millisecondsSinceEpoch,
      'lastPlayed': lastPlayed?.millisecondsSinceEpoch,
      'playCount': playCount,
      'isDownloaded': isDownloaded ? 1 : 0,
      'isSynced': isSynced ? 1 : 0,
      'cloudId': cloudId,
    };
  }

  factory MediaItem.fromMap(Map<String, dynamic> map) {
    return MediaItem(
      id: map['id'],
      title: map['title'],
      artist: map['artist'],
      album: map['album'],
      genre: map['genre'],
      year: map['year'],
      duration: map['duration'],
      filePath: map['filePath'],
      coverArtPath: map['coverArtPath'],
      downloadUrl: map['downloadUrl'],
      dateAdded: DateTime.fromMillisecondsSinceEpoch(map['dateAdded']),
      lastModified: DateTime.fromMillisecondsSinceEpoch(map['lastModified']),
      lastPlayed: map['lastPlayed'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['lastPlayed'])
          : null,
      playCount: map['playCount'] ?? 0,
      isDownloaded: map['isDownloaded'] == 1,
      isSynced: map['isSynced'] == 1,
      cloudId: map['cloudId'],
    );
  }

  MediaItem copyWith({
    String? id,
    String? title,
    String? artist,
    String? album,
    String? genre,
    int? year,
    int? duration,
    String? filePath,
    String? coverArtPath,
    String? downloadUrl,
    DateTime? dateAdded,
    DateTime? lastModified,
    DateTime? lastPlayed,
    int? playCount,
    bool? isDownloaded,
    bool? isSynced,
    String? cloudId,
  }) {
    return MediaItem(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      genre: genre ?? this.genre,
      year: year ?? this.year,
      duration: duration ?? this.duration,
      filePath: filePath ?? this.filePath,
      coverArtPath: coverArtPath ?? this.coverArtPath,
      downloadUrl: downloadUrl ?? this.downloadUrl,
      dateAdded: dateAdded ?? this.dateAdded,
      lastModified: lastModified ?? this.lastModified,
      lastPlayed: lastPlayed ?? this.lastPlayed,
      playCount: playCount ?? this.playCount,
      isDownloaded: isDownloaded ?? this.isDownloaded,
      isSynced: isSynced ?? this.isSynced,
      cloudId: cloudId ?? this.cloudId,
    );
  }
}
