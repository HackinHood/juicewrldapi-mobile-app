class Playlist {
  final String id;
  final String name;
  final String? description;
  final String? coverArtPath;
  final DateTime dateCreated;
  final DateTime lastModified;
  final List<String> mediaItemIds;
  final bool isSynced;
  final String? cloudId;

  Playlist({
    required this.id,
    required this.name,
    this.description,
    this.coverArtPath,
    required this.dateCreated,
    required this.lastModified,
    this.mediaItemIds = const [],
    this.isSynced = false,
    this.cloudId,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'coverArtPath': coverArtPath,
      'dateCreated': dateCreated.millisecondsSinceEpoch,
      'lastModified': lastModified.millisecondsSinceEpoch,
      'mediaItemIds': mediaItemIds.join(','),
      'isSynced': isSynced ? 1 : 0,
      'cloudId': cloudId,
    };
  }

  factory Playlist.fromMap(Map<String, dynamic> map) {
    final rawIds = map['mediaItemIds'];
    final ids = rawIds is String
        ? rawIds.split(',').where((id) => id.trim().isNotEmpty).toList()
        : <String>[];
    return Playlist(
      id: (map['id'] as String?) ?? '',
      name: (map['name'] as String?) ?? '',
      description: map['description'] as String?,
      coverArtPath: map['coverArtPath'] as String?,
      dateCreated: DateTime.fromMillisecondsSinceEpoch((map['dateCreated'] as int?) ?? 0),
      lastModified: DateTime.fromMillisecondsSinceEpoch((map['lastModified'] as int?) ?? 0),
      mediaItemIds: ids,
      isSynced: map['isSynced'] == 1,
      cloudId: map['cloudId'] as String?,
    );
  }

  Playlist copyWith({
    String? id,
    String? name,
    String? description,
    String? coverArtPath,
    DateTime? dateCreated,
    DateTime? lastModified,
    List<String>? mediaItemIds,
    bool? isSynced,
    String? cloudId,
  }) {
    return Playlist(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      coverArtPath: coverArtPath ?? this.coverArtPath,
      dateCreated: dateCreated ?? this.dateCreated,
      lastModified: lastModified ?? this.lastModified,
      mediaItemIds: mediaItemIds ?? this.mediaItemIds,
      isSynced: isSynced ?? this.isSynced,
      cloudId: cloudId ?? this.cloudId,
    );
  }
}
