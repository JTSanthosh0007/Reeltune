import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class CoverStorageHelper {
  CoverStorageHelper._();

  /// Saves a picked image file to local app documents directory under /album_covers/
  /// returns the final absolute path of the copied file
  static Future<String> saveAlbumCover(String srcPath, String albumId) async {
    final appDir = await getApplicationDocumentsDirectory();
    final coverDir = Directory('${appDir.path}/album_covers');
    if (!await coverDir.exists()) {
      await coverDir.create(recursive: true);
    }

    final extension = srcPath.split('.').last;
    // Append timestamp to prevent cache issues in Flutter image widgets
    final destPath = '${coverDir.path}/${albumId}_${DateTime.now().millisecondsSinceEpoch}.$extension';

    // Clean up old cover files for this album to save storage space
    try {
      if (await coverDir.exists()) {
        final List<FileSystemEntity> entities = coverDir.listSync();
        for (final entity in entities) {
          if (entity is File && entity.path.contains(albumId)) {
            await entity.delete();
          }
        }
      }
    } catch (e) {
      debugPrint('Warning: cover cleanup failed: $e');
    }

    // Copy to destination
    await File(srcPath).copy(destPath);
    return destPath;
  }
}
