import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../../core/network/extraction_service.dart';
import '../../core/theme/app_colors.dart';
import '../queue/queue_provider.dart';
import 'share_overlay_bridge.dart';

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
  static const _sharingChannel = MethodChannel("com.reeltune.app/sharing");

  ShareIntentHandler(this._ref) : super(const ShareIntentState()) {
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    _localNotifications.initialize(initSettings);
  }

  void initialize(BuildContext context) {
    if (state.initialized) return;
    state = const ShareIntentState(initialized: true);

    // Setup native MethodChannel listener for direct Kotlin intent callback
    _sharingChannel.setMethodCallHandler((call) async {
      if (call.method == "onSharedTextReceived") {
        final text = call.arguments as String?;
        if (text != null) {
          _handleSharedText(text);
        }
      }
    });

    // Fetch any pending intent text from native launch
    _sharingChannel.invokeMethod<String?>("getSharedText").then((text) {
      if (text != null) {
        _handleSharedText(text);
      }
    });

    // Backup plugin subscriptions
    _intentSub = ReceiveSharingIntent.instance.getMediaStream().listen(
      (List<SharedMediaFile> files) {
        _handleSharedFiles(files);
      },
    );

    ReceiveSharingIntent.instance.getInitialMedia().then(
      (List<SharedMediaFile> files) {
        if (files.isNotEmpty) {
          _handleSharedFiles(files);
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
      'Extraction and downloads started in background.',
      details,
    );
  }

  void _handleSharedFiles(List<SharedMediaFile> files) {
    if (files.isEmpty) return;
    for (final file in files) {
      if (file.type == SharedMediaType.url || file.type == SharedMediaType.text) {
        final url = _extractUrl(file.path);
        if (url != null) {
          _handleSharedText(url);
          break;
        }
      }
    }
  }

  Future<void> _handleSharedText(String text) async {
    final url = _extractUrl(text);
    if (url == null) return;

    final platform = ExtractionService.detectPlatform(url);
    final queue = _ref.read(queueProvider.notifier);
    
    // Add to downloader queue
    await queue.addToQueue(
      url: url,
      platform: platform,
    );

    // Compute active badge count (pending + downloading)
    final pendingCount = _ref.read(queueProvider).where((i) => i.status == 'pending' || i.status == 'downloading').length;

    // Direct backgrounding & native overlay triggering
    final hasPermission = await ShareOverlayBridge.checkOverlayPermission();
    if (hasPermission) {
      await ShareOverlayBridge.showBubble(badgeCount: pendingCount > 0 ? pendingCount : 1);
    } else {
      await _showSavedNotification();
    }

    // Instantly return the user to original application (Instagram/YT)
    await ShareOverlayBridge.minimizeToBackground();
  }

  @override
  void dispose() {
    _intentSub?.cancel();
    super.dispose();
  }
}
