import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../navigation/app_routes.dart';
import '../providers/device_session_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Shown while the register has no network, or sales are still waiting to send.
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(deviceSessionProvider);
    final waiting = session.outboxIds.length;
    if (!session.ready || (session.online && waiting == 0)) {
      return const SizedBox.shrink();
    }
    final message = !session.online
        ? (waiting == 0
            ? 'Vous êtes hors ligne. Les ventes restent sur cet appareil et se synchronisent au retour de la connexion.'
            : waiting == 1
                ? 'Vous êtes hors ligne. 1 vente est enregistrée sur cet appareil.'
                : 'Vous êtes hors ligne. $waiting ventes sont enregistrées sur cet appareil.')
        : (waiting == 1
            ? 'Connexion rétablie. 1 opération attend d\'être envoyée.'
            : 'Connexion rétablie. $waiting opérations attendent d\'être envoyées.');
    return Material(
      color: AppColors.amber,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              session.online ? Icons.cloud_upload_outlined : Icons.wifi_off,
              size: 18,
              color: AppColors.nearBlack,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: AppTextStyles.body(color: AppColors.nearBlack)
                    .copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: AppColors.nearBlack,
                backgroundColor: AppColors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => context.push(AppRoutes.sync),
              child: Text(
                'Synchronisation',
                style: AppTextStyles.button(color: AppColors.nearBlack).copyWith(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
