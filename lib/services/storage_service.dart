import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:music_library_app/models/media_item.dart';
import 'package:music_library_app/models/playlist.dart';

class StorageService {
  static Database? _database;
  static const String _databaseName = 'music_library.db';
  static const int _databaseVersion = 2;

  static const String _mediaTable = 'media_items';
  static const String _playlistTable = 'playlists';
  static bool _initializing = false;

  static Future<void> initialize() async {
    if (_database != null) return;
    if (_initializing) {
      while (_initializing) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      if (_database == null) {
        throw Exception('Database initialization failed');
      }
      return;
    }
    _initializing = true;
    try {
      _database = await _initDatabase();
    } catch (e) {
      print('StorageService initialization error: $e');
      _database = null;
      rethrow;
    } finally {
      _initializing = false;
    }
  }

  static Future<void> _ensureInitialized() async {
    if (_database != null) return;
    try {
      await initialize();
      if (_database == null) {
        print('StorageService: Database is still null after initialization');
      }
    } catch (e) {
      print('StorageService: Failed to initialize database: $e');
      print('StorageService: Error type: ${e.runtimeType}');
      if (e.toString().contains('MissingPluginException')) {
        print('StorageService: sqflite plugin not found. Make sure to rebuild the app after pod install.');
      }
    }
  }

