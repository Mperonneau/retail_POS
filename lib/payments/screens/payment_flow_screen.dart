import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/constants.dart';
import '../../core/utils/input_formatters.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_card.dart';

class PaymentFlowScreen extends StatefulWidget {
  const PaymentFlowScreen({super.key});

  @override
  State<PaymentFlowScreen> createState() => _PaymentFlowScreenState();
}

class _PaymentFlowScreenState extends State<PaymentFlowScreen> {
  final _total = 12500.0;
  String _method = 'MonCash';
  bool _isProcessing = false;
  bool _isDone = false;

  final _methods = ['MonCash', 'Carte', 'Espèces', 'Split'];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.warmOffWhite,
      appBar: AppBar(
        title: Text('Paiement', style: AppTextStyles.h2(color: AppColors.white)),
        backgroundColor: AppColors.primaryBlue,
        foregroundColor: AppColors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(AppConstants.spacing24),
            child: _isDone ? _buildSuccess(context) : _buildForm(isDark),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Amount summary
        AppCard(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Montant dû', style: AppTextStyles.body()),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(CurrencyFormatter.local(context, _total), style: AppTextStyles.price()),
                  if (CurrencyFormatter.usdEquivalentOrNull(context, _total) != null)
                    Text(CurrencyFormatter.usdEquivalent(context, _total), style: AppTextStyles.caption()),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppConstants.spacing24),
        Text('Moyen de paiement', style: AppTextStyles.h2(
          color: isDark ? AppColors.warmWhite : AppColors.primaryBlue,
        )),
        const SizedBox(height: AppConstants.spacing12),
        // Method tabs
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          crossAxisSpacing: AppConstants.spacing8,
          mainAxisSpacing: AppConstants.spacing8,
          childAspectRatio: 2.5,
          physics: const NeverScrollableScrollPhysics(),
          children: _methods.map((m) {
            final isSelected = m == _method;
            final icon = m == 'MonCash'
                ? Icons.phone_android_outlined
                : m == 'Carte'
                    ? Icons.credit_card_outlined
                    : m == 'Espèces'
                        ? Icons.payments_outlined
                        : Icons.call_split_outlined;

            return GestureDetector(
              onTap: () => setState(() => _method = m),
              child: AnimatedContainer(
                duration: AppConstants.animFast,
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primaryBlue : (isDark ? AppColors.darkSurface : AppColors.white),
                  borderRadius: BorderRadius.circular(AppConstants.radiusButton),
                  border: Border.all(color: isSelected ? AppColors.primaryBlue : const Color(0xFFE0E0E0)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 18, color: isSelected ? AppColors.white : AppColors.darkGray),
                    const SizedBox(width: 6),
                    Text(m, style: AppTextStyles.caption(
                      color: isSelected ? AppColors.white : AppColors.darkGray,
                    )),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: AppConstants.spacing24),
        // Method-specific content
        Expanded(child: _buildMethodContent(isDark)),
        const SizedBox(height: AppConstants.spacing16),
        AppButton(
          label: _isProcessing ? 'Traitement...' : 'Confirmer le paiement',
          onPressed: _isProcessing ? null : _processPayment,
          isLoading: _isProcessing,
          icon: Icons.check_circle_outline,
        ),
      ],
    );
  }

  Widget _buildMethodContent(bool isDark) {
    switch (_method) {
      case 'MonCash':
        return AppCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.phone_android_outlined, size: 40, color: isDark ? AppColors.skyBlue : AppColors.primaryBlue),
              const SizedBox(height: 12),
              Text('Téléphone du client ou scan QR', style: AppTextStyles.body(), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              TextField(
                decoration: InputDecoration(
                  labelText: 'Téléphone du client (MonCash)',
                  prefixIcon: const Icon(Icons.phone_outlined, size: 18),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppConstants.radiusInput)),
                ),
                keyboardType: TextInputType.phone,
                inputFormatters: InputFormatters.phone,
              ),
              const SizedBox(height: 16),
              Container(
                width: 100, height: 100,
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkBackground : AppColors.lightBlue,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.qr_code_2_rounded, size: 52, color: isDark ? AppColors.skyBlue : AppColors.primaryBlue),
                  Text('QR', style: AppTextStyles.caption()),
                ]),
              ),
            ],
          ),
        );
      case 'Espèces':
        return AppCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.payments_outlined, size: 40, color: isDark ? AppColors.skyBlue : AppColors.primaryBlue),
              const SizedBox(height: 12),
              TextField(
                decoration: InputDecoration(
                  labelText: 'Espèces reçues (HTG)',
                  prefixText: 'HTG ',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppConstants.radiusInput)),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: InputFormatters.decimalAmount,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: [500, 1000, 2000, 5000, 10000, 20000].map((a) => ActionChip(
                  label: Text(CurrencyFormatter.compact(a.toDouble())),
                  onPressed: () {},
                )).toList(),
              ),
            ],
          ),
        );
      case 'Split':
        return AppCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Paiement partagé', style: AppTextStyles.h3()),
              const SizedBox(height: 12),
              Text('Combiner plusieurs moyens de paiement', style: AppTextStyles.body()),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: TextField(
                  decoration: InputDecoration(labelText: 'MonCash (HTG)', border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppConstants.radiusInput))),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: InputFormatters.decimalAmount,
                )),
                const SizedBox(width: 8),
                Expanded(child: TextField(
                  decoration: InputDecoration(labelText: 'Espèces (HTG)', border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppConstants.radiusInput))),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: InputFormatters.decimalAmount,
                )),
              ]),
              const SizedBox(height: 8),
              Text('Remaining: ${CurrencyFormatter.local(context, _total)}',
                  style: AppTextStyles.caption(color: AppColors.boldRed)),
            ],
          ),
        );
      default: // Card
        return AppCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.credit_card_outlined, size: 40, color: isDark ? AppColors.skyBlue : AppColors.primaryBlue),
              const SizedBox(height: 12),
              TextField(
                decoration: InputDecoration(
                  labelText: 'Numéro de carte',
                  hintText: '1234 5678 9012 3456',
                  prefixIcon: const Icon(Icons.credit_card, size: 18),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppConstants.radiusInput)),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: InputFormatters.cardNumber,
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: TextField(
                  decoration: InputDecoration(labelText: 'MM/YY', border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppConstants.radiusInput))),
                  keyboardType: TextInputType.number,
                  inputFormatters: InputFormatters.cardExpiry,
                )),
                const SizedBox(width: 8),
                Expanded(child: TextField(
                  decoration: InputDecoration(labelText: 'CVV', border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppConstants.radiusInput))),
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: InputFormatters.cardCvv,
                )),
              ]),
              const SizedBox(height: 4),
              Text('Propulsé par Stripe', style: AppTextStyles.caption()),
            ],
          ),
        );
    }
  }

  Future<void> _processPayment() async {
    setState(() => _isProcessing = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() { _isProcessing = false; _isDone = true; });
  }

  void _showWhatsAppDialog(BuildContext context) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          String? err;
          return AlertDialog(
            title: const Text('Envoyer par WhatsApp'),
            content: StatefulBuilder(
              builder: (ctx2, setD2) => TextField(
                controller: ctrl,
                onChanged: (_) => setD2(() => err = null),
                decoration: InputDecoration(
                  labelText: 'Numéro de téléphone',
                  hintText: '+509 XXXX-XXXX',
                  prefixIcon: const Icon(Icons.phone_outlined),
                  errorText: err,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppConstants.radiusInput),
                  ),
                ),
                keyboardType: TextInputType.phone,
                inputFormatters: InputFormatters.phone,
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
              TextButton(
                onPressed: () {
                  if (ctrl.text.trim().isEmpty) {
                    setD(() => err = 'Veuillez saisir un numéro de téléphone.');
                    return;
                  }
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Reçu envoyé par WhatsApp'), behavior: SnackBarBehavior.floating),
                  );
                },
                child: const Text('Envoyer'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showEmailDialog(BuildContext context) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          String? err;
          return AlertDialog(
            title: const Text('Envoyer le reçu par e-mail'),
            content: StatefulBuilder(
              builder: (ctx2, setD2) => TextField(
                controller: ctrl,
                onChanged: (_) => setD2(() => err = null),
                decoration: InputDecoration(
                  labelText: 'Adresse e-mail',
                  hintText: 'email@example.com',
                  prefixIcon: const Icon(Icons.email_outlined),
                  errorText: err,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppConstants.radiusInput),
                  ),
                ),
                keyboardType: TextInputType.emailAddress,
                inputFormatters: InputFormatters.email,
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
              TextButton(
                onPressed: () {
                  final email = ctrl.text.trim();
                  if (email.isEmpty || !email.contains('@')) {
                    setD(() => err = 'Veuillez saisir une adresse e-mail valide.');
                    return;
                  }
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Reçu envoyé par e-mail'), behavior: SnackBarBehavior.floating),
                  );
                },
                child: const Text('Envoyer'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showPrintDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Imprimer le reçu'),
        content: const Text('Reçu envoyé à l\'imprimante.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccess(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_rounded, color: AppColors.deepGreen, size: 80),
          const SizedBox(height: 24),
          Text('Paiement réussi', style: AppTextStyles.h1()),
          const SizedBox(height: 8),
          Text(CurrencyFormatter.local(context, _total), style: AppTextStyles.price().copyWith(fontSize: 24)),
          const SizedBox(height: 8),
          Text('via $_method', style: AppTextStyles.caption()),
          const SizedBox(height: 32),
          AppButton(
            label: 'Envoyer le reçu par WhatsApp',
            onPressed: () => _showWhatsAppDialog(context),
            icon: Icons.send_outlined,
          ),
          const SizedBox(height: 8),
          AppButton(
            label: 'Envoyer le reçu par e-mail',
            onPressed: () => _showEmailDialog(context),
            variant: AppButtonVariant.secondary,
            icon: Icons.email_outlined,
          ),
          const SizedBox(height: 8),
          AppButton(
            label: 'Imprimer le reçu',
            onPressed: () => _showPrintDialog(context),
            variant: AppButtonVariant.secondary,
            icon: Icons.print_outlined,
          ),
          const SizedBox(height: 8),
          AppButton(label: 'Terminé', onPressed: () => context.pop(), variant: AppButtonVariant.ghost),
        ],
      ),
    );
  }
}
