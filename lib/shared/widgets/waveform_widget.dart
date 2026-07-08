import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

class WaveformWidget extends StatelessWidget {
  final int barCount;
  final double height;
  final Color color;
  final double progress;

  const WaveformWidget({
    super.key,
    this.barCount = 40,
    this.height = 48,
    this.color = AppColors.primary,
    this.progress = 0.0,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(barCount, (index) {
          // Generate a pseudo-random wave pattern
          final seed = (index * 7 + 3) % 10;
          final normalizedHeight = (seed + 2) / 12.0;
          final isPlayed = index / barCount <= progress;

          return Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 0.5),
              height: height * normalizedHeight,
              decoration: BoxDecoration(
                color: isPlayed
                    ? color
                    : color.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      ),
    );
  }
}
