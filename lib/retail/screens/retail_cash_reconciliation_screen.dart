import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/cash_control.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/providers/staff_session_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/constants.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/input_formatters.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_card.dart';
import '../cash/cash_report_pdf.dart';

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

  Future<void> _printSession(CashControlState state) {
    return showCashPdfActions(
      context,
      filename: 'rapport-caisse.pdf',
      title: 'Rapport de caisse',
      build: () => buildSessionReportPdf(
        CashReportFigures.fromState(state, shopName: 'Boutique Soleil'),
      ),
    );
  }

  Future<void> _printClosure(SessionSummary summary) {
    return showCashPdfActions(
      context,
      filename: 'cloture-caisse.pdf',
      title: 'Clôture de caisse',
      build: () => buildClosurePdf(
        shopName: 'Boutique Soleil',
        summary: summary,
        countedHtg: summary.finalBalanceHtg,
        countedUsd: summary.finalBalanceUsd,
        note: summary.session.closingNote ?? '',
      ),
    );
  }

  Future<void> _close(CashControlState state) async {
    final countedHtg = double.tryParse(_actualCtrl.text);
    final countedUsd = double.tryParse(_actualUsdCtrl.text);
    if (countedHtg == null || countedUsd == null) return;
    final note = _noteCtrl.text.trim();
    final me = ref.read(staffSessionProvider);
    ref.read(retailCashSessionProvider.notifier).closeSession(
          note: note,
          closedBy: me?.employeeName ?? 'Gérant',
          countedHtg: countedHtg,
          countedUsd: countedUsd,
        );
    setState(() => _confirmed = true);
    final summary =
        ref.read(retailCashSessionProvider).sessionHistory.firstOrNull;
    if (summary != null && mounted) {
      await _printClosure(summary);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(retailCashSessionProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final session = state.activeSession;

    if (_confirmed) {
      final summary = state.sessionHistory.firstOrNull;
      if (summary != null) {
        return _ConfirmedView(
          isDark: isDark,
          summary: summary,
          onPrint: () => _printClosure(summary),
        );
      }
    }

    if (session == null || session.status != CashSessionStatus.open) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: Text('Aucune session ouverte.', style: AppTextStyles.body()),
        ),
      );
    }

    final countedHtg = double.tryParse(_actualCtrl.text);
    final countedUsd = double.tryParse(_actualUsdCtrl.text);
    final expectedHtg = state.drawerExpectedHtg;
    final expectedUsd = state.drawerExpectedUsd;
    final diffHtg = (countedHtg ?? 0) - expectedHtg;
    final diffUsd = (countedUsd ?? 0) - expectedUsd;
    final canClose = countedHtg != null && countedUsd != null;

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
                Text(
                  'Fermer et rapprocher',
                  style: AppTextStyles.h1(
                    color: isDark ? AppColors.warmWhite : AppColors.primaryBlue,
                  ),
                ),
                const SizedBox(height: AppConstants.spacing8),
                Text(
                  'Comptez les gourdes et les dollars du tiroir. Chaque devise reste dans sa devise. La carte est en dollars et n\'entre pas dans ce comptage.',
                  style: AppTextStyles.body(
                    color: isDark ? AppColors.coolGray : AppColors.darkGray,
                  ),
                ),
                const SizedBox(height: AppConstants.spacing24),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _AttenduCard(
                          label: 'Attendu HTG',
                          amount: CurrencyFormatter.local(context, expectedHtg),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _AttenduCard(
                          label: 'Attendu USD',
                          amount: CurrencyFormatter.usd(expectedUsd),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppConstants.spacing16),
                AppCard(
                  child: Column(
                    children: [
                      _RecRow(
                        label: 'Ouverture HTG',
                        value: CurrencyFormatter.local(
                            context, session.openingBalanceHtg),
                      ),
                      _RecRow(
                        label: 'Ouverture USD',
                        value: CurrencyFormatter.usd(session.openingBalanceUsd),
                      ),
                      const Divider(height: 16),
                      _RecRow(
                        label: 'Entrées HTG',
                        value:
                            '+ ${CurrencyFormatter.local(context, state.drawerCashInHtg)}',
                        valueColor: AppColors.deepGreen,
                      ),
                      _RecRow(
                        label: 'Entrées USD',
                        value: '+ ${CurrencyFormatter.usd(state.drawerCashInUsd)}',
                        valueColor: AppColors.deepGreen,
                      ),
                      const SizedBox(height: 4),
                      _RecRow(
                        label: 'Sorties HTG',
                        value:
                            '- ${CurrencyFormatter.local(context, state.drawerCashOutHtg)}',
                        valueColor: AppColors.boldRed,
                      ),
                      _RecRow(
                        label: 'Sorties USD',
                        value: '- ${CurrencyFormatter.usd(state.drawerCashOutUsd)}',
                        valueColor: AppColors.boldRed,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppConstants.spacing24),
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
                          BorderRadius.circular(AppConstants.radiusInput),
                    ),
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
                    labelText: 'Espèces comptées (USD) *',
                    prefixText: '\$ ',
                    border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(AppConstants.radiusInput),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: AppConstants.spacing12),
                TextField(
                  controller: _noteCtrl,
                  decoration: InputDecoration(
                    labelText: 'Notes de clôture — facultatif',
                    border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(AppConstants.radiusInput),
                    ),
                  ),
                  maxLines: 2,
                ),
                if (countedHtg != null || countedUsd != null) ...[
                  const SizedBox(height: AppConstants.spacing16),
                  _DiffBox(
                    showHtg: countedHtg != null,
                    showUsd: countedUsd != null,
                    diffHtg: diffHtg,
                    diffUsd: diffUsd,
                  ),
                ],
                const SizedBox(height: AppConstants.spacing24),
                AppButton(
                  label: 'Fermer le tiroir',
                  onPressed: canClose ? () => _close(state) : null,
                  icon: Icons.lock_outlined,
                ),
                const SizedBox(height: AppConstants.spacing8),
                AppButton(
                  label: 'Imprimer ou télécharger le rapport',
                  onPressed: () => _printSession(state),
                  icon: Icons.print_outlined,
                  variant: AppButtonVariant.secondary,
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

class _AttenduCard extends StatelessWidget {
  final String label;
  final String amount;

  const _AttenduCard({required this.label, required this.amount});

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.topLeft,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.amber.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppConstants.radiusCard),
        border: Border.all(
          color: AppColors.amber.withValues(alpha: 0.55),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTextStyles.caption(color: AppColors.amber)
                .copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            amount,
            style: AppTextStyles.h3(color: AppColors.amber)
                .copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _DiffBox extends StatelessWidget {
  final bool showHtg;
  final bool showUsd;
  final double diffHtg;
  final double diffUsd;

  const _DiffBox({
    required this.showHtg,
    required this.showUsd,
    required this.diffHtg,
    required this.diffUsd,
  });

  @override
  Widget build(BuildContext context) {
    final htgOk = !showHtg || diffHtg.abs() < 1;
    final usdOk = !showUsd || diffUsd.abs() < 0.01;
    final ok = htgOk && usdOk;
    final color = ok ? AppColors.deepGreen : AppColors.boldRed;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.spacing16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppConstants.radiusCard),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showHtg)
            Text(
              _line('HTG', diffHtg, CurrencyFormatter.local(context, diffHtg.abs()), 1),
              style: AppTextStyles.body(color: color)
                  .copyWith(fontWeight: FontWeight.w700),
            ),
          if (showUsd)
            Text(
              _line('USD', diffUsd, CurrencyFormatter.usd(diffUsd.abs()), 0.01),
              style: AppTextStyles.body(color: color)
                  .copyWith(fontWeight: FontWeight.w700),
            ),
        ],
      ),
    );
  }

  String _line(String code, double diff, String amount, double tolerance) {
    if (diff.abs() < tolerance) return '$code · Juste';
    if (diff > 0) return '$code · Excédent de $amount';
    return '$code · Manque de $amount';
  }
}

