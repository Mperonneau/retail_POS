import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../mock/mock_retail_orders.dart';
import '../../models/order_history.dart';
import '../../models/pending_operation.dart';
import '../../models/retail_order.dart';
import '../../providers/device_session_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../utils/constants.dart';
import '../../utils/currency_formatter.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../order_history/order_history_screen.dart';
import '../../theme/app_icons.dart';

/// Changes waiting on this device, and the button that sends them once online.
class SyncScreen extends ConsumerWidget {
  const SyncScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final session = ref.watch(deviceSessionProvider);
    final orders = ref.watch(retailOrdersProvider);
    final ink = isDark ? AppColors.warmWhite : AppColors.nearBlack;
    final muted = isDark ? AppColors.coolGray : AppColors.darkGray;
    final waiting = session.pending.length;
    final offline = !session.online;
    final dot = offline || waiting > 0 ? AppColors.amber : AppColors.deepGreen;

    final String title;
    final String body;
    if (waiting > 0 && offline) {
      title = waiting == 1
          ? '1 opération en attente'
          : '$waiting opérations en attente';
      body =
          'Envoi dès le retour de la connexion. Vous pouvez continuer à encaisser.';
    } else if (waiting > 0) {
      title = waiting == 1
          ? '1 opération en attente'
          : '$waiting opérations en attente';
      body = 'La connexion est rétablie. Envoyez-les maintenant.';
    } else if (offline) {
      title = 'Hors ligne';
      body =
          'Vos changements restent sur cet appareil. Ils partiront au retour de la connexion.';
    } else {
      title = 'En ligne';
      body = 'Tout est envoyé.';
    }

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.warmOffWhite,
      appBar: AppBar(
        title: const Text('Synchronisation'),
        titleTextStyle: AppTextStyles.h3(color: ink),
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.white,
        foregroundColor: ink,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppConstants.spacing24),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(title, style: AppTextStyles.h2(color: ink)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(body, style: AppTextStyles.body(color: muted)),
                if (session.lastSyncAt != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Dernière synchronisation · ${_stamp(session.lastSyncAt!)}',
                    style: AppTextStyles.caption(color: muted),
                  ),
                ],
                if (waiting > 0) ...[
                  const SizedBox(height: 16),
                  AppButton(
                    label: 'Synchroniser',
                    icon: AppIcons.sync,
                    isLoading: session.syncing,
                    onPressed: offline || session.syncing
                        ? null
                        : () => ref.read(deviceSessionProvider.notifier).syncNow(),
                  ),
                  if (offline) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Indisponible hors ligne',
                      style: AppTextStyles.caption(color: muted),
                    ),
                  ],
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text('En attente', style: AppTextStyles.h3(color: ink)),
          const SizedBox(height: 4),
          Text('Sur cet appareil', style: AppTextStyles.caption(color: muted)),
          const SizedBox(height: 12),
          if (waiting == 0)
            AppCard(
              child: Text(
                'Rien à envoyer pour l\'instant.',
                style: AppTextStyles.body(color: muted),
              ),
            )
          else
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < session.pending.length; i++) ...[
                    if (i > 0)
                      Divider(
                        height: 1,
                        color: isDark ? AppColors.darkBorder : const Color(0xFFE5E5EA),
                      ),
                    _WaitingRow(
                      operation: session.pending[i],
                      order: _orderFor(orders, session.pending[i].orderId),
                      ink: ink,
                      muted: muted,
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  static RetailOrder? _orderFor(List<RetailOrder> orders, String? id) {
    if (id == null) return null;
    for (final order in orders) {
      if (order.id == id) return order;
    }
    return null;
  }

  static String _stamp(DateTime value) =>
      DateFormat('d MMM y · HH:mm', 'fr').format(value.toLocal());
}

class _WaitingRow extends StatelessWidget {
  const _WaitingRow({
    required this.operation,
    required this.order,
    required this.ink,
    required this.muted,
  });

  final PendingOperation operation;
  final RetailOrder? order;
  final Color ink;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final sale = order;
    final String detail;
    if (operation.kind == PendingOperationKind.sale && sale != null) {
      final who = (sale.clientName ?? '').trim().isEmpty
          ? 'Client de passage'
          : sale.clientName!.trim();
      detail =
          '$who · ${sale.paymentMethod.label} · ${CurrencyFormatter.local(context, sale.totalHtg)}';
    } else {
      detail = [
        if (operation.detail.isNotEmpty) operation.detail,
        if (operation.amountHtg != null)
          CurrencyFormatter.local(context, operation.amountHtg!),
      ].join(' · ');
    }
    final when = DateFormat('d MMM · HH:mm', 'fr').format(operation.createdAt.toLocal());

    return InkWell(
      onTap: sale == null
          ? null
          : () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => RetailOrderDetailPage(order: sale),
                ),
              ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(operation.kind.icon, size: 22, color: ink),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    operation.kind.label,
                    style: AppTextStyles.caption(color: muted),
                  ),
                  Text(
                    operation.title,
                    style: AppTextStyles.body(color: ink)
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (detail.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(detail, style: AppTextStyles.caption(color: muted)),
                  ],
                  const SizedBox(height: 2),
                  Text(when, style: AppTextStyles.caption(color: muted)),
                  const SizedBox(height: 4),
                  Text(
                    'Pas encore envoyé',
                    style: AppTextStyles.caption(color: AppColors.amber),
                  ),
                ],
              ),
            ),
            if (sale != null)
              Icon(Icons.chevron_right, size: 22, color: muted),
          ],
        ),
      ),
    );
  }
}
