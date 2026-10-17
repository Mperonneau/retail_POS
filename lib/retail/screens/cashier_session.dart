import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/constants.dart';
import '../../core/utils/input_formatters.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_card.dart';

class CashierSession extends StatefulWidget {
  const CashierSession({super.key});

  @override
  State<CashierSession> createState() => _CashierSessionState();
}

class _CashierSessionState extends State<CashierSession> {
  bool _sessionOpen = true;
  double _countedCash = 0;
  final _expectedCash = 15800.0;
  final _totalSales = 48200.0;
  final _startingCash = 5000.0;

  double get _variance => _countedCash - _expectedCash;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppConstants.spacing24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Session de caisse', style: AppTextStyles.h1(
              color: isDark ? AppColors.warmWhite : AppColors.primaryBlue,
            )),
            const SizedBox(height: AppConstants.spacing4),
            Text('Roseline · Session ouverte à 08:00', style: AppTextStyles.caption()),
            const SizedBox(height: AppConstants.spacing24),

            // Session status banner
            Container(
              padding: const EdgeInsets.all(AppConstants.spacing16),
              decoration: BoxDecoration(
                color: _sessionOpen
                    ? AppColors.deepGreen.withValues(alpha: 0.1)
                    : AppColors.amber.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppConstants.radiusCard),
                border: Border.all(color: _sessionOpen ? AppColors.deepGreen.withValues(alpha: 0.3) : AppColors.amber.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(_sessionOpen ? Icons.lock_open_outlined : Icons.lock_outlined,
                      color: _sessionOpen ? AppColors.deepGreen : AppColors.amber),
                  const SizedBox(width: 12),
                  Expanded(child: Text(
                    _sessionOpen ? 'La session est OUVERTE' : 'Session FERMÉE',
                    style: AppTextStyles.body(color: _sessionOpen ? AppColors.deepGreen : AppColors.amber),
                  )),
                  Text(_sessionOpen ? 'Aujourd\'hui' : 'Terminée à 18:00',
                      style: AppTextStyles.caption()),
                ],
              ),
            ),
            const SizedBox(height: AppConstants.spacing24),

            // Summary cards
            Row(
              children: [
                Expanded(child: AppCard(child: Column(children: [
                  Text("Fond de caisse", style: AppTextStyles.caption()),
                  const SizedBox(height: 4),
                  Text(CurrencyFormatter.local(context, _startingCash), style: AppTextStyles.price().copyWith(fontSize: 14)),
                ]))),
                const SizedBox(width: 12),
                Expanded(child: AppCard(child: Column(children: [
                  Text("Ventes totales", style: AppTextStyles.caption()),
                  const SizedBox(height: 4),
                  Text(CurrencyFormatter.local(context, _totalSales), style: AppTextStyles.price(color: AppColors.deepGreen).copyWith(fontSize: 14)),
                ]))),
                const SizedBox(width: 12),
                Expanded(child: AppCard(child: Column(children: [
                  Text("Espèces attendues", style: AppTextStyles.caption()),
                  const SizedBox(height: 4),
                  Text(CurrencyFormatter.local(context, _expectedCash), style: AppTextStyles.price(color: isDark ? AppColors.skyBlue : AppColors.primaryBlue).copyWith(fontSize: 14)),
                ]))),
              ],
            ),
            const SizedBox(height: AppConstants.spacing24),

            // Payment breakdown
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Ventes par moyen de paiement', style: AppTextStyles.h3()),
                  const SizedBox(height: AppConstants.spacing16),
                  _PayMethodRow(label: 'MonCash', amount: 28400, color: isDark ? AppColors.skyBlue : AppColors.primaryBlue),
                  const SizedBox(height: 8),
                  _PayMethodRow(label: 'Espèces HTG', amount: 15800, color: AppColors.deepGreen),
                  const SizedBox(height: 8),
                  _PayMethodRow(label: 'Carte (Stripe)', amount: 4000, color: AppColors.statusMaintenance),
                ],
              ),
            ),

            if (_sessionOpen) ...[
              const SizedBox(height: AppConstants.spacing24),
              Text('Fermer la session', style: AppTextStyles.h2(
                color: isDark ? AppColors.warmWhite : AppColors.primaryBlue,
              )),
              const SizedBox(height: AppConstants.spacing16),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Comptez le tiroir-caisse', style: AppTextStyles.body()),
                    const SizedBox(height: AppConstants.spacing12),
                    TextField(
                      onChanged: (v) => setState(() => _countedCash = double.tryParse(v) ?? 0),
                      decoration: InputDecoration(
                        labelText: 'Espèces réelles dans le tiroir (HTG)',
                        prefixText: 'HTG ',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppConstants.radiusInput)),
                      ),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: InputFormatters.decimalAmount,
                    ),
                    if (_countedCash > 0) ...[
                      const SizedBox(height: AppConstants.spacing16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Attendu :', style: AppTextStyles.body()),
                          Text(CurrencyFormatter.local(context, _expectedCash), style: AppTextStyles.body()),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Compté :', style: AppTextStyles.body()),
                          Text(CurrencyFormatter.local(context, _countedCash), style: AppTextStyles.body()),
                        ],
                      ),
                      const Divider(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Écart :', style: AppTextStyles.body().copyWith(fontWeight: FontWeight.w700)),
                          Text(
                            '${_variance >= 0 ? '+' : ''}${CurrencyFormatter.local(context, _variance)}',
                            style: AppTextStyles.price(
                              color: _variance.abs() < 100 ? AppColors.deepGreen : AppColors.boldRed,
                            ).copyWith(fontSize: 14),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppConstants.spacing16),
              AppButton(
                label: 'Fermer la session et envoyer le rapport',
                onPressed: () => setState(() => _sessionOpen = false),
                variant: AppButtonVariant.danger,
                icon: Icons.lock_outlined,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PayMethodRow extends StatelessWidget {
  final String label;
  final double amount;
  final Color color;

  const _PayMethodRow({required this.label, required this.amount, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: AppTextStyles.body())),
        Text(CurrencyFormatter.local(context, amount), style: AppTextStyles.body().copyWith(fontWeight: FontWeight.w600)),
      ],
    );
  }
}
