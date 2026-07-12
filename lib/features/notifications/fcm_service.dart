import 'package:flutter/foundation.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/constants.dart';

final oneSignalServiceProvider = Provider<OneSignalService>((ref) {
  return OneSignalService(ref.watch(apiClientProvider));
});

class OneSignalService {
  final ApiClient _apiClient;

  OneSignalService(this._apiClient);

  Future<void> initialize() async {
    try {
      // 1. Set log level
      OneSignal.Debug.setLogLevel(OSLogLevel.none);

      // 2. Initialize OneSignal SDK with your App ID
      OneSignal.initialize("c8b3423e-c6cc-4630-a908-2b94f3c19e46");

      // 3. Request push notification permission
      await OneSignal.Notifications.requestPermission(true);

      // 4. Retrieve local deviceId and link it to OneSignal as the External ID
      final prefs = await SharedPreferences.getInstance();
      final deviceId = prefs.getString(AppConstants.keyDeviceId);

      if (deviceId != null && deviceId.isNotEmpty) {
        debugPrint('[OneSignal] Linking device ID: $deviceId');
        OneSignal.login(deviceId);

        // Register the device with the backend (placeholder token)
        await _registerDeviceWithBackend(deviceId);
      } else {
        debugPrint('[OneSignal] Warning: deviceId is null. Deferring registration.');
      }
    } catch (e) {
      debugPrint('[OneSignal] Error initializing OneSignal: $e');
    }
  }

  Future<void> _registerDeviceWithBackend(String deviceId) async {
    try {
      debugPrint('[OneSignal] Registering device $deviceId with backend placeholder');
      await _apiClient.post(
        '/api/devices/register',
        data: {
          'deviceId': deviceId,
          'fcmToken': 'onesignal-registered',
          'platform': defaultTargetPlatform.name.toLowerCase(),
        },
      );
    } catch (e) {
      debugPrint('[OneSignal] Backend placeholder registration failed: $e');
    }
  }
}
