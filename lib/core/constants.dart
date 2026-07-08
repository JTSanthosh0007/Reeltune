import 'config/env_config.dart';

class AppConstants {
  AppConstants._();

  // Backend API
  static String get apiBaseUrl => EnvConfig.apiBaseUrl;

  // App Groups (iOS)
  static const String appGroupId = 'group.com.reeltune.app';

  // Bundle IDs
  static const String bundleId = 'com.reeltune.app';
  static const String shareExtensionBundleId = 'com.reeltune.app.ShareExtension';

  // Storage
  static const String albumsDirectory = 'albums';
  static const String audioExtension = '.mp3';

  // Extraction polling
  static const Duration pollInterval = Duration(seconds: 2);
  static const int maxPollAttempts = 150; // 5 minutes max

  // Rate limiting (client-side awareness)
  static const int maxExtractionsPerHour = 10;

  // Platforms
  static const String platformInstagram = 'instagram';
  static const String platformTiktok = 'tiktok';
  static const String platformYoutube = 'youtube';
  static const String platformFacebook = 'facebook';
  static const String platformLocal = 'local';

  // Shared Preferences keys
  static const String keyOnboardingComplete = 'onboarding_complete';
  static const String keyLegalAccepted = 'legal_accepted';
  static const String keyDeviceId = 'device_id';
  static const String keyThemeMode = 'theme_mode';
}
