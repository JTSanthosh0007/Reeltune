import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants.dart';
import '../../core/theme/app_colors.dart';

class LegalDialog {
  static const String _legalText = '''
Audio extracted via ReelTune is for personal offline listening only.

Redistribution or commercial use of extracted audio may infringe the original creator's copyright and applicable intellectual property laws.

You are solely responsible for your usage of content saved through this app. ReelTune does not host, store, or distribute any copyrighted content — all processing is performed on-demand and temporary files are automatically deleted.

By using this app, you acknowledge and agree to these terms.''';

  /// Show the legal dialog. If [force] is true, always shows.
  /// Otherwise, only shows if not previously acknowledged.
  static Future<void> show(BuildContext context, {bool force = true}) async {
    if (!force) {
      final prefs = await SharedPreferences.getInstance();
      final accepted = prefs.getBool(AppConstants.keyLegalAccepted) ?? false;
      if (accepted) return;
    }

    if (!context.mounted) return;

    return showDialog(
      context: context,
      barrierDismissible: force, // First-time dialog is mandatory
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.coral.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.gavel_rounded,
                color: AppColors.coral,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text('Fair Use Notice'),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.coral.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.coral.withValues(alpha: 0.2),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: AppColors.coral, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Please read carefully',
                        style: TextStyle(
                          color: AppColors.coral,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _legalText,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      height: 1.5,
                    ),
              ),
            ],
          ),
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool(AppConstants.keyLegalAccepted, true);
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              },
              child: const Text('I Understand'),
            ),
          ),
        ],
      ),
    );
  }

  /// Show the first-time legal dialog (mandatory, cannot dismiss without accepting)
  static Future<void> showFirstTime(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final accepted = prefs.getBool(AppConstants.keyLegalAccepted) ?? false;
    if (accepted) return;

    if (!context.mounted) return;
    await show(context, force: false);
  }
}
