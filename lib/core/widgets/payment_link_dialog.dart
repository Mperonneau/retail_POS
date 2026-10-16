import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/constants.dart';
import '../utils/currency_formatter.dart';

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
String buildOrderPaymentLinkPath(Object orderId) => 'pay.bizmanager.ht/order-$orderId';

/// Standalone paylink page path from our app’s paylink id.
String buildStandalonePaylinkPath(String payLinkId) => 'pay.bizmanager.ht/pl/$payLinkId';

/// Retail quote checkout path.
String buildQuotePaymentLinkPath(String quoteNumber) =>
    'pay.bizmanager.ht/quote-${quoteNumber.toLowerCase()}';

String normalizePaymentLinkUrl(String pathOrUrl) {
  final t = pathOrUrl.trim();
  if (t.startsWith('http://') || t.startsWith('https://')) return t;
  return 'https://$t';
}

/// Shown after a payment link is **created and sent** (bill, quote, or paylink).
Future<void> showPaymentLinkSuccessDialog(
  BuildContext context, {
  required bool isDark,
  required String title,
  required String pathOrUrl,
  String? subtitle,
}) {
  final fullUrl = normalizePaymentLinkUrl(pathOrUrl);
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      const headline = 'Link has been sent';
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
                  child: const Icon(Icons.check_circle_rounded,
                      color: AppColors.deepGreen, size: 22),
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
                    'You can copy or share the link for the client or the payer. '
                    'It was not active before you sent it.',
                    style: AppTextStyles.caption(
                      color: isDark ? AppColors.coolGray : AppColors.darkGray,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.darkBackground
                          : AppColors.lightBlue,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isDark
                            ? AppColors.darkBorder
                            : AppColors.primaryBlue.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.link,
                            size: 14,
                            color: isDark
                                ? AppColors.skyBlue
                                : AppColors.primaryBlue),
                        const SizedBox(width: 6),
                        Expanded(
                          child: SelectableText(
                            fullUrl,
                            style: AppTextStyles.caption(
                              color: isDark
                                  ? AppColors.skyBlue
                                  : AppColors.primaryBlue,
                            ).copyWith(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: fullUrl));
                              setModalState(() => linkCopied[0] = true);
                              Future.delayed(
                                  const Duration(seconds: 2), () {
                                if (context.mounted) {
                                  setModalState(
                                      () => linkCopied[0] = false);
                                }
                              });
                            },
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 5),
                              decoration: BoxDecoration(
                                color: (isDark
                                        ? AppColors.darkSurface
                                        : AppColors.white)
                                    .withValues(alpha: 0.9),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: (isDark
                                          ? AppColors.coolGray
                                          : AppColors.primaryBlue)
                                      .withValues(alpha: 0.35),
                                ),
                              ),
                              child: AnimatedSwitcher(
                                duration: AppConstants.animFast,
                                child: linkCopied[0]
                                    ? const Icon(
                                        Icons.check_circle_outline_rounded,
                                        key: ValueKey('ok'),
                                        size: 16,
                                        color: AppColors.deepGreen,
                                      )
                                    : Icon(
                                        Icons.copy_outlined,
                                        key: const ValueKey('cp'),
                                        size: 16,
                                        color: isDark
                                            ? AppColors.skyBlue
                                            : AppColors.primaryBlue,
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  'Close',
                  style: AppTextStyles.button(
                    color: isDark ? AppColors.coolGray : AppColors.darkGray,
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => Share.share(fullUrl, subject: title),
                icon: const Icon(Icons.share_rounded, size: 18),
                label: const Text('Share'),
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
/// The checkout URL is **not** shown until the user taps "Send Link" and the
/// parent flow creates the link — use [showPaymentLinkSuccessDialog] with the
/// same path you would have passed as [linkPathForSuccess].
///
/// Returns [PaymentLinkSendResult] when the user taps "Send Link", or null on cancel.
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
      final v =
          double.tryParse(_prepaidAmountCtrl.text.replaceAll(',', '').trim());
      if (v == null || v <= 0) return false;
    }
    return true;
  }

  double? get _parsedPrepaidAmount {
    if (!widget.allowPrepaidAmount || !_usePrepaidAmount) return null;
    final v =
        double.tryParse(_prepaidAmountCtrl.text.replaceAll(',', '').trim());
    if (v == null || v <= 0) return null;
    return v;
  }

  String? get _validationMessage {
    if (_channel == null) return null;
    if (_channel == PaymentLinkChannel.email &&
        _emailCtrl.text.trim().isEmpty) {
      return "Enter the payer's email to send via Email";
    }
    if (_channel != PaymentLinkChannel.email &&
        _phoneCtrl.text.trim().isEmpty) {
      final name =
          _channel == PaymentLinkChannel.whatsApp ? 'WhatsApp' : 'SMS';
      return "Enter the payer's phone number to send via $name";
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final desc = widget.description ??
        "Enter the payer's phone or email below (who will actually pay), "
        'then choose how to send. The payment is applied to this order once completed.';

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
            child: Icon(Icons.link_rounded,
                size: 20,
                color: isDark ? AppColors.mediumGreen : AppColors.deepGreen),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Send Payment Link',
                    style: AppTextStyles.h3(
                        color: isDark
                            ? AppColors.warmWhite
                            : AppColors.nearBlack)),
                Text(widget.referenceLabel,
                    style: AppTextStyles.caption(
                        color: isDark
                            ? AppColors.coolGray
                            : AppColors.darkGray)),
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
              Text(desc,
                  style: AppTextStyles.body(
                      color: isDark ? AppColors.coolGray : AppColors.darkGray)),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                    Icon(Icons.info_outline_rounded,
                        size: 16,
                        color: isDark ? AppColors.skyBlue : AppColors.primaryBlue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'The payment link is created only when you tap “Send link”.',
                        style: AppTextStyles.caption(
                          color: isDark ? AppColors.coolGray : AppColors.darkGray,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _SectionLabel(label: 'PAYER CONTACT', isDark: isDark),
              const SizedBox(height: 4),
              Text(
                'Who will receive the link to pay. This is not pre-filled; enter the payer, not the client on file, unless they are the same person.',
                style: AppTextStyles.caption(
                  color: isDark ? AppColors.coolGray : AppColors.darkGray,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _phoneCtrl,
                onChanged: (_) => setState(() {}),
                keyboardType: TextInputType.phone,
                // `null` fully disables platform / browser autofill (default `[]` does not).
                autofillHints: null,
                enableSuggestions: false,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: 'Payer phone number',
                  prefixIcon: const Icon(Icons.phone_outlined, size: 18),
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(AppConstants.radiusInput),
                  ),
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
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
                  labelText: 'Payer email address',
                  prefixIcon: const Icon(Icons.email_outlined, size: 18),
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(AppConstants.radiusInput),
                  ),
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
              const SizedBox(height: 16),
              _SectionLabel(label: 'SEND VIA', isDark: isDark),
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
                          () => _channel = PaymentLinkChannel.whatsApp),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: _ChannelChip(
                      icon: Icons.email_outlined,
                      label: 'Email',
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
                    label: 'PREPAID AMOUNT (OPTIONAL)', isDark: isDark),
                const SizedBox(height: 6),
                Text(
                  'The guest spends against that balance on this bill (tax and service '
                  'included in estimates). Orders above the prepaid balance are blocked '
                  'until adjusted.',
                  style: AppTextStyles.caption(
                    color: isDark ? AppColors.coolGray : AppColors.darkGray,
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Set prepaid amount (HTG)',
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
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Prepaid amount (HTG)',
                      prefixIcon:
                          const Icon(Icons.payments_outlined, size: 18),
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppConstants.radiusInput),
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                    ),
                  ),
                  Builder(
                    builder: (ctx) {
                      final v = _parsedPrepaidAmount;
                      if (v == null) return const SizedBox.shrink();
                      final usd =
                          CurrencyFormatter.usdEquivalentOrNull(ctx, v);
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
                            const Icon(Icons.warning_amber_rounded,
                                size: 13, color: AppColors.boldRed),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(_validationMessage!,
                                  style: AppTextStyles.caption(
                                      color: AppColors.boldRed)),
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
          child: Text('Cancel',
              style: AppTextStyles.button(
                  color: isDark ? AppColors.coolGray : AppColors.darkGray)),
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
          label: const Text('Send Link'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.deepGreen,
            foregroundColor: AppColors.white,
            disabledBackgroundColor:
                isDark ? AppColors.darkBorder : const Color(0xFFEEEEEE),
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(AppConstants.radiusButton)),
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
              : (isDark
                  ? AppColors.darkBackground
                  : const Color(0xFFF7F7F7)),
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
            Icon(icon,
                size: 16,
                color: selected
                    ? color
                    : (isDark ? AppColors.coolGray : AppColors.darkGray)),
            const SizedBox(height: 1),
            Text(label,
                style: AppTextStyles.caption(
                  color: selected
                      ? color
                      : (isDark ? AppColors.coolGray : AppColors.darkGray),
                ).copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 10,
                  height: 1.1,
                )),
          ],
        ),
      ),
    );
  }
}
