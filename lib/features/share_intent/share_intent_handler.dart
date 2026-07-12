import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../../core/network/extraction_service.dart';
import '../home/main_navigation_screen.dart';
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
    try {
      const initSettings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      );
      _localNotifications.initialize(initSettings);
    } catch (e) {
      debugPrint('[ShareIntent] Failed to initialize notifications: $e');
    }
  }

  void initialize(BuildContext context) {
    if (state.initialized) return;
    state = const ShareIntentState(initialized: true);

    // Setup native MethodChannel listener for direct Kotlin intent callback
    try {
      _sharingChannel.setMethodCallHandler((call) async {
        try {
          if (call.method == "onSharedTextReceived") {
            final text = call.arguments as String?;
            if (text != null && text.isNotEmpty) {
              _handleSharedText(text);
            }
          } else if (call.method == "onNavigateToQueue") {
            _ref.read(navigationIndexProvider.notifier).state = 1;
          }
        } catch (e) {
          debugPrint('[ShareIntent] Error handling MethodChannel call ${call.method}: $e');
        }
      });
    } catch (e) {
      debugPrint('[ShareIntent] Error setting up MethodChannel: $e');
    }

    // Check on startup if we should navigate directly to the Queue tab
    try {
      _sharingChannel.invokeMethod<bool>("shouldOpenQueue").then((shouldOpen) {
        if (shouldOpen == true) {
          _ref.read(navigationIndexProvider.notifier).state = 1;
        }
      }).catchError((e) {
        debugPrint('[ShareIntent] Error checking shouldOpenQueue: $e');
      });
    } catch (e) {
      debugPrint('[ShareIntent] Error invoking shouldOpenQueue: $e');
    }

    // Fetch any pending intent text from native launch
    try {
      _sharingChannel.invokeMethod<String?>("getSharedText").then((text) {
        if (text != null && text.isNotEmpty) {
          _handleSharedText(text);
        }
      }).catchError((e) {
        debugPrint('[ShareIntent] Error getting shared text: $e');
      });
    } catch (e) {
      debugPrint('[ShareIntent] Error invoking getSharedText: $e');
    }

    // Backup plugin subscriptions
    try {
      _intentSub = ReceiveSharingIntent.instance.getMediaStream().listen(
        (List<SharedMediaFile> files) {
          _handleSharedFiles(files);
        },
        onError: (e) {
          debugPrint('[ShareIntent] Media stream error: $e');
        },
      );

      ReceiveSharingIntent.instance.getInitialMedia().then(
        (List<SharedMediaFile> files) {
          if (files.isNotEmpty) {
            _handleSharedFiles(files);
            ReceiveSharingIntent.instance.reset();
          }
        },
      ).catchError((e) {
        debugPrint('[ShareIntent] Error getting initial media: $e');
      });
    } catch (e) {
      debugPrint('[ShareIntent] Error setting up ReceiveSharingIntent: $e');
    }
  }

  String? _extractUrl(String text) {
    try {
      final exp = RegExp(r'(https?://[^\s]+)');
      final match = exp.firstMatch(text);
      return match?.group(0);
    } catch (e) {
      debugPrint('[ShareIntent] Error extracting URL: $e');
      return null;
    }
  }

  Future<void> _showSavedNotification() async {
    try {
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
    } catch (e) {
      debugPrint('[ShareIntent] Error showing notification: $e');
    }
  }

  void _handleSharedFiles(List<SharedMediaFile> files) {
    if (files.isEmpty) return;
    try {
      for (final file in files) {
        if (file.type == SharedMediaType.url || file.type == SharedMediaType.text) {
          final url = _extractUrl(file.path);
          if (url != null) {
            _handleSharedText(url);
            break;
          }
        }
      }
    } catch (e) {
      debugPrint('[ShareIntent] Error handling shared files: $e');
    }
  }

  String? _lastProcessedUrl;
  DateTime? _lastProcessedTime;

  Future<void> _handleSharedText(String text) async {
    try {
      final url = _extractUrl(text);
      if (url == null) {
        debugPrint('[ShareIntent] No valid URL found in: $text');
        return;
      }

      // Deduplicate rapid successive handling of the same URL (e.g., within 3 seconds)
      final now = DateTime.now();
      if (_lastProcessedUrl == url && _lastProcessedTime != null && now.difference(_lastProcessedTime!).inSeconds < 3) {
        debugPrint('[ShareIntent] De-duplicating rapid share event for: $url');
        return;
      }
      _lastProcessedUrl = url;
      _lastProcessedTime = now;

      final platform = ExtractionService.detectPlatform(url);
      final queue = _ref.read(queueProvider.notifier);
      
      // Add to downloader queue
      await queue.addToQueue(
        url: url,
        platform: platform,
      );

      // Compute active badge count
      final pendingCount = _ref.read(queueProvider).where((i) => 
        i.status == 'queued' ||
        i.status == 'pending' || 
        i.status == 'preparing' || 
        i.status == 'fetching_metadata' || 
        i.status == 'extracting_audio' || 
        i.status == 'generating_download_link' || 
        i.status == 'downloading' || 
        i.status == 'saving'
      ).length;

      // Direct backgrounding & native overlay triggering
      try {
        await ShareOverlayBridge.showBubble(badgeCount: pendingCount > 0 ? pendingCount : 1);
      } catch (e) {
        debugPrint('[ShareIntent] Error with overlay/notification: $e');
        await _showSavedNotification();
      }

      // Instantly return the user to original application (Instagram/YT)
      try {
        await ShareOverlayBridge.minimizeToBackground();
      } catch (e) {
        debugPrint('[ShareIntent] Error minimizing: $e');
      }
    } catch (e) {
      debugPrint('[ShareIntent] CRITICAL: Error handling shared text: $e');
    }
  }

  @override
  void dispose() {
    _intentSub?.cancel();
    super.dispose();
  }
}
