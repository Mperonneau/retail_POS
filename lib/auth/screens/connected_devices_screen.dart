import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/navigation/app_routes.dart';
import '../../core/providers/device_session_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/constants.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_card.dart';

/// Creates the one-time codes another register uses to connect.
class ConnectedDevicesScreen extends ConsumerWidget {
  const ConnectedDevicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final session = ref.watch(deviceSessionProvider);
    final ink = isDark ? AppColors.warmWhite : AppColors.nearBlack;
    final muted = isDark ? AppColors.coolGray : AppColors.darkGray;
    final live = session.invites.where((invite) => invite.isLive(DateTime.now()));
    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.warmOffWhite,
      appBar: AppBar(
        title: const Text('Connected devices'),
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.white,
        foregroundColor: ink,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppConstants.spacing24),
        children: [
          Text(
            'A new register enters a code once. After that it opens with a staff PIN, even offline.',
            style: AppTextStyles.body(color: muted),
          ),
          const SizedBox(height: 16),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('This device', style: AppTextStyles.h3(color: AppColors.primaryBlue)),
                const SizedBox(height: 8),
                Text(
                  session.isPaired
                      ? 'Connected to ${session.pairing!.locationName}.'
                      : 'This register is not connected yet.',
                  style: AppTextStyles.body(color: ink),
                ),
                if (session.offlineExpiringSoon) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Connect to the internet soon. Offline PIN stops in ${session.pairing!.daysLeft(DateTime.now())} days.',
                    style: AppTextStyles.body(color: AppColors.boldRed),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppButton(
            label: 'Create a device code',
            icon: Icons.add,
            onPressed: () async {
              final invite = await ref.read(deviceSessionProvider.notifier).createInvite();
              if (invite == null || !context.mounted) return;
              await showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Device code'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        invite.code,
                        style: AppTextStyles.h1(color: AppColors.primaryBlue),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Valid for 24 hours. Enter it on the new register.',
                        style: AppTextStyles.body(color: muted),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: invite.code));
                        Navigator.pop(context);
                      },
                      child: const Text('Copy'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Done'),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          Text('Active codes', style: AppTextStyles.h2(color: ink)),
          const SizedBox(height: 8),
          if (live.isEmpty)
            Text('No active codes.', style: AppTextStyles.body(color: muted))
          else
            for (final invite in live)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AppCard(
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          invite.code,
                          style: AppTextStyles.h3(color: ink),
                        ),
                      ),
                      Text(
                        'Expires today',
                        style: AppTextStyles.caption(color: muted),
                      ),
                    ],
                  ),
                ),
              ),
          if (session.isPaired) ...[
            const SizedBox(height: 24),
            AppButton(
              label: 'Forget this device',
              variant: AppButtonVariant.secondary,
              onPressed: () async {
                await ref.read(deviceSessionProvider.notifier).unpairThisDevice();
                if (context.mounted) context.go(AppRoutes.pairDevice);
              },
            ),
          ],
        ],
      ),
    );
  }
}
