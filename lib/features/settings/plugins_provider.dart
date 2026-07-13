import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PluginsState {
  final bool isYoutubeEnabled;
  final bool isJiosaavnEnabled;
  final bool isApplemusicEnabled;

  const PluginsState({
    required this.isYoutubeEnabled,
    required this.isJiosaavnEnabled,
    required this.isApplemusicEnabled,
  });

  factory PluginsState.initial() => const PluginsState(
        isYoutubeEnabled: true,
        isJiosaavnEnabled: true,
        isApplemusicEnabled: true,
      );

  PluginsState copyWith({
    bool? isYoutubeEnabled,
    bool? isJiosaavnEnabled,
    bool? isApplemusicEnabled,
  }) {
    return PluginsState(
      isYoutubeEnabled: isYoutubeEnabled ?? this.isYoutubeEnabled,
      isJiosaavnEnabled: isJiosaavnEnabled ?? this.isJiosaavnEnabled,
      isApplemusicEnabled: isApplemusicEnabled ?? this.isApplemusicEnabled,
    );
  }
}

class PluginsNotifier extends StateNotifier<PluginsState> {
  PluginsNotifier() : super(PluginsState.initial()) {
    _loadPlugins();
  }

  Future<void> _loadPlugins() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = PluginsState(
        isYoutubeEnabled: prefs.getBool('plugin_youtube_enabled') ?? true,
        isJiosaavnEnabled: prefs.getBool('plugin_jiosaavn_enabled') ?? true,
        isApplemusicEnabled: prefs.getBool('plugin_applemusic_enabled') ?? true,
      );
    } catch (_) {}
  }

  Future<void> toggleYoutube(bool enabled) async {
    state = state.copyWith(isYoutubeEnabled: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('plugin_youtube_enabled', enabled);
  }

  Future<void> toggleJiosaavn(bool enabled) async {
    state = state.copyWith(isJiosaavnEnabled: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('plugin_jiosaavn_enabled', enabled);
  }

  Future<void> toggleApplemusic(bool enabled) async {
    state = state.copyWith(isApplemusicEnabled: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('plugin_applemusic_enabled', enabled);
  }
}

final pluginsProvider = StateNotifierProvider<PluginsNotifier, PluginsState>((ref) {
  return PluginsNotifier();
});
