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
        title: const Text('Appareils connectés'),
        titleTextStyle: AppTextStyles.h3(color: ink),
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.white,
        foregroundColor: ink,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppConstants.spacing24),
        children: [
          Text(
            'Une nouvelle caisse saisit un code une seule fois. Ensuite elle s\'ouvre avec un code PIN, même hors ligne.',
            style: AppTextStyles.body(color: muted),
          ),
          const SizedBox(height: 16),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Cet appareil', style: AppTextStyles.h3(color: AppColors.primaryBlue)),
                const SizedBox(height: 8),
                Text(
                  session.isPaired
                      ? 'Connecté à ${session.pairing!.locationName}.'
                      : 'Cette caisse n\'est pas encore connectée.',
                  style: AppTextStyles.body(color: ink),
                ),
                if (session.offlineExpiringSoon) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Reconnectez-vous bientôt. Le code PIN hors ligne s\'arrête dans ${session.pairing!.daysLeft(DateTime.now())} jours.',
                    style: AppTextStyles.body(color: AppColors.boldRed),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppButton(
            label: 'Créer un code appareil',
            icon: Icons.add,
            onPressed: () async {
              final invite = await ref.read(deviceSessionProvider.notifier).createInvite();
              if (invite == null || !context.mounted) return;
              await showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Code appareil'),
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
                        'Valable 24 heures. Saisissez-le sur la nouvelle caisse.',
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
                      child: const Text('Copier'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Terminé'),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          Text('Codes actifs', style: AppTextStyles.h2(color: ink)),
          const SizedBox(height: 8),
          if (live.isEmpty)
            Text('Aucun code actif.', style: AppTextStyles.body(color: muted))
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
                        'Expire aujourd\'hui',
                        style: AppTextStyles.caption(color: muted),
                      ),
                    ],
                  ),
                ),
              ),
          if (session.isPaired) ...[
            const SizedBox(height: 24),
            AppButton(
              label: 'Oublier cet appareil',
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