  static Future<Database> _initDatabase() async {
    try {
      final dbPath = await getDatabasesPath();
      String path = join(dbPath, _databaseName);
      return await openDatabase(
        path,
        version: _databaseVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );
    } catch (e) {
      print('StorageService: Error initializing database: $e');
      rethrow;
    }
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $_mediaTable (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        artist TEXT NOT NULL,
        album TEXT NOT NULL,
        genre TEXT,
        year INTEGER,
        duration INTEGER NOT NULL,
        filePath TEXT NOT NULL,
        coverArtPath TEXT,
        downloadUrl TEXT,
        dateAdded INTEGER NOT NULL,
        lastModified INTEGER NOT NULL,
        lastPlayed INTEGER,
        playCount INTEGER DEFAULT 0,
        isDownloaded INTEGER DEFAULT 0,
        isSynced INTEGER DEFAULT 0,
        cloudId TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE $_playlistTable (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        coverArtPath TEXT,
        dateCreated INTEGER NOT NULL,
        lastModified INTEGER NOT NULL,
        mediaItemIds TEXT,
        isSynced INTEGER DEFAULT 0,
        cloudId TEXT
      )
    ''');
  }

  static Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE $_mediaTable ADD COLUMN lastModified INTEGER NOT NULL DEFAULT 0');
    }
  }

  static Future<void> insertMediaItem(MediaItem item) async {
    await _ensureInitialized();
    if (_database == null) return;
    await _database!.insert(_mediaTable, item.toMap());
  }

  static Future<void> updateMediaItem(MediaItem item) async {
    await _ensureInitialized();
    if (_database == null) return;
    final count = await _database!.update(
      _mediaTable,
      item.toMap(),
      where: 'id = ?',
      whereArgs: [item.id],
    );
    if (count == 0) {
      print('StorageService: WARNING - No rows updated for item ID: ${item.id}');
      await _database!.insert(
        _mediaTable,
        item.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      print('StorageService: Inserted item with replace algorithm');
    }
  }

  static Future<void> batchInsertMediaItems(List<MediaItem> items) async {
    await _ensureInitialized();
    if (_database == null) return;
    final batch = _database!.batch();
    for (final item in items) {
      batch.insert(_mediaTable, item.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  static Future<void> batchUpdateMediaItems(List<MediaItem> items) async {
    await _ensureInitialized();
    if (_database == null) return;
    final batch = _database!.batch();
    for (final item in items) {
      batch.update(
        _mediaTable,
        item.toMap(),
        where: 'id = ?',
        whereArgs: [item.id],
      );
    }
    await batch.commit(noResult: true);
  }
  static Future<void> batchUpsertServerFileEntries(
    List<Map<String, dynamic>> entries, {
    required String baseUrl,
  }) async {
    if (entries.isEmpty) {
      print('StorageService: batchUpsertServerFileEntries - entries is empty');
      return;
    }
    await _ensureInitialized();
    if (_database == null) {
      print('StorageService: batchUpsertServerFileEntries - database is null, cannot upsert ${entries.length} entries');
      return;
    }
    print('StorageService: Upserting ${entries.length} server file entries');

    final db = _database!;
    await db.transaction((txn) async {
      const sql = '''
INSERT INTO media_items(
  id,title,artist,album,genre,year,duration,filePath,coverArtPath,downloadUrl,
  dateAdded,lastModified,lastPlayed,playCount,isDownloaded,isSynced,cloudId
) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
ON CONFLICT(id) DO UPDATE SET
  downloadUrl=excluded.downloadUrl,
  lastModified=excluded.lastModified,
  cloudId=excluded.cloudId,
  filePath=CASE WHEN media_items.isDownloaded=1 THEN media_items.filePath ELSE excluded.filePath END,
  title=CASE
    WHEN media_items.isDownloaded=1 AND media_items.artist!='Server' THEN media_items.title
    WHEN media_items.title='' OR media_items.artist='Server' THEN excluded.title
    ELSE media_items.title
  END,
  artist=CASE
    WHEN media_items.isDownloaded=1 AND media_items.artist!='Server' THEN media_items.artist
    ELSE excluded.artist
  END,
  album=CASE
    WHEN media_items.isDownloaded=1 AND media_items.album!='Server Library' THEN media_items.album
    ELSE excluded.album
  END
''';
      const chunkSize = 300;
      for (int i = 0; i < entries.length; i += chunkSize) {
        final batch = txn.batch();
        final end = (i + chunkSize) > entries.length ? entries.length : (i + chunkSize);

        for (int j = i; j < end; j++) {
          final e = entries[j];
          final id = (e['id'] as String?) ?? '';
          if (id.isEmpty) continue;

          final title = (e['title'] as String?) ?? id;
          final ts = (e['timestampMs'] as int?) ?? DateTime.now().millisecondsSinceEpoch;
          final downloadUrl = '$baseUrl/download?filepath=${Uri.encodeComponent(id)}';

          batch.rawInsert(sql, [
            id,
            title,
            'Server',
            'Server Library',
            null,
            null,
            0,
            id,
            null,
            downloadUrl,
            ts,
            ts,
            null,
            0,
            0,
            0,
            id,
          ]);
        }

        await batch.commit(noResult: true);
        await Future<void>.delayed(Duration.zero);
      }
    });
  }

  static Future<void> deleteMediaItem(String id) async {
    await _ensureInitialized();
    if (_database == null) return;
    await _database!.delete(
      _mediaTable,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<MediaItem?> getMediaItem(String id) async {
    await _ensureInitialized();
    if (_database == null) return null;
    final List<Map<String, dynamic>> maps = await _database!.query(
      _mediaTable,
      where: 'id = ?',
      whereArgs: [id],
    );

    if (maps.isNotEmpty) {
      return MediaItem.fromMap(maps.first);
    }
    return null;
  }

  static Future<List<MediaItem>> getAllMediaItems() async {
    await _ensureInitialized();
    if (_database == null) return [];
    final List<Map<String, dynamic>> maps = await _database!.query(
      _mediaTable,
      orderBy: 'dateAdded DESC',
    );

    return List.generate(maps.length, (i) {
      return MediaItem.fromMap(maps[i]);
    });
  }

  static Future<List<MediaItem>> getCachedServerItems() async {
    await _ensureInitialized();
    if (_database == null) {
      print('StorageService: getCachedServerItems - database is null');
      return [];
    }
    try {
      final List<Map<String, dynamic>> maps = await _database!.query(
        _mediaTable,
        where: 'cloudId IS NOT NULL AND cloudId != ?',
        whereArgs: [''],
        orderBy: 'title COLLATE NOCASE ASC',
      );

      print('StorageService: Found ${maps.length} cached server items');
      return List.generate(maps.length, (i) {
        return MediaItem.fromMap(maps[i]);
      });
    } catch (e) {
      print('StorageService: Error querying cached server items: $e');
      return [];
    }
  }

  static Future<void> deleteCachedServerItemsOutsideRoots(Set<String> allowedRoots) async {
    await _ensureInitialized();
    if (_database == null) return;
    final roots = allowedRoots.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (roots.isEmpty) return;
    final placeholders = List.filled(roots.length, '?').join(',');
    final sql = '''
DELETE FROM $_mediaTable
WHERE isDownloaded=0
  AND cloudId IS NOT NULL AND cloudId != ''
  AND (
    CASE
      WHEN instr(filePath, '/') > 0 THEN substr(filePath, 1, instr(filePath, '/') - 1)
      ELSE filePath
    END
  ) NOT IN ($placeholders)
''';
    await _database!.rawDelete(sql, roots);
  }

  static Future<void> deleteAllCachedServerItems() async {
    await _ensureInitialized();
    if (_database == null) return;
    await _database!.delete(
      _mediaTable,
      where: "isDownloaded=0 AND cloudId IS NOT NULL AND cloudId != ''",
    );
  }

  static Future<void> deleteCachedServerItemsNotAllowed(
    bool Function(String path) isAllowed,
  ) async {
    await _ensureInitialized();
    if (_database == null) return;

    final rows = await _database!.query(
      _mediaTable,
      columns: ['id', 'filePath'],
      where: "isDownloaded=0 AND cloudId IS NOT NULL AND cloudId != ''",
    );
    if (rows.isEmpty) return;

    final idsToDelete = <String>[];
    for (final r in rows) {
      final fp = (r['filePath'] as String?) ?? '';
      final id = (r['id'] as String?) ?? '';
      if (id.isEmpty) continue;
      final path = fp.isEmpty ? id : fp;
      if (!isAllowed(path)) {
        idsToDelete.add(id);
      }
    }
    if (idsToDelete.isEmpty) return;

    await _database!.transaction((txn) async {
      const chunkSize = 400;
      for (int i = 0; i < idsToDelete.length; i += chunkSize) {
        final end = (i + chunkSize) > idsToDelete.length ? idsToDelete.length : (i + chunkSize);
        final chunk = idsToDelete.sublist(i, end);
        final batch = txn.batch();
        for (final id in chunk) {
          batch.delete(_mediaTable, where: 'id = ?', whereArgs: [id]);
        }
        await batch.commit(noResult: true);
        await Future<void>.delayed(Duration.zero);
      }
    });
  }

  static Future<void> deleteAllLibraryData() async {
    await _ensureInitialized();
    if (_database == null) return;
    await _database!.transaction((txn) async {
      await txn.delete(_mediaTable);
      await txn.delete(_playlistTable);
    });
  }

  static Future<List<MediaItem>> searchMediaItems(String query) async {
    await _ensureInitialized();
    if (_database == null) return [];
    final List<Map<String, dynamic>> maps = await _database!.query(
      _mediaTable,
      where: 'title LIKE ? OR artist LIKE ? OR album LIKE ?',
      whereArgs: ['%$query%', '%$query%', '%$query%'],
      orderBy: 'dateAdded DESC',
    );

    return List.generate(maps.length, (i) {
      return MediaItem.fromMap(maps[i]);
    });
  }

  static Future<List<MediaItem>> getMediaItemsByArtist(String artist) async {
    await _ensureInitialized();
    if (_database == null) return [];
    final List<Map<String, dynamic>> maps = await _database!.query(
      _mediaTable,
      where: 'artist = ?',
      whereArgs: [artist],
      orderBy: 'album, title',
    );

    return List.generate(maps.length, (i) {
      return MediaItem.fromMap(maps[i]);
    });
  }

  static Future<List<MediaItem>> getMediaItemsByAlbum(String album) async {
    await _ensureInitialized();
    if (_database == null) return [];
    final List<Map<String, dynamic>> maps = await _database!.query(
      _mediaTable,
      where: 'album = ?',
      whereArgs: [album],
      orderBy: 'title COLLATE NOCASE ASC',
    );

    return List.generate(maps.length, (i) {
      return MediaItem.fromMap(maps[i]);
    });
  }

  static Future<List<MediaItem>> getMediaItemsByIds(List<String> ids) async {
    await _ensureInitialized();
    if (_database == null) return [];
    final cleaned = ids.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (cleaned.isEmpty) return [];

    final found = <String, MediaItem>{};
    const chunkSize = 400;
    for (int i = 0; i < cleaned.length; i += chunkSize) {
      final end = (i + chunkSize) > cleaned.length ? cleaned.length : (i + chunkSize);
      final chunk = cleaned.sublist(i, end);
      final placeholders = List.filled(chunk.length, '?').join(',');
      final maps = await _database!.query(
        _mediaTable,
        where: 'id IN ($placeholders)',
        whereArgs: chunk,
      );
      for (final m in maps) {
        final item = MediaItem.fromMap(m);
        found[item.id] = item;
      }
    }

    final ordered = <MediaItem>[];
    for (final id in cleaned) {
      final item = found[id];
      if (item != null) {
        ordered.add(item);
      }
    }
    return ordered;
  }

  static Future<List<String>> getAllArtists() async {
    await _ensureInitialized();
    if (_database == null) return [];
    final List<Map<String, dynamic>> maps = await _database!.rawQuery(
      'SELECT DISTINCT artist FROM $_mediaTable ORDER BY artist',
    );

    return maps.map((map) => map['artist'] as String).toList();
  }

  static Future<List<String>> getAllAlbums() async {
    await _ensureInitialized();
    if (_database == null) return [];
    final List<Map<String, dynamic>> maps = await _database!.rawQuery(
      'SELECT DISTINCT album FROM $_mediaTable ORDER BY album',
    );

    return maps.map((map) => map['album'] as String).toList();
  }

  static Future<void> insertPlaylist(Playlist playlist) async {
    await _ensureInitialized();
    if (_database == null) return;
    await _database!.insert(_playlistTable, playlist.toMap());
  }

  static Future<void> updatePlaylist(Playlist playlist) async {
    await _ensureInitialized();
    if (_database == null) return;
    await _database!.update(
      _playlistTable,
      playlist.toMap(),
      where: 'id = ?',
      whereArgs: [playlist.id],
    );
  }

  static Future<void> deletePlaylist(String id) async {
    await _ensureInitialized();
    if (_database == null) return;
    await _database!.delete(
      _playlistTable,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<Playlist?> getPlaylist(String id) async {
    await _ensureInitialized();
    if (_database == null) return null;
    final List<Map<String, dynamic>> maps = await _database!.query(
      _playlistTable,
      where: 'id = ?',
      whereArgs: [id],
    );

    if (maps.isNotEmpty) {
      return Playlist.fromMap(maps.first);
    }
    return null;
  }

  static Future<List<Playlist>> getAllPlaylists() async {
    await _ensureInitialized();
    if (_database == null) return [];
    final List<Map<String, dynamic>> maps = await _database!.query(
      _playlistTable,
      orderBy: 'lastModified DESC',
    );

    return List.generate(maps.length, (i) {
      return Playlist.fromMap(maps[i]);
    });
  }

  static Future<void> close() async {
    await _database?.close();
  }
}
