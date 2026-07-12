import 'package:flutter/services.dart';

class ShareOverlayBridge {
  static const _channel = MethodChannel("com.reeltune.app/sharing");

  static Future<bool> checkOverlayPermission() async {
    try {
      return await _channel.invokeMethod<bool>('checkOverlayPermission') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> requestOverlayPermission() async {
    try {
      await _channel.invokeMethod('requestOverlayPermission');
    } catch (_) {}
  }

  static Future<bool> checkAccessibilityPermission() async {
    try {
      return await _channel.invokeMethod<bool>('checkAccessibilityPermission') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> requestAccessibilityPermission() async {
    try {
      await _channel.invokeMethod('requestAccessibilityPermission');
    } catch (_) {}
  }

  static Future<void> showBubble({int badgeCount = 1}) async {
    try {
      await _channel.invokeMethod('showBubble', {'badgeCount': badgeCount});
    } catch (_) {}
  }

  static Future<void> updateBubbleBadge(int count) async {
    try {
      await _channel.invokeMethod('updateBubbleBadge', {'badgeCount': count});
    } catch (_) {}
  }

  static Future<void> dismissBubble() async {
    try {
      await _channel.invokeMethod('dismissBubble');
    } catch (_) {}
  }

  static Future<void> minimizeToBackground() async {
    try {
      await _channel.invokeMethod('minimizeToBackground');
    } catch (_) {}
  }
}
