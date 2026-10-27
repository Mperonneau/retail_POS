import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/constants.dart';
import '../utils/currency_formatter.dart';
import 'phone_field.dart';

enum PaymentLinkChannel { whatsApp, email, sms }

class PaymentLinkSendResult {
  final PaymentLinkChannel channel;
  final String contact;

  /// When set (table / dine-in prepaid link), guest spends against this prepaid HTG balance.
  final double? prepaidCapHtg;

  const PaymentLinkSendResult({
    required this.channel,
    required this.contact,
    this.prepaidCapHtg,
  });
}

/// Mock checkout base path (no scheme). Real integration would return a URL from the API.
String buildOrderPaymentLinkPath(Object orderId) =>
    'pay.bizmanager.ht/order-$orderId';

/// Standalone paylink page path from our app’s paylink id.
String buildStandalonePaylinkPath(String payLinkId) =>
    'pay.bizmanager.ht/pl/$payLinkId';

/// Retail quote checkout path.
String buildQuotePaymentLinkPath(String quoteNumber) =>
    'pay.bizmanager.ht/quote-${quoteNumber.toLowerCase()}';

String normalizePaymentLinkUrl(String pathOrUrl) {
  final t = pathOrUrl.trim();
  if (t.startsWith('http://') || t.startsWith('https://')) return t;
  return 'https://$t';
}

/// Message for the share sheet. The checkout URL is included so the payer can
/// open it, along with the commande or devis number and the client.
///
/// The amount is the dollar charge, with the gourde amount in parentheses.
/// The payer's phone is never included.
String paymentLinkShareMessage({
  required String url,
  required String number,
  String? kindLabel,
  String? clientName,
  String? usdLabel,
  String? htgLabel,
}) {
  final lines = <String>['Lien de paiement'];
  final num = number.trim();
  final kind = kindLabel?.trim() ?? '';
  if (num.isNotEmpty) {
    lines.add(kind.isEmpty ? 'Numéro : $num' : '$kind : $num');
  }
  final client = clientName?.trim() ?? '';
  if (client.isNotEmpty) lines.add('Client : $client');
  final usd = usdLabel?.trim() ?? '';
  final htg = htgLabel?.trim() ?? '';
  if (usd.isNotEmpty && htg.isNotEmpty) {
    lines.add('Montant : $usd ($htg)');
  } else if (usd.isNotEmpty) {
    lines.add('Montant : $usd');
  } else if (htg.isNotEmpty) {
    lines.add('Montant : $htg');
  }
  final link = url.trim();
  if (link.isNotEmpty) {
    lines.add('');
    lines.add('Cliquez sur le lien ci-dessous pour effectuer le paiement.');
    lines.add(link);
  }
  return lines.join('\n');
}

