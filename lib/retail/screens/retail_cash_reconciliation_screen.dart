import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/cash_control.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/constants.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/input_formatters.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_card.dart';

class RetailCashReconciliationScreen extends ConsumerStatefulWidget {
  const RetailCashReconciliationScreen({super.key});

  @override
  ConsumerState<RetailCashReconciliationScreen> createState() =>
      _RetailCashReconciliationScreenState();
}

class _RetailCashReconciliationScreenState
    extends ConsumerState<RetailCashReconciliationScreen> {
  final _actualCtrl = TextEditingController();
  final _actualUsdCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _confirmed = false;

  @override
  void dispose() {
    _actualCtrl.dispose();
    _actualUsdCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  void _close(CashControlState state) {
    ref
        .read(retailCashSessionProvider.notifier)
        .closeSession(note: _noteCtrl.text.trim());
    setState(() => _confirmed = true);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(retailCashSessionProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final session = state.activeSession;

    if (session == null) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: Text('Aucune session active.', style: AppTextStyles.body()),
        ),
      );
    }

    if (_confirmed) {
      return _ConfirmedView(isDark: isDark, state: state);
    }

    final actualHtg = double.tryParse(_actualCtrl.text) ?? 0;
    final diff = actualHtg - state.expectedBalance;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppConstants.spacing24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Fermer et rapprocher',
                    style: AppTextStyles.h1(
                        color: isDark
                            ? AppColors.warmWhite
                            : AppColors.primaryBlue)),
                const SizedBox(height: AppConstants.spacing8),
                Text(
                  'Comptez l\'argent du tiroir et saisissez le montant réel ci-dessous.',
                  style: AppTextStyles.body(
                      color: isDark ? AppColors.coolGray : AppColors.darkGray),
                ),
                const SizedBox(height: AppConstants.spacing24),

                // Session summary
                AppCard(
                  child: Column(
                    children: [
                      _RecRow(
                        label: 'Solde d\'ouverture',
                        value: CurrencyFormatter.local(context, session.openingBalanceHtg),
                        isDark: isDark,
                      ),
                      const Divider(height: 16),
                      _RecRow(
                        label: 'Total des entrées',
                        value: '+ ${CurrencyFormatter.local(context, state.totalIn)}',
                        isDark: isDark,
                        valueColor: AppColors.deepGreen,
                      ),
                      const SizedBox(height: 4),
                      _RecRow(
                        label: 'Total des sorties',
                        value: '- ${CurrencyFormatter.local(context, state.totalOut)}',
                        isDark: isDark,
                        valueColor: AppColors.boldRed,
                      ),
                      const Divider(height: 16),
                      _RecRow(
                        label: 'Attendu dans le tiroir',
                        value: CurrencyFormatter.local(context, state.expectedBalance),
                        isDark: isDark,
                        bold: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppConstants.spacing24),

                // Actual count entry
                TextField(
                  controller: _actualCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: InputFormatters.decimalAmount,
                  decoration: InputDecoration(
                    labelText: 'Espèces comptées (HTG) *',
                    prefixText: 'HTG ',
                    border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppConstants.radiusInput)),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: AppConstants.spacing12),
                TextField(
                  controller: _actualUsdCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: InputFormatters.decimalAmount,
                  decoration: InputDecoration(
                    labelText: 'Espèces comptées (USD) — facultatif',
                    prefixText: '\$ ',
                    border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppConstants.radiusInput)),
                  ),
                ),
                const SizedBox(height: AppConstants.spacing12),
                TextField(
                  controller: _noteCtrl,
                  decoration: InputDecoration(
                    labelText: 'Notes de clôture — facultatif',
                    border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppConstants.radiusInput)),
                  ),
                  maxLines: 2,
                ),

                // Over / Short indicator
                if (_actualCtrl.text.isNotEmpty) ...[
                  const SizedBox(height: AppConstants.spacing16),
                  Container(
                    padding: const EdgeInsets.all(AppConstants.spacing16),
                    decoration: BoxDecoration(
                      color: diff == 0
                          ? AppColors.deepGreen.withValues(alpha: 0.08)
                          : diff > 0
                              ? AppColors.deepGreen.withValues(alpha: 0.08)
                              : AppColors.boldRed.withValues(alpha: 0.08),
                      borderRadius:
                          BorderRadius.circular(AppConstants.radiusCard),
                      border: Border.all(
                          color: diff == 0
                              ? AppColors.deepGreen.withValues(alpha: 0.35)
                              : diff > 0
                                  ? AppColors.deepGreen.withValues(alpha: 0.35)
                                  : AppColors.boldRed.withValues(alpha: 0.35)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          diff == 0
                              ? Icons.check_circle_outline
                              : diff > 0
                                  ? Icons.arrow_upward_rounded
                                  : Icons.arrow_downward_rounded,
                          color: diff >= 0
                              ? AppColors.deepGreen
                              : AppColors.boldRed,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                diff == 0
                                    ? 'Balanced'
                                    : diff > 0
                                        ? 'Excédent de ${CurrencyFormatter.local(context, diff.abs())}'
                                        : 'Manque de ${CurrencyFormatter.local(context, diff.abs())}',
                                style: AppTextStyles.body(
                                    color: diff >= 0
                                        ? AppColors.deepGreen
                                        : AppColors.boldRed),
                              ),
                              if (diff != 0)
                                Text(
                                  'Écart avec le solde attendu',
                                  style: AppTextStyles.caption(),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: AppConstants.spacing24),
                AppButton(
                  label: 'Fermer le tiroir',
                  onPressed:
                      _actualCtrl.text.isNotEmpty ? () => _close(state) : null,
                  icon: Icons.lock_outlined,
                ),
                const SizedBox(height: AppConstants.spacing8),
                AppButton(
                  label: 'Retour au contrôle de caisse',
                  onPressed: () => context.go(AppRoutes.retailCashControl),
                  variant: AppButtonVariant.ghost,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isDark;
  final Color? valueColor;
  final bool bold;

  const _RecRow({
    required this.label,
    required this.value,
    required this.isDark,
    this.valueColor,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: bold
                ? AppTextStyles.body(
                        color:
                            isDark ? AppColors.warmWhite : AppColors.nearBlack)
                    .copyWith(fontWeight: FontWeight.w700)
                : AppTextStyles.body()),
        Text(value,
            style: AppTextStyles.body(
                    color: valueColor ??
                        (isDark ? AppColors.warmWhite : AppColors.nearBlack))
                .copyWith(
                    fontWeight: bold ? FontWeight.w700 : FontWeight.w400)),
      ],
    );
  }
}

class _ConfirmedView extends StatelessWidget {
  final bool isDark;
  final CashControlState state;
  const _ConfirmedView({required this.isDark, required this.state});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.deepGreen.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.lock_outlined,
                  color: AppColors.deepGreen, size: 44),
            ),
            const SizedBox(height: AppConstants.spacing24),
            Text('Tiroir fermé',
                style: AppTextStyles.h1(
                    color:
                        isDark ? AppColors.warmWhite : AppColors.primaryBlue)),
            const SizedBox(height: AppConstants.spacing8),
            Text(
              'Session rapprochée et fermée.',
              style: AppTextStyles.body(
                  color: isDark ? AppColors.coolGray : AppColors.darkGray),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppConstants.spacing32),
            SizedBox(
              width: 320,
              child: AppCard(
                child: Column(
                  children: [
                    _RecRow(
                      label: 'Total des entrées',
                      value: CurrencyFormatter.local(context, state.totalIn),
                      isDark: isDark,
                      valueColor: AppColors.deepGreen,
                    ),
                    const SizedBox(height: 8),
                    _RecRow(
                      label: 'Total des sorties',
                      value: CurrencyFormatter.local(context, state.totalOut),
                      isDark: isDark,
                      valueColor: AppColors.boldRed,
                    ),
                    const Divider(height: 16),
                    _RecRow(
                      label: 'Espèces nettes',
                      value:
                          CurrencyFormatter.local(context, state.totalIn - state.totalOut),
                      isDark: isDark,
                      bold: true,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppConstants.spacing32),
            SizedBox(
              width: 320,
              child: AppButton(
                label: 'Retour au tableau de bord',
                onPressed: () => context.go(AppRoutes.retailDashboard),
                icon: Icons.dashboard_outlined,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
