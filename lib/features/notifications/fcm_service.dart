import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/constants.dart';

final fcmServiceProvider = Provider<FcmService>((ref) {
  return FcmService(ref.watch(apiClientProvider));
});

class FcmService {
  final ApiClient _apiClient;
  static final FlutterLocalNotificationsPlugin _localNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  FcmService(this._apiClient);

  Future<void> initialize() async {
    try {
      // 1. Initialize Firebase Core
      await Firebase.initializeApp();

      // 2. Setup Local Notifications for Foreground handling
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      
      const InitializationSettings initializationSettings = InitializationSettings(
        android: initializationSettingsAndroid,
      );

      await _localNotificationsPlugin.initialize(initializationSettings);

      // Create Android Notification Channel
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'reeltune_push_channel', // id
        'ReelTune Push Notifications', // name
        description: 'Channel for ReelTune updates and push alerts', // description
        importance: Importance.max,
      );

      await _localNotificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);

      // 3. Request Permissions
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        debugPrint('[FCM] User granted permission');

        // 4. Retrieve Registration Token
        final token = await messaging.getToken();
        if (token != null) {
          await _registerTokenWithBackend(token);
        }

        // 5. Token Refresh Listener
        messaging.onTokenRefresh.listen(_registerTokenWithBackend);

        // 6. Foreground Messages Listener
        FirebaseMessaging.onMessage.listen((RemoteMessage message) {
          RemoteNotification? notification = message.notification;
          AndroidNotification? android = message.notification?.android;

          if (notification != null && android != null) {
            _localNotificationsPlugin.show(
              notification.hashCode,
              notification.title,
              notification.body,
              NotificationDetails(
                android: AndroidNotificationDetails(
                  channel.id,
                  channel.name,
                  channelDescription: channel.description,
                  icon: android.smallIcon ?? '@mipmap/ic_launcher',
                ),
              ),
            );
          }
        });
      }
    } catch (e) {
      debugPrint('[FCM] Error initializing Cloud Messaging: $e');
    }
  }

  Future<void> _registerTokenWithBackend(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final deviceId = prefs.getString(AppConstants.keyDeviceId);

      if (deviceId == null) {
        debugPrint('[FCM] Device ID is not initialized yet. Deferring registration.');
        return;
      }

      debugPrint('[FCM] Registering token: $token');
      
      await _apiClient.post(
        '/api/devices/register',
        data: {
          'deviceId': deviceId,
          'fcmToken': token,
          'platform': defaultTargetPlatform.name.toLowerCase(),
        },
      );
    } catch (e) {
      debugPrint('[FCM] Registration with backend failed: $e');
    }
  }
}
