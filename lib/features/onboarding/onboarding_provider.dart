import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants.dart';

final onboardingCompleteProvider = FutureProvider<bool>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(AppConstants.keyOnboardingComplete) ?? false;
});

final onboardingControllerProvider =
    Provider<OnboardingController>((ref) {
  return OnboardingController(ref);
});

class OnboardingController {
  final Ref _ref;

  OnboardingController(this._ref);

  Future<void> completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.keyOnboardingComplete, true);
    _ref.invalidate(onboardingCompleteProvider);
  }
}
