import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'features/player/audio_handler.dart';
import 'app.dart';

late final AudioHandler audioHandler;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize background audio service
  audioHandler = await initAudioHandler();

  runApp(
    const ProviderScope(
      child: ReelTuneApp(),
    ),
  );
}
