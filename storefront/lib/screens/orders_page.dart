import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:retail_pos/core/theme/app_colors.dart';
import 'package:retail_pos/core/theme/app_text_styles.dart';
import 'package:retail_pos/core/utils/constants.dart';

import '../api.dart';
import '../money.dart';
import '../session.dart';
import '../widgets.dart';

class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key});

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  List<OrderSummary>? _rows;
  String? _error;
  String _filter = 'tous';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final rows = await Session.instance.orders();
      if (!mounted) return;
      setState(() => _rows = rows);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _rows = const [];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
        children: [
          Text('Mes commandes', style: AppTextStyles.h1(color: AppColors.nearBlack)),
          const SizedBox(height: 4),
          Text(
            Session.instance.isLoggedIn
                ? 'Devis et commandes de ${Session.instance.name}.'
                : 'Les demandes passées sur cet appareil. Un compte les retrouve aussi ailleurs.',
            style: AppTextStyles.body(color: AppColors.darkGray),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: [
              for (final item in const [('tous', 'Tout'), ('commande', 'Commandes'), ('devis', 'Devis')])
                ChoiceChip(
                  label: Text(item.$2),
                  selected: _filter == item.$1,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _filter = item.$1),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (rows == null)
            const Padding(padding: EdgeInsets.only(top: 48), child: LoadingView())
          else if (_error != null && rows.isEmpty)
            MessageView(
              icon: Icons.wifi_off_rounded,
              title: 'Chargement impossible',
              message: _error!,
              actionLabel: 'Réessayer',
              onAction: _load,
            )
          else if (rows.where((row) => _filter == 'tous' || row.kind == _filter).isEmpty)
            SizedBox(height: 360, child: MessageView(
              icon: Icons.receipt_long_outlined,
              title: 'Aucune demande',
              message: Session.instance.isLoggedIn
                  ? 'Vos devis et commandes apparaîtront ici.'
                  : 'Commandez en invité, ou connectez-vous pour retrouver vos demandes.',
              actionLabel: Session.instance.isLoggedIn ? null : 'Se connecter',
              onAction: Session.instance.isLoggedIn ? null : () => context.push('/login'),
            ))
          else
            for (final row in rows.where((row) => _filter == 'tous' || row.kind == _filter))
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _OrderCard(row: row),
              ),
        ],
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.row});

  final OrderSummary row;

  @override
  Widget build(BuildContext context) {
    final when = DateFormat('d MMM yyyy • HH:mm', 'fr').format(
      DateTime.fromMillisecondsSinceEpoch(row.createdAt * 1000),
    );
    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(AppConstants.radiusCard),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppConstants.radiusCard),
        onTap: () => context.push('/r/${row.id}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Pill(
                    label: row.isQuote ? 'Devis' : 'Commande',
                    color: row.isQuote ? AppColors.primaryBlue : AppColors.deepGreen,
                  ),
                  const SizedBox(width: 8),
                  Pill(
                    label: row.isPaid ? 'Payé' : 'En attente',
                    color: row.isPaid ? AppColors.deepGreen : AppColors.amber,
                  ),
                  const Spacer(),
                  Text(row.number, style: AppTextStyles.caption()),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                row.shopName.isEmpty ? 'Boutique' : row.shopName,
                style: AppTextStyles.h2(color: AppColors.nearBlack).copyWith(fontSize: 16),
              ),
              const SizedBox(height: 2),
              Text(when, style: AppTextStyles.caption()),
              const SizedBox(height: 8),
              Text(
                Money.usdFromHtg(row.totalHtg, row.usdRate),
                style: AppTextStyles.price(color: AppColors.nearBlack).copyWith(fontSize: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
