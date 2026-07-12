import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PluginManifest {
  final String id;
  final String name;
  final String description;
  final int colorValue;
  final bool isEnabled;
  final bool isCustom;
  final String? configUrl;

  PluginManifest({
    required this.id,
    required this.name,
    required this.description,
    required this.colorValue,
    this.isEnabled = true,
    this.isCustom = false,
    this.configUrl,
  });

  PluginManifest copyWith({
    String? name,
    String? description,
    int? colorValue,
    bool? isEnabled,
    bool? isCustom,
    String? configUrl,
  }) {
    return PluginManifest(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      colorValue: colorValue ?? this.colorValue,
      isEnabled: isEnabled ?? this.isEnabled,
      isCustom: isCustom ?? this.isCustom,
      configUrl: configUrl ?? this.configUrl,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'colorValue': colorValue,
      'isEnabled': isEnabled,
      'isCustom': isCustom,
      'configUrl': configUrl,
    };
  }

  factory PluginManifest.fromJson(Map<String, dynamic> json) {
    return PluginManifest(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      colorValue: json['colorValue'] as int,
      isEnabled: json['isEnabled'] as bool? ?? true,
      isCustom: json['isCustom'] as bool? ?? false,
      configUrl: json['configUrl'] as String?,
    );
  }

  Color get color => Color(colorValue);

  IconData get icon {
    switch (id) {
      case 'spotify':
        return Icons.music_note_rounded;
      case 'youtube':
        return Icons.video_library_rounded;
      case 'apple':
        return Icons.apple_rounded;
      case 'jiosaavn':
        return Icons.library_music_rounded;
      case 'm3u':
        return Icons.list_alt_rounded;
      default:
        return Icons.extension_rounded;
    }
  }
}

final pluginsProvider = StateNotifierProvider<PluginsNotifier, List<PluginManifest>>((ref) {
  return PluginsNotifier()..loadPlugins();
});

class PluginsNotifier extends StateNotifier<List<PluginManifest>> {
  PluginsNotifier() : super([]);

  static const String _prefsKey = 'reeltune_importer_plugins';

  final List<PluginManifest> _defaultPlugins = [
    PluginManifest(
      id: 'spotify',
      name: 'Spotify Importer',
      description: 'Import Spotify playlists and albums into ReelTune.',
      colorValue: const Color(0xFF1DB954).value,
    ),
    PluginManifest(
      id: 'youtube',
      name: 'YouTube Music Importer',
      description: 'Import YouTube and YouTube Music playlists/albums.',
      colorValue: const Color(0xFFFF0000).value,
    ),
    PluginManifest(
      id: 'apple',
      name: 'Apple Music Importer',
      description: 'Import Apple Music playlists and albums.',
      colorValue: const Color(0xFFFC3C44).value,
    ),
    PluginManifest(
      id: 'jiosaavn',
      name: 'JioSaavn Importer',
      description: 'Import JioSaavn playlists and albums into ReelTune.',
      colorValue: const Color(0xFF24A1E1).value,
    ),
    PluginManifest(
      id: 'm3u',
      name: 'M3U Importer',
      description: 'Import tracks from local M3U / M3U8 files.',
      colorValue: const Color(0xFFD4AF37).value,
    ),
  ];

  Future<void> loadPlugins() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_prefsKey);
      if (jsonStr == null || jsonStr.isEmpty) {
        state = _defaultPlugins;
        await _saveToPrefs();
        return;
      }

      final list = json.decode(jsonStr) as List<dynamic>;
      state = list.map((item) => PluginManifest.fromJson(Map<String, dynamic>.from(item))).toList();
    } catch (e) {
      debugPrint('[PluginsNotifier] Error loading plugins: $e');
      state = _defaultPlugins;
    }
  }

  Future<void> _saveToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = json.encode(state.map((e) => e.toJson()).toList());
      await prefs.setString(_prefsKey, jsonStr);
    } catch (e) {
      debugPrint('[PluginsNotifier] Error saving plugins: $e');
    }
  }

  Future<void> togglePlugin(String id) async {
    state = [
      for (final p in state)
        if (p.id == id) p.copyWith(isEnabled: !p.isEnabled) else p
    ];
    await _saveToPrefs();
  }

  Future<void> addCustomPlugin({
    required String name,
    required String description,
    required String endpointUrl,
  }) async {
    final cleanId = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_') +
        '_' +
        DateTime.now().millisecondsSinceEpoch.toString();

    // Use a clean color and dynamic icon for custom plugin
    final newPlugin = PluginManifest(
      id: cleanId,
      name: name,
      description: description,
      colorValue: Colors.purple.value,
      isCustom: true,
      isEnabled: true,
      configUrl: endpointUrl,
    );

    state = [...state, newPlugin];
    await _saveToPrefs();
  }

  Future<void> removeCustomPlugin(String id) async {
    state = state.where((p) => p.id != id).toList();
    await _saveToPrefs();
  }
}
