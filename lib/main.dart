import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audio_service/audio_service.dart';
import 'core/db/album_repository.dart';
import 'core/db/clip_repository.dart';
import 'core/db/demo_data_initializer.dart';
import 'core/config/env_config.dart';
import 'features/player/audio_handler.dart';
import 'app.dart';

late final AudioHandler audioHandler;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Create ProviderContainer
  final container = ProviderContainer();

  // Load environment configuration
  await EnvConfig.initialize();

  // Initialize background audio service
  audioHandler = await initAudioHandler();

  // Initialize demo data in Development/Debug Mode
  final albumRepo = container.read(albumRepositoryProvider);
  final clipRepo = container.read(clipRepositoryProvider);
  await DemoDataInitializer.initialize(albumRepo, clipRepo);

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const ReelTuneApp(),
    ),
  );
}
