import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'database_helper.dart';
import 'album_repository.dart';
import 'clip_repository.dart';

class DemoDataInitializer {
  DemoDataInitializer._();

  static Future<void> initialize(
    AlbumRepository albumRepo,
    ClipRepository clipRepo,
  ) async {
    // Only run in development/debug mode
    if (!kDebugMode) return;

    final prefs = await SharedPreferences.getInstance();
    final isInitialized = prefs.getBool('demo_initialized_v2') ?? false;
    if (isInitialized) return;

    try {
      // Check if albums already exist, if so skip
      final existingAlbums = await albumRepo.getAllAlbums();
      if (existingAlbums.isNotEmpty) {
        await prefs.setBool('demo_initialized_v2', true);
        return;
      }

      // 1. Create Demo Albums
      final uuid = const Uuid();
      final workoutAlbumId = uuid.v4();
      final chillAlbumId = uuid.v4();
      final travelAlbumId = uuid.v4();

      final dbHelper = DatabaseHelper();
      final db = await dbHelper.database;

      await db.insert('albums', {
        'id': workoutAlbumId,
        'name': 'Workout',
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'cover_color': '10B981',
      });

      await db.insert('albums', {
        'id': chillAlbumId,
        'name': 'Chill',
        'created_at': DateTime.now().millisecondsSinceEpoch - 1000,
        'cover_color': '38BDF8',
      });

      await db.insert('albums', {
        'id': travelAlbumId,
        'name': 'Travel',
        'created_at': DateTime.now().millisecondsSinceEpoch - 2000,
        'cover_color': 'FB7185',
      });

      // 2. Generate playable audio file
      final appDir = await getApplicationDocumentsDirectory();
      final demoAudioDir = Directory('${appDir.path}/demo_audio');
      if (!await demoAudioDir.exists()) {
        await demoAudioDir.create(recursive: true);
      }

      // Generate a 1-second silent WAV file
      final wavBytes = _generateSilentWav();
      final audioFile = File('${demoAudioDir.path}/demo_silence.wav');
      await audioFile.writeAsBytes(wavBytes);

      // 3. Create Demo Clips
      await clipRepo.createClip(
        albumId: workoutAlbumId,
        title: 'Motivation Boost',
        filePath: audioFile.path,
        durationMs: 180000, // 3 minutes
        sourceUrl: 'https://youtube.com/shorts/motivation',
        sourcePlatform: 'youtube',
      );

      await clipRepo.createClip(
        albumId: workoutAlbumId,
        title: 'No Limits',
        filePath: audioFile.path,
        durationMs: 240000, // 4 minutes
        sourceUrl: 'https://instagram.com/reel/nolimits',
        sourcePlatform: 'instagram',
      );

      await clipRepo.createClip(
        albumId: workoutAlbumId,
        title: 'Push Harder',
        filePath: audioFile.path,
        durationMs: 150000, // 2.5 minutes
        sourceUrl: 'https://tiktok.com/pushharder',
        sourcePlatform: 'tiktok',
      );

      await prefs.setBool('demo_initialized_v2', true);
    } catch (e) {
      debugPrint('Error initializing demo data: $e');
    }
  }

  static List<int> _generateSilentWav() {
    // 44-byte WAV header for 8kHz, 16-bit, mono PCM (1 second = 16000 bytes of data)
    final header = [
      0x52, 0x49, 0x46, 0x46, // "RIFF"
      0x24, 0x3E, 0x00, 0x00, // file size - 8 (16036 bytes)
      0x57, 0x41, 0x56, 0x45, // "WAVE"
      0x66, 0x6D, 0x74, 0x20, // "fmt "
      0x10, 0x00, 0x00, 0x00, // chunk size (16)
      0x01, 0x00,             // audio format (1 = PCM)
      0x01, 0x00,             // channels (1)
      0x40, 0x1F, 0x00, 0x00, // sample rate (8000 Hz)
      0x80, 0x3E, 0x00, 0x00, // byte rate (16000 B/s)
      0x02, 0x00,             // block align (2)
      0x10, 0x00,             // bits per sample (16)
      0x64, 0x61, 0x74, 0x61, // "data"
      0x00, 0x3E, 0x00, 0x00, // data size (16000 bytes)
    ];
    final data = List<int>.filled(16000, 0);
    return [...header, ...data];
  }
}
