import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../constants.dart';

final fileStorageServiceProvider = Provider<FileStorageService>((ref) {
  return FileStorageService();
});

class FileStorageService {
  Directory? _baseDir;

  /// Get the base storage directory for albums
  Future<Directory> get baseDirectory async {
    if (_baseDir != null) return _baseDir!;
    final appDir = await getApplicationDocumentsDirectory();
    _baseDir = Directory(p.join(appDir.path, AppConstants.albumsDirectory));
    if (!await _baseDir!.exists()) {
      await _baseDir!.create(recursive: true);
    }
    return _baseDir!;
  }

  /// Get the directory for a specific album
  Future<Directory> getAlbumDirectory(String albumId) async {
    final base = await baseDirectory;
    final dir = Directory(p.join(base.path, albumId));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Generate the file path for a new clip
  Future<String> getClipFilePath(String albumId, String clipId) async {
    final albumDir = await getAlbumDirectory(albumId);
    return p.join(albumDir.path, '$clipId${AppConstants.audioExtension}');
  }

  /// Save audio data to a clip file
  Future<String> saveAudioFile(
    String albumId,
    String clipId,
    List<int> audioData,
  ) async {
    final filePath = await getClipFilePath(albumId, clipId);
    final file = File(filePath);
    await file.writeAsBytes(audioData);
    return filePath;
  }

  /// Copy a file (e.g., from shared intent temp location)
  Future<String> copyToAlbum(
    String sourcePath,
    String albumId,
    String clipId,
  ) async {
    final destPath = await getClipFilePath(albumId, clipId);
    final sourceFile = File(sourcePath);
    await sourceFile.copy(destPath);
    return destPath;
  }

  /// Move a clip file from one album to another
  Future<String> moveClipFile(
    String currentPath,
    String newAlbumId,
    String clipId,
  ) async {
    final newPath = await getClipFilePath(newAlbumId, clipId);
    final file = File(currentPath);
    if (await file.exists()) {
      await file.copy(newPath);
      await file.delete();
    }
    return newPath;
  }

  /// Delete a clip file
  Future<void> deleteClipFile(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Delete an entire album directory
  Future<void> deleteAlbumDirectory(String albumId) async {
    final base = await baseDirectory;
    final dir = Directory(p.join(base.path, albumId));
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  /// Get total storage used by all albums in bytes
  Future<int> getTotalStorageUsed() async {
    final base = await baseDirectory;
    if (!await base.exists()) return 0;

    int totalBytes = 0;
    await for (final entity in base.list(recursive: true)) {
      if (entity is File) {
        totalBytes += await entity.length();
      }
    }
    return totalBytes;
  }

  /// Format bytes to human-readable string
  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
