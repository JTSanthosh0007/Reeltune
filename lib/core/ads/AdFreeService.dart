import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final adFreeProvider = StateNotifierProvider<AdFreeNotifier, bool>((ref) {
  return AdFreeNotifier();
});

final adFreeRemainingProvider = StreamProvider<String>((ref) {
  final isAdFree = ref.watch(adFreeProvider);
  if (!isAdFree) return Stream.value('');
  
  final controller = StreamController<String>();
  
  void update() async {
    if (controller.isClosed) return;
    final time = await ref.read(adFreeProvider.notifier).getRemainingTime();
    controller.add(time);
  }
  
  update();
  final timer = Timer.periodic(const Duration(seconds: 15), (_) => update());
  
  ref.onDispose(() {
    timer.cancel();
    controller.close();
  });
  
  return controller.stream;
});

class AdFreeNotifier extends StateNotifier<bool> {
  Timer? _timer;

  AdFreeNotifier() : super(false) {
    _loadAdFreeExpiry();
  }

  Future<void> _loadAdFreeExpiry() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final expiryTime = prefs.getInt('ad_free_expiry');
      if (expiryTime != null) {
        final expiryDate = DateTime.fromMillisecondsSinceEpoch(expiryTime);
        if (DateTime.now().isBefore(expiryDate)) {
          state = true;
          _startTimer(expiryDate);
        } else {
          state = false;
        }
      }
    } catch (e) {
      debugPrint('[AdFreeService] Failed to load expiry: $e');
    }
  }

  Future<void> grantAdFreeDuration(Duration duration) async {
    try {
      final expiryDate = DateTime.now().add(duration);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('ad_free_expiry', expiryDate.millisecondsSinceEpoch);
      state = true;
      _startTimer(expiryDate);
    } catch (e) {
      debugPrint('[AdFreeService] Failed to save expiry: $e');
    }
  }

  void _startTimer(DateTime expiryDate) {
    _timer?.cancel();
    final remaining = expiryDate.difference(DateTime.now());
    if (remaining.isNegative) {
      state = false;
      return;
    }
    _timer = Timer(remaining, () {
      state = false;
    });
  }

  Future<String> getRemainingTime() async {
    final prefs = await SharedPreferences.getInstance();
    final expiryTime = prefs.getInt('ad_free_expiry');
    if (expiryTime != null) {
      final expiryDate = DateTime.fromMillisecondsSinceEpoch(expiryTime);
      final remaining = expiryDate.difference(DateTime.now());
      if (!remaining.isNegative) {
        final hours = remaining.inHours;
        final minutes = remaining.inMinutes % 60;
        return '${hours}h ${minutes}m left';
      }
    }
    return '';
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
