import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audio_service/audio_service.dart';
import 'core/db/album_repository.dart';
import 'core/db/clip_repository.dart';
import 'core/db/demo_data_initializer.dart';
import 'core/config/env_config.dart';
import 'core/config/AdManager.dart';
import 'core/ads/AppOpenService.dart';
import 'core/ads/InterstitialService.dart';
import 'core/ads/RewardedService.dart';
import 'features/player/audio_handler.dart';
import 'app.dart';

late final AudioHandler audioHandler;

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Create ProviderContainer early so the app can start rendering
  final container = ProviderContainer();

  // Launch the app immediately — defer all initialization to the AppEntryPoint
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const ReelTuneApp(),
    ),
  );
}
