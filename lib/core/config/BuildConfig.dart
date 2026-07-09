import 'environment.dart';

class BuildConfig {
  BuildConfig._();

  // Read compile-time dart-defines
  static const String _env = String.fromEnvironment('APP_ENV', defaultValue: 'development');
  static const bool _useTestAds = bool.fromEnvironment('USE_TEST_ADS', defaultValue: true);

  static AppEnv get environment {
    switch (_env.toLowerCase()) {
      case 'production':
        return AppEnv.production;
      case 'testing':
        return AppEnv.testing;
      case 'development':
      default:
        return AppEnv.development;
    }
  }

  static bool get useTestAds => _useTestAds;

  static String get envFileName {
    switch (environment) {
      case AppEnv.production:
        return '.env.production';
      case AppEnv.testing:
        return '.env.testing';
      case AppEnv.development:
      default:
        return '.env.development';
    }
  }
}
