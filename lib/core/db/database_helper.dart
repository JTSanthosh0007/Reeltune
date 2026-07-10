import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final databaseHelperProvider = Provider<DatabaseHelper>((ref) {
  return DatabaseHelper();
});

class DatabaseHelper {
  static Database? _database;
  static const String _dbName = 'reeltune.db';
  static const int _dbVersion = 5;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);

    return await openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onConfigure: _onConfigure,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onConfigure(Database db) async {
    // Enable foreign key support
    await db.execute('PRAGMA foreign_keys = ON');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE albums ADD COLUMN cover_image_path TEXT');
    }
    if (oldVersion < 3) {
      // Add new metadata columns to clips
      await db.execute('ALTER TABLE clips ADD COLUMN artist TEXT');
      await db.execute('ALTER TABLE clips ADD COLUMN album_name TEXT');
      await db.execute('ALTER TABLE clips ADD COLUMN bitrate INTEGER');
      await db.execute('ALTER TABLE clips ADD COLUMN file_size INTEGER');
      await db.execute('ALTER TABLE clips ADD COLUMN genre TEXT');
      await db.execute('ALTER TABLE clips ADD COLUMN year INTEGER');
      await db.execute('ALTER TABLE clips ADD COLUMN track_number INTEGER');
      await db.execute('ALTER TABLE clips ADD COLUMN is_favorite INTEGER DEFAULT 0');
      await db.execute('ALTER TABLE clips ADD COLUMN last_played_at INTEGER');

      // Create playlist tables
      await db.execute('''
        CREATE TABLE playlists (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          created_at INTEGER NOT NULL
        )
      ''');

      await db.execute('''
        CREATE TABLE playlist_clips (
          playlist_id TEXT NOT NULL,
          clip_id TEXT NOT NULL,
          PRIMARY KEY (playlist_id, clip_id),
          FOREIGN KEY (playlist_id) REFERENCES playlists(id) ON DELETE CASCADE,
          FOREIGN KEY (clip_id) REFERENCES clips(id) ON DELETE CASCADE
        )
      ''');
    }
    if (oldVersion < 4) {
      await db.execute('''
        CREATE TABLE notifications (
          id TEXT PRIMARY KEY,
          title TEXT NOT NULL,
          body TEXT NOT NULL,
          timestamp INTEGER NOT NULL,
          is_read INTEGER DEFAULT 0,
          type TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 5) {
      // Add description and cover_image_path to playlists, and sort_order to playlist_clips
      try {
        await db.execute('ALTER TABLE playlists ADD COLUMN description TEXT');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE playlists ADD COLUMN cover_image_path TEXT');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE playlist_clips ADD COLUMN sort_order INTEGER DEFAULT 0');
      } catch (_) {}
    }
    // Ensure default fallback album exists
    await db.execute(
      "INSERT OR IGNORE INTO albums (id, name, created_at, cover_color) "
      "VALUES ('imported_playlist_songs', 'Imported Tracks', 1700000000000, '94A3B8')"
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE albums (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        cover_color TEXT,
        cover_image_path TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE clips (
        id TEXT PRIMARY KEY,
        album_id TEXT NOT NULL,
        title TEXT NOT NULL,
        file_path TEXT NOT NULL,
        duration_ms INTEGER,
        source_url TEXT,
        source_platform TEXT,
        created_at INTEGER NOT NULL,
        artist TEXT,
        album_name TEXT,
        bitrate INTEGER,
        file_size INTEGER,
        genre TEXT,
        year INTEGER,
        track_number INTEGER,
        is_favorite INTEGER DEFAULT 0,
        last_played_at INTEGER,
        FOREIGN KEY (album_id) REFERENCES albums(id) ON DELETE CASCADE
      )
    ''');

    // Index for faster album-based queries
    await db.execute(
      'CREATE INDEX idx_clips_album_id ON clips(album_id)',
    );

    // Index for search
    await db.execute(
      'CREATE INDEX idx_clips_title ON clips(title COLLATE NOCASE)',
    );

    // Create playlist tables
    await db.execute('''
      CREATE TABLE playlists (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        description TEXT,
        cover_image_path TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE playlist_clips (
        playlist_id TEXT NOT NULL,
        clip_id TEXT NOT NULL,
        sort_order INTEGER DEFAULT 0,
        PRIMARY KEY (playlist_id, clip_id),
        FOREIGN KEY (playlist_id) REFERENCES playlists(id) ON DELETE CASCADE,
        FOREIGN KEY (clip_id) REFERENCES clips(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE notifications (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        body TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        is_read INTEGER DEFAULT 0,
        type TEXT NOT NULL
      )
    ''');
    
    // Ensure default fallback album exists
    await db.execute(
      "INSERT OR IGNORE INTO albums (id, name, created_at, cover_color) "
      "VALUES ('imported_playlist_songs', 'Imported Tracks', 1700000000000, '94A3B8')"
    );
  }

  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}