/// Shown after a payment link is **created and sent** (bill, quote, or paylink).
Future<void> showPaymentLinkSuccessDialog(
  BuildContext context, {
  required bool isDark,
  required String title,
  required String pathOrUrl,
  String? subtitle,
  String headline = 'Le lien a été envoyé',
  String? shareText,
}) {
  final fullUrl = normalizePaymentLinkUrl(pathOrUrl);
  final shared = (shareText ?? '').trim().isEmpty ? fullUrl : shareText!.trim();
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      final linkCopied = <bool>[false];
      return StatefulBuilder(
        builder: (context, setModalState) {
          return AlertDialog(
            backgroundColor: isDark ? AppColors.darkSurface : AppColors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.deepGreen.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.check_circle_rounded,
                    color: AppColors.deepGreen,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    headline,
                    style: AppTextStyles.h3(
                      color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
                    ),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTextStyles.body(
                      color: isDark ? AppColors.coolGray : AppColors.darkGray,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: AppTextStyles.caption(
                        color: isDark ? AppColors.coolGray : AppColors.darkGray,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    'Copiez le lien ou partagez-le avec le payeur.',
                    style: AppTextStyles.caption(
                      color: isDark ? AppColors.coolGray : AppColors.darkGray,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Material(
                    color: isDark
                        ? AppColors.darkBackground
                        : AppColors.lightBlue,
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: fullUrl));
                        setModalState(() => linkCopied[0] = true);
                        Future.delayed(const Duration(seconds: 2), () {
                          if (context.mounted) {
                            setModalState(() => linkCopied[0] = false);
                          }
                        });
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isDark
                                ? AppColors.darkBorder
                                : AppColors.primaryBlue.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              linkCopied[0]
                                  ? Icons.check_circle_outline_rounded
                                  : Icons.copy_outlined,
                              size: 18,
                              color: linkCopied[0]
                                  ? AppColors.deepGreen
                                  : (isDark
                                        ? AppColors.skyBlue
                                        : AppColors.primaryBlue),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                linkCopied[0] ? 'Lien copié' : 'Copier le lien',
                                style: AppTextStyles.body(
                                  color: isDark
                                      ? AppColors.skyBlue
                                      : AppColors.primaryBlue,
                                ).copyWith(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  'Fermer',
                  style: AppTextStyles.button(
                    color: isDark ? AppColors.coolGray : AppColors.darkGray,
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => Share.share(shared, subject: title),
                icon: const Icon(Icons.share_rounded, size: 18),
                label: const Text('Partager'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primaryBlue,
                  side: BorderSide(
                    color: AppColors.primaryBlue.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ],
            actionsAlignment: MainAxisAlignment.end,
            actionsOverflowButtonSpacing: 8,
            actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          );
        },
      );
    },
  );
}

/// Shared dialog for sending a payment link via WhatsApp, Email, or SMS.
///
/// The checkout URL is **not** shown until the user taps "Envoyer le lien" and the
/// parent flow creates the link — use [showPaymentLinkSuccessDialog] with the
/// same path you would have passed as [linkPathForSuccess].
///
/// Returns [PaymentLinkSendResult] when the user taps "Envoyer le lien", or null on cancel.
class PaymentLinkDialog extends StatefulWidget {
  final String referenceLabel;
  final String? description;
  final bool isDark;

  /// When true, staff can set a prepaid amount (HTG) for table / dine-in links.
  final bool allowPrepaidAmount;

  /// Starting prepaid amount when resending (optional).
  final double? initialPrepaidAmountHtg;

  const PaymentLinkDialog({
    super.key,
    required this.referenceLabel,
    this.description,
    required this.isDark,
    this.allowPrepaidAmount = false,
    this.initialPrepaidAmountHtg,
  });

  @override
  State<PaymentLinkDialog> createState() => _PaymentLinkDialogState();
}

class _PaymentLinkDialogState extends State<PaymentLinkDialog> {
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _prepaidAmountCtrl;
  PaymentLinkChannel? _channel;
  bool _usePrepaidAmount = false;

  @override
  void initState() {
    super.initState();
    // Payer contact — not prefilled; staff enters who will pay.
    _phoneCtrl = TextEditingController();
    _emailCtrl = TextEditingController();
    final cap = widget.initialPrepaidAmountHtg;
    _usePrepaidAmount = widget.allowPrepaidAmount && cap != null && cap > 0;
    _prepaidAmountCtrl = TextEditingController(
      text: cap != null && cap > 0 ? cap.toStringAsFixed(0) : '',
    );
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _prepaidAmountCtrl.dispose();
    super.dispose();
  }

  bool get _canSend {
    if (_channel == null) return false;
    if (_channel == PaymentLinkChannel.email) {
      if (_emailCtrl.text.trim().isEmpty) return false;
    } else if (_phoneCtrl.text.trim().isEmpty) {
      return false;
    }
    if (widget.allowPrepaidAmount && _usePrepaidAmount) {
      final v = double.tryParse(
        _prepaidAmountCtrl.text.replaceAll(',', '').trim(),
      );
      if (v == null || v <= 0) return false;
    }
    return true;
  }

  double? get _parsedPrepaidAmount {
    if (!widget.allowPrepaidAmount || !_usePrepaidAmount) return null;
    final v = double.tryParse(
      _prepaidAmountCtrl.text.replaceAll(',', '').trim(),
    );
    if (v == null || v <= 0) return null;
    return v;
  }

  String? get _validationMessage {
    if (_channel == null) return null;
    if (_channel == PaymentLinkChannel.email &&
        _emailCtrl.text.trim().isEmpty) {
      return "Saisissez l'e-mail du payeur pour l'envoi par e-mail";
    }
    if (_channel != PaymentLinkChannel.email &&
        _phoneCtrl.text.trim().isEmpty) {
      final name = _channel == PaymentLinkChannel.whatsApp ? 'WhatsApp' : 'SMS';
      return "Saisissez le téléphone du payeur pour l'envoi via $name";
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final desc =
        widget.description ??
        "Saisissez ci-dessous le téléphone ou l'e-mail du payeur, "
            'puis choisissez le mode d\'envoi. Le paiement sera appliqué à cette commande une fois terminé.';

    return AlertDialog(
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.white,
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.deepGreen.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.link_rounded,
              size: 20,
              color: isDark ? AppColors.mediumGreen : AppColors.deepGreen,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Envoyer le lien de paiement',
                  style: AppTextStyles.h3(
                    color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
                  ),
                ),
                Text(
                  widget.referenceLabel,
                  style: AppTextStyles.caption(
                    color: isDark ? AppColors.coolGray : AppColors.darkGray,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Text(
                desc,
                style: AppTextStyles.body(
                  color: isDark ? AppColors.coolGray : AppColors.darkGray,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.darkBackground
                      : const Color(0xFFF0F4F8),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark
                        ? AppColors.darkBorder
                        : AppColors.primaryBlue.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 16,
                      color: isDark ? AppColors.skyBlue : AppColors.primaryBlue,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Le lien de paiement est créé seulement quand vous touchez « Envoyer le lien ».',
                        style: AppTextStyles.caption(
                          color: isDark
                              ? AppColors.coolGray
                              : AppColors.darkGray,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _SectionLabel(label: 'CONTACT DU PAYEUR', isDark: isDark),
              const SizedBox(height: 4),
              Text(
                'Qui recevra le lien de paiement. Ce n\'est pas prérempli : saisissez le payeur, pas le client du dossier, sauf si c\'est la même personne.',
                style: AppTextStyles.caption(
                  color: isDark ? AppColors.coolGray : AppColors.darkGray,
                ),
              ),
              const SizedBox(height: 8),
              PhoneField(
                controller: _phoneCtrl,
                label: 'Téléphone du payeur',
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _emailCtrl,
                onChanged: (_) => setState(() {}),
                keyboardType: TextInputType.emailAddress,
                autofillHints: null,
                enableSuggestions: false,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: 'E-mail du payeur',
                  prefixIcon: const Icon(Icons.email_outlined, size: 18),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                      AppConstants.radiusInput,
                    ),
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _SectionLabel(label: 'ENVOYER PAR', isDark: isDark),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: _ChannelChip(
                      icon: Icons.chat_rounded,
                      label: 'WhatsApp',
                      color: const Color(0xFF25D366),
                      selected: _channel == PaymentLinkChannel.whatsApp,
                      isDark: isDark,
                      onTap: () => setState(
                        () => _channel = PaymentLinkChannel.whatsApp,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: _ChannelChip(
                      icon: Icons.email_outlined,
                      label: 'E-mail',
                      color: AppColors.primaryBlue,
                      selected: _channel == PaymentLinkChannel.email,
                      isDark: isDark,
                      onTap: () =>
                          setState(() => _channel = PaymentLinkChannel.email),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: _ChannelChip(
                      icon: Icons.sms_outlined,
                      label: 'SMS',
                      color: AppColors.amber,
                      selected: _channel == PaymentLinkChannel.sms,
                      isDark: isDark,
                      onTap: () =>
                          setState(() => _channel = PaymentLinkChannel.sms),
                    ),
                  ),
                ],
              ),
              if (widget.allowPrepaidAmount) ...[
                const SizedBox(height: 16),
                _SectionLabel(
                  label: 'MONTANT PRÉPAYÉ (FACULTATIF)',
                  isDark: isDark,
                ),
                const SizedBox(height: 6),
                Text(
                  'Le client utilise ce solde sur cette note (taxe et service '
                  'inclus dans l\'estimation). Au-delà du prépaiement, les commandes sont bloquées '
                  'tant que le montant n\'est pas ajusté.',
                  style: AppTextStyles.caption(
                    color: isDark ? AppColors.coolGray : AppColors.darkGray,
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Définir le prépaiement (HTG)',
                    style: AppTextStyles.body(
                      color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
                    ),
                  ),
                  value: _usePrepaidAmount,
                  activeTrackColor: AppColors.deepGreen.withValues(alpha: 0.5),
                  onChanged: (v) => setState(() => _usePrepaidAmount = v),
                ),
                if (_usePrepaidAmount) ...[
                  TextField(
                    controller: _prepaidAmountCtrl,
                    onChanged: (_) => setState(() {}),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Montant prépayé (HTG)',
                      prefixIcon: const Icon(Icons.payments_outlined, size: 18),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                          AppConstants.radiusInput,
                        ),
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                  ),
                  Builder(
                    builder: (ctx) {
                      final v = _parsedPrepaidAmount;
                      if (v == null) return const SizedBox.shrink();
                      final usd = CurrencyFormatter.usdEquivalentOrNull(ctx, v);
                      if (usd == null) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(left: 4, top: 6),
                        child: Text(
                          usd,
                          style: AppTextStyles.caption(
                            color: isDark
                                ? AppColors.coolGray
                                : AppColors.darkGray,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ],
              AnimatedSize(
                duration: AppConstants.animFast,
                child: _validationMessage != null
                    ? Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.warning_amber_rounded,
                              size: 13,
                              color: AppColors.boldRed,
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                _validationMessage!,
                                style: AppTextStyles.caption(
                                  color: AppColors.boldRed,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Annuler',
            style: AppTextStyles.button(
              color: isDark ? AppColors.coolGray : AppColors.darkGray,
            ),
          ),
        ),
        ElevatedButton.icon(
          onPressed: _canSend
              ? () => Navigator.pop(
                  context,
                  PaymentLinkSendResult(
                    channel: _channel!,
                    contact: _channel == PaymentLinkChannel.email
                        ? _emailCtrl.text.trim()
                        : _phoneCtrl.text.trim(),
                    prepaidCapHtg: _parsedPrepaidAmount,
                  ),
                )
              : null,
          icon: const Icon(Icons.send_rounded, size: 16),
          label: const Text('Envoyer le lien'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.deepGreen,
            foregroundColor: AppColors.white,
            disabledBackgroundColor: isDark
                ? AppColors.darkBorder
                : const Color(0xFFEEEEEE),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppConstants.radiusButton),
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final bool isDark;
  const _SectionLabel({required this.label, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: AppTextStyles.caption(
        color: isDark ? AppColors.coolGray : AppColors.darkGray,
      ).copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.8, fontSize: 10),
    );
  }
}

class _ChannelChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;

  const _ChannelChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppConstants.animFast,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: isDark ? 0.18 : 0.1)
              : (isDark ? AppColors.darkBackground : const Color(0xFFF7F7F7)),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected
                ? color
                : (isDark ? AppColors.darkBorder : const Color(0xFFE0E0E0)),
            width: selected ? 1.25 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: selected
                  ? color
                  : (isDark ? AppColors.coolGray : AppColors.darkGray),
            ),
            const SizedBox(height: 1),
            Text(
              label,
              style:
                  AppTextStyles.caption(
                    color: selected
                        ? color
                        : (isDark ? AppColors.coolGray : AppColors.darkGray),
                  ).copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 10,
                    height: 1.1,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
