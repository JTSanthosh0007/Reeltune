import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

final adConsentProvider = StateNotifierProvider<ConsentNotifier, bool>((ref) {
  return ConsentNotifier();
});

class ConsentNotifier extends StateNotifier<bool> {
  ConsentNotifier() : super(false) {
    initConsent();
  }

  Future<void> initConsent() async {
    // Under COPPA, or if consent is not required/obtained, we handle loading safely.
    final params = ConsentRequestParameters(
      tagForUnderAgeOfConsent: false,
    );

    ConsentInformation.instance.requestConsentInfoUpdate(
      params,
      () async {
        final isAvailable = await ConsentInformation.instance.isConsentFormAvailable();
        if (isAvailable) {
          _loadForm();
        } else {
          // If form is not available, we can show ads safely
          state = true;
        }
      },
      (FormError error) {
        debugPrint('Consent info update failed: ${error.message}');
        // Fallback to allowing ads so we don't break the app flow
        state = true;
      },
    );
  }

  void _loadForm() {
    ConsentForm.loadConsentForm(
      (ConsentForm consentForm) async {
        final status = await ConsentInformation.instance.getConsentStatus();
        if (status == ConsentStatus.required) {
          consentForm.show((FormError? showFormError) {
            if (showFormError != null) {
              debugPrint('Consent form display failed: ${showFormError.message}');
            }
            // Re-evaluate after form is shown/dismissed
            _loadForm();
          });
        } else {
          state = true;
        }
      },
      (FormError error) {
        debugPrint('Consent form load failed: ${error.message}');
        // Fallback to enabling ads
        state = true;
      },
    );
  }

  // Shows the options form (privacy policy change screen) from Settings Screen
  void showPrivacyOptionsForm(BuildContext context) {
    ConsentForm.showPrivacyOptionsForm((FormError? error) {
      if (error != null) {
        debugPrint('Privacy Options Form failed to show: ${error.message}');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load privacy preferences Form')),
        );
      }
    });
  }
}
