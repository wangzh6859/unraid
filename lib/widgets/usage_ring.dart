import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class UsageRing extends StatelessWidget {
  final String label;
  final double percent; // 0-100
  final Color color;
  final String centerLabel;

  const UsageRing({
    super.key,
    required this.label,
    required this.percent,
    required this.color,
    required this.centerLabel,
  });

  @override
  Widget build(BuildContext context) {
    final clamped = (percent.isFinite ? percent : 0).clamp(0, 100).toDouble();
    return Column(
      children: [
        SizedBox(
          width: 96,
          height: 96,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 96,
                height: 96,
                child: CircularProgressIndicator(
                  value: clamped / 100,
                  strokeWidth: 9,
                  strokeCap: StrokeCap.round,
                  backgroundColor: AppColors.border,
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${clamped.toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (centerLabel.isNotEmpty)
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          centerLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 10, color: AppColors.textFaint),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(label,
            style:
                TextStyle(fontSize: 13, color: AppColors.textSecondary)),
      ],
    );
  }
}