class _RecRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool bold;

  const _RecRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: AppTextStyles.body().copyWith(
              fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
          Text(
            value,
            style: AppTextStyles.body(
              color: valueColor ??
                  (isDark ? AppColors.warmWhite : AppColors.nearBlack),
            ).copyWith(fontWeight: bold ? FontWeight.w700 : FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _ConfirmedView extends StatelessWidget {
  final bool isDark;
  final SessionSummary summary;
  final VoidCallback onPrint;

  const _ConfirmedView({
    required this.isDark,
    required this.summary,
    required this.onPrint,
  });

  @override
  Widget build(BuildContext context) {
    final expectedHtg = summary.expectedHtg;
    final expectedUsd = summary.expectedUsd;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppConstants.spacing24),
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
              Text(
                'Tiroir fermé',
                style: AppTextStyles.h1(
                  color: isDark ? AppColors.warmWhite : AppColors.primaryBlue,
                ),
              ),
              const SizedBox(height: AppConstants.spacing8),
              Text(
                'Session rapprochée et fermée. Les gourdes et les dollars restent séparés.',
                style: AppTextStyles.body(
                  color: isDark ? AppColors.coolGray : AppColors.darkGray,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppConstants.spacing24),
              SizedBox(
                width: 360,
                child: Row(
                  children: [
                    Expanded(
                      child: _AttenduCard(
                        label: 'Attendu HTG',
                        amount: CurrencyFormatter.local(context, expectedHtg),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _AttenduCard(
                        label: 'Attendu USD',
                        amount: CurrencyFormatter.usd(expectedUsd),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppConstants.spacing16),
              SizedBox(
                width: 360,
                child: AppCard(
                  child: Column(
                    children: [
                      _RecRow(
                        label: 'Compté HTG',
                        value: CurrencyFormatter.local(
                            context, summary.finalBalanceHtg),
                        bold: true,
                      ),
                      _RecRow(
                        label: 'Compté USD',
                        value: CurrencyFormatter.usd(summary.finalBalanceUsd),
                        bold: true,
                      ),
                      const Divider(height: 16),
                      _RecRow(
                        label: 'Écart HTG',
                        value: CurrencyFormatter.local(
                            context, summary.overShortHtg),
                        valueColor: summary.overShortHtg.abs() < 1
                            ? AppColors.deepGreen
                            : AppColors.boldRed,
                      ),
                      _RecRow(
                        label: 'Écart USD',
                        value: CurrencyFormatter.usd(summary.overShortUsd),
                        valueColor: summary.overShortUsd.abs() < 0.01
                            ? AppColors.deepGreen
                            : AppColors.boldRed,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppConstants.spacing24),
              SizedBox(
                width: 360,
                child: AppButton(
                  label: 'Imprimer ou télécharger la clôture',
                  onPressed: onPrint,
                  icon: Icons.print_outlined,
                  variant: AppButtonVariant.secondary,
                ),
              ),
              const SizedBox(height: AppConstants.spacing8),
              SizedBox(
                width: 360,
                child: AppButton(
                  label: 'Retour au tableau de bord',
                  onPressed: () => context.go(AppRoutes.retailDashboard),
                  icon: Icons.dashboard_outlined,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
