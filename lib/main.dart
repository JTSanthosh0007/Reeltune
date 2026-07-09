import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audio_service/audio_service.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'core/db/album_repository.dart';
import 'core/db/clip_repository.dart';
import 'core/db/demo_data_initializer.dart';
import 'core/config/env_config.dart';
import 'core/ads/AppOpenService.dart';
import 'core/ads/InterstitialService.dart';
import 'core/ads/RewardedService.dart';
import 'features/player/audio_handler.dart';
import 'app.dart';

late final AudioHandler audioHandler;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Create ProviderContainer early so the app can start rendering
  final container = ProviderContainer();

  // Run all independent initialization tasks concurrently instead of sequentially
  final results = await Future.wait<dynamic>([
    MobileAds.instance.initialize(), // index 0
    EnvConfig.initialize(),          // index 1
    initAudioHandler(),              // index 2
  ]);

  audioHandler = results[2] as AudioHandler;

  // Launch the app immediately — defer non-critical work to after the first frame
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const ReelTuneApp(),
    ),
  );

  // Defer ad preloading and demo data to after the first frame renders
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    // Trigger ad service creation to start preloading logic
    container.read(appOpenServiceProvider);
    container.read(interstitialServiceProvider);
    container.read(rewardedServiceProvider);

    // Initialize demo data in Development/Debug Mode
    final albumRepo = container.read(albumRepositoryProvider);
    final clipRepo = container.read(clipRepositoryProvider);
    await DemoDataInitializer.initialize(albumRepo, clipRepo);
  });
}
