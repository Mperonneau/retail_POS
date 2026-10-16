import 'package:flutter/material.dart';

import '../theme/app_text_styles.dart';
import '../utils/constants.dart';
import '../utils/currency_formatter.dart';

/// Compact KPI chip for cash drawer summaries (HTG + USD subline).
class CashSummaryChip extends StatelessWidget {
  const CashSummaryChip({
    super.key,
    required this.label,
    required this.htg,
    required this.usd,
    required this.color,
    required this.isDark,
  });

  final String label;
  final double htg;
  final double usd;
  final Color color;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppConstants.radiusCard),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppTextStyles.caption(color: color)),
            const SizedBox(height: 3),
            Text(
              CurrencyFormatter.local(context, htg),
              style: AppTextStyles.body(color: color)
                  .copyWith(fontWeight: FontWeight.w700, fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 1),
            Text(
              '\$${usd.toStringAsFixed(2)}',
              style: AppTextStyles.caption(color: color.withValues(alpha: 0.65))
                  .copyWith(fontSize: 10),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
