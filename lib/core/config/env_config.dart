import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'BuildConfig.dart';
import 'AdMobConfig.dart';

class EnvConfig {
  EnvConfig._();

  static String _apiBaseUrl = 'https://api.reeltune.example.com';

  static String get apiBaseUrl => _apiBaseUrl;

  static Future<void> initialize() async {
    final String envFile = BuildConfig.envFileName;
    try {
      final content = await rootBundle.loadString(envFile);
      final lines = content.split('\n');
      final Map<String, String> keys = {};
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
        final parts = trimmed.split('=');
        if (parts.length >= 2) {
          final key = parts[0].trim();
          final value = parts.sublist(1).join('=').trim();
          keys[key] = value;
          if (key == 'API_BASE_URL') {
            _apiBaseUrl = value;
            // Handle Android emulator localhost mapping dynamically
            if (kDebugMode && Platform.isAndroid) {
              if (_apiBaseUrl.contains('localhost')) {
                _apiBaseUrl = _apiBaseUrl.replaceAll('localhost', '10.0.2.2');
              } else if (_apiBaseUrl.contains('127.0.0.1')) {
                _apiBaseUrl = _apiBaseUrl.replaceAll('127.0.0.1', '10.0.2.2');
              }
            }
          }
        }
      }
      AdMobConfig.load(keys);
    } catch (e) {
      debugPrint('Error loading env file $envFile: $e. Falling back to default.');
    }
  }
}
