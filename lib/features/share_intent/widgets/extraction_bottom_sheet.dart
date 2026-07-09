import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/ads/InterstitialService.dart';
import '../share_intent_provider.dart';
import 'album_picker_sheet.dart';

class ExtractionBottomSheet extends ConsumerWidget {
  const ExtractionBottomSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flowState = ref.watch(extractionFlowProvider);

    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).bottomSheetTheme.backgroundColor ?? AppColors.pureWhite,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(color: AppColors.getAdaptiveSurfaceBorder(context)),
          left: BorderSide(color: AppColors.getAdaptiveSurfaceBorder(context)),
          right: BorderSide(color: AppColors.getAdaptiveSurfaceBorder(context)),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textTertiary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),

              // Content based on step
              _buildContent(context, ref, flowState),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    ExtractionFlowState flowState,
  ) {
    switch (flowState.step) {
      case ExtractionStep.submitting:
        return _StepView(
          icon: Icons.cloud_upload_rounded,
          iconColor: AppColors.skyBlue,
          title: 'Submitting...',
          subtitle: 'Sending link to extraction server',
          showProgress: true,
        );

      case ExtractionStep.extracting:
        return _StepView(
          icon: Icons.auto_awesome_rounded,
          iconColor: AppColors.primary,
          title: 'Extracting Audio',
          subtitle: 'Processing your reel...',
          showProgress: true,
          platform: flowState.platform,
        );

      case ExtractionStep.downloading:
        return _StepView(
          icon: Icons.download_rounded,
          iconColor: AppColors.skyBlue,
          title: 'Downloading',
          subtitle:
              '${(flowState.downloadProgress * 100).toStringAsFixed(0)}% complete',
          showProgress: true,
          progress: flowState.downloadProgress,
        );

      case ExtractionStep.pickAlbum:
        return AlbumPickerSheet(
          title: flowState.generatedTitle ?? 'Audio Clip',
          onAlbumSelected: (albumId) async {
            final clip = await ref
                .read(extractionFlowProvider.notifier)
                .saveToAlbum(albumId);
            if (clip != null && context.mounted) {
              // Short delay then close
              await Future.delayed(const Duration(milliseconds: 800));
              if (context.mounted) {
                Navigator.of(context).pop();
                ref.read(extractionFlowProvider.notifier).reset();
                // Trigger interstitial ad after successful extraction & save
                ref.read(interstitialServiceProvider).showInterstitialIfAllowed(
                      onAdDismissed: () {},
                    );
              }
            }
          },
        );

      case ExtractionStep.saving:
        return _StepView(
          icon: Icons.save_rounded,
          iconColor: AppColors.success,
          title: 'Saving...',
          subtitle: 'Adding to your library',
          showProgress: true,
        );

      case ExtractionStep.done:
        return _StepView(
          icon: Icons.check_circle_rounded,
          iconColor: AppColors.success,
          title: 'Saved!',
          subtitle: 'Audio clip added to your album',
          showProgress: false,
        );

      case ExtractionStep.error:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: AppColors.error,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              'Extraction Failed',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              flowState.errorMessage ?? 'An unknown error occurred',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: () {
                    ref.read(extractionFlowProvider.notifier).reset();
                    Navigator.of(context).pop();
                  },
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.surfaceBorder),
                  ),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: () {
                    ref.read(extractionFlowProvider.notifier).retry();
                  },
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ],
        );

      case ExtractionStep.idle:
        return const SizedBox.shrink();
    }
  }
}

class _StepView extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool showProgress;
  final double? progress;
  final String? platform;

  const _StepView({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.showProgress = false,
    this.progress,
    this.platform,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Icon
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(icon, color: iconColor, size: 32),
        )
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .scale(
              begin: const Offset(1, 1),
              end: const Offset(1.05, 1.05),
              duration: 1500.ms,
            ),

        const SizedBox(height: 20),

        // Platform badge
        if (platform != null)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.glassBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _platformLabel(platform!),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),

        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodyMedium,
        ),

        if (showProgress) ...[
          const SizedBox(height: 20),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: AppColors.surfaceBorder,
              valueColor:
                  AlwaysStoppedAnimation<Color>(iconColor),
              minHeight: 4,
            ),
          ),
        ],

        const SizedBox(height: 8),
      ],
    );
  }

  String _platformLabel(String platform) {
    switch (platform) {
      case 'instagram':
        return '📷 Instagram Reel';
      case 'tiktok':
        return '🎵 TikTok';
      case 'youtube':
        return '▶️ YouTube Short';
      default:
        return '🎧 Local File';
    }
  }
}
