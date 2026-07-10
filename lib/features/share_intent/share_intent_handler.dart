import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../../core/network/extraction_service.dart';
import '../../core/theme/app_colors.dart';
import '../queue/queue_provider.dart';

final shareIntentHandlerProvider =
    StateNotifierProvider<ShareIntentHandler, ShareIntentState>((ref) {
  return ShareIntentHandler(ref);
});

class ShareIntentState {
  final bool initialized;

  const ShareIntentState({this.initialized = false});
}

class ShareIntentHandler extends StateNotifier<ShareIntentState> {
  final Ref _ref;
  StreamSubscription? _intentSub;
  static final _localNotifications = FlutterLocalNotificationsPlugin();

  ShareIntentHandler(this._ref) : super(const ShareIntentState()) {
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    _localNotifications.initialize(initSettings);
  }

  void initialize(BuildContext context) {
    if (state.initialized) return;
    state = const ShareIntentState(initialized: true);

    // Handle intent when app is already running
    _intentSub = ReceiveSharingIntent.instance.getMediaStream().listen(
      (List<SharedMediaFile> files) {
        _handleSharedFiles(context, files, false);
      },
    );

    // Handle intent when app is launched via share
    ReceiveSharingIntent.instance.getInitialMedia().then(
      (List<SharedMediaFile> files) {
        if (files.isNotEmpty) {
          _handleSharedFiles(context, files, true);
          ReceiveSharingIntent.instance.reset();
        }
      },
    );
  }

  String? _extractUrl(String text) {
    final exp = RegExp(r'(https?://[^\s]+)');
    final match = exp.firstMatch(text);
    return match?.group(0);
  }

  Future<void> _showSavedNotification() async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'reeltune_queue_channel',
        'ReelTune Queue Updates',
        channelDescription: 'Notifications for ReelTune background queue',
        importance: Importance.max,
        priority: Priority.high,
      ),
    );
    await _localNotifications.show(
      999,
      'Saved to ReelTune Queue 🎵',
      'You can continue watching, extraction will be saved.',
      details,
    );
  }

  void _handleSharedFiles(BuildContext context, List<SharedMediaFile> files, bool isInitial) {
    if (files.isEmpty) return;

    for (final file in files) {
      String? url;
      if (file.type == SharedMediaType.url ||
          file.type == SharedMediaType.text) {
        url = _extractUrl(file.path);
      }

      if (url != null) {
        final platform = ExtractionService.detectPlatform(url);
        
        // Quietly add to download queue in background
        _ref.read(queueProvider.notifier).addToQueue(
              url: url,
              platform: platform,
            );

        if (isInitial) {
          _showSavedNotification().then((_) {
            SystemNavigator.pop();
          });
        } else {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Saved to ReelTune Queue 🎵'),
                backgroundColor: AppColors.primary,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
        break; // Handle first valid URL
      }
    }
  }

  @override
  void dispose() {
    _intentSub?.cancel();
    super.dispose();
  }
}
