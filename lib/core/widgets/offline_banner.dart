import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/device_session_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Shown while the register has no network. Sales stay on the device.
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(deviceSessionProvider);
    if (!session.ready || session.online) return const SizedBox.shrink();
    final waiting = session.outboxIds.length;
    final message = waiting == 0
        ? 'You are offline. Sales stay on this device and sync when the connection returns.'
        : waiting == 1
            ? 'You are offline. 1 sale is saved on this device.'
            : 'You are offline. $waiting sales are saved on this device.';
    return Material(
      color: AppColors.amber,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.wifi_off, size: 18, color: AppColors.nearBlack),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: AppTextStyles.body(color: AppColors.nearBlack)
                    .copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
