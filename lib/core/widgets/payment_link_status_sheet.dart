import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/constants.dart';
import '../utils/currency_formatter.dart';
import '../utils/order_bill_estimate.dart';
import 'discount_approval_dialog.dart';
import 'payment_link_dialog.dart';

/// Result returned from the payment-link status sheet.
class PaymentLinkStatusAction {
  /// null = dismissed, 'resend' = link was resent, 'mark_paid' = manually marked paid.
  final String action;
  /// Non-null when action == 'resend'.
  final PaymentLinkSendResult? resendResult;
  const PaymentLinkStatusAction(this.action, {this.resendResult});
}

/// Full-featured dialog showing the current payment-link state for an order.
///
/// Displays: link URL, recipient, channel, sent time, payment status.
/// Actions: copy link, update recipient & resend, manually mark as paid (admin code).
class PaymentLinkStatusSheet extends ConsumerStatefulWidget {
  final String orderLabel;
  final String payUrl;
  final String? recipient;
  final String? channel;
  final DateTime? sentAt;
  /// Customer / gateway payment received (webhook or manual simulation).
  final bool paymentLinkRemotePaid;
  /// Staff confirmed payment on the POS (clears active orders for dine-in when applicable).
  final bool staffPaymentConfirmed;
  final double? prepaidCapHtg;
  /// Resend dialog offers prepaid amount for table / dine-in flows.
  final bool allowPrepaidAmountOnResend;
  final bool isDark;

  const PaymentLinkStatusSheet({
    super.key,
    required this.orderLabel,
    required this.payUrl,
    this.recipient,
    this.channel,
    this.sentAt,
    this.paymentLinkRemotePaid = false,
    this.staffPaymentConfirmed = false,
    this.prepaidCapHtg,
    this.allowPrepaidAmountOnResend = false,
    required this.isDark,
  });

  @override
  ConsumerState<PaymentLinkStatusSheet> createState() =>
      _PaymentLinkStatusSheetState();
}

class _PaymentLinkStatusSheetState
    extends ConsumerState<PaymentLinkStatusSheet> {
  bool _linkCopied = false;
  bool _markingPaid = false;

  String get _channelLabel {
    switch (widget.channel) {
      case 'whatsApp':
        return 'WhatsApp';
      case 'email':
        return 'Email';
      case 'sms':
        return 'SMS';
      default:
        return widget.channel ?? '—';
    }
  }

  IconData get _channelIcon {
    switch (widget.channel) {
      case 'whatsApp':
        return Icons.chat_rounded;
      case 'email':
        return Icons.email_outlined;
      case 'sms':
        return Icons.sms_outlined;
      default:
        return Icons.send_rounded;
    }
  }

  String get _sentTimeLabel {
    if (widget.sentAt == null) return '—';
    final d = widget.sentAt!;
    final now = DateTime.now();
    final diff = now.difference(d);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${d.month}/${d.day} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  String get _summaryLabel {
    if (widget.staffPaymentConfirmed) {
      return 'Staff confirmed · Paid';
    }
    if (widget.paymentLinkRemotePaid) {
      return 'Customer paid · Confirm at register';
    }
    return 'Waiting for payment';
  }

  Color _summaryColor(bool isDark) {
    if (widget.staffPaymentConfirmed) {
      return isDark ? AppColors.mediumGreen : AppColors.deepGreen;
    }
    if (widget.paymentLinkRemotePaid) {
      return AppColors.amber;
    }
    return AppColors.amber;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final statusColor = _summaryColor(isDark);
    final statusLabel = _summaryLabel;

    return AlertDialog(
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.white,
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      actionsPadding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusCard),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.link_rounded, size: 20, color: statusColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Payment Link',
                  style: AppTextStyles.h3(
                    color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.orderLabel,
                  style: AppTextStyles.caption(
                    color: isDark ? AppColors.coolGray : AppColors.darkGray,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppConstants.radiusBadge),
              border: Border.all(color: statusColor.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  statusLabel,
                  style: AppTextStyles.caption(color: statusColor)
                      .copyWith(fontWeight: FontWeight.w600, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              _buildLinkBox(isDark),
              const SizedBox(height: 16),
              _buildInfoSection(isDark),
              if (!widget.staffPaymentConfirmed) ...[
                const SizedBox(height: 16),
                _buildActionsSection(isDark),
              ],
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Close',
            style: AppTextStyles.button(
              color: isDark ? AppColors.coolGray : AppColors.darkGray,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLinkBox(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkBackground : AppColors.lightBlue,
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
              color: isDark ? AppColors.skyBlue : AppColors.primaryBlue),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.payUrl,
              style: AppTextStyles.caption(
                color: isDark ? AppColors.skyBlue : AppColors.primaryBlue,
              ),
            ),
          ),
          GestureDetector(
            onTap: () {
              Clipboard.setData(
                ClipboardData(text: 'https://${widget.payUrl}'),
              );
              setState(() => _linkCopied = true);
              Future.delayed(const Duration(seconds: 2), () {
                if (mounted) setState(() => _linkCopied = false);
              });
            },
            child: AnimatedSwitcher(
              duration: AppConstants.animFast,
              child: _linkCopied
                  ? Icon(Icons.check_circle_outline_rounded,
                      key: const ValueKey('check'),
                      size: 15,
                      color: AppColors.deepGreen)
                  : Icon(Icons.copy_outlined,
                      key: const ValueKey('copy'),
                      size: 15,
                      color: isDark
                          ? AppColors.skyBlue
                          : AppColors.primaryBlue),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoSection(bool isDark) {
    final labelColor = isDark ? AppColors.coolGray : AppColors.darkGray;
    final valueColor = isDark ? AppColors.warmWhite : AppColors.nearBlack;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.darkBackground.withValues(alpha: 0.5)
            : const Color(0xFFF9F9FB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : const Color(0xFFE8E8EE),
        ),
      ),
      child: Column(
        children: [
          _InfoRow(
            icon: Icons.person_outline_rounded,
            label: 'Sent to',
            value: widget.recipient ?? '—',
            labelColor: labelColor,
            valueColor: valueColor,
          ),
          const SizedBox(height: 10),
          _InfoRow(
            icon: _channelIcon,
            label: 'Via',
            value: _channelLabel,
            labelColor: labelColor,
            valueColor: valueColor,
          ),
          const SizedBox(height: 10),
          _InfoRow(
            icon: Icons.schedule_rounded,
            label: 'Sent',
            value: _sentTimeLabel,
            labelColor: labelColor,
            valueColor: valueColor,
          ),
          if (widget.prepaidCapHtg != null) ...[
            const SizedBox(height: 10),
            _InfoRow(
              icon: Icons.savings_outlined,
              label: 'Prepaid amount',
              value: () {
                final p = widget.prepaidCapHtg!;
                final usd = CurrencyFormatter.usdEquivalentOrNull(context, p);
                if (usd == null) {
                  return CurrencyFormatter.local(context, p);
                }
                return '${CurrencyFormatter.local(context, p)}\n$usd';
              }(),
              labelColor: labelColor,
              valueColor: valueColor,
            ),
          ],
          const SizedBox(height: 10),
          _InfoRow(
            icon: Icons.cloud_done_outlined,
            label: 'Gateway',
            value: widget.paymentLinkRemotePaid ? 'Paid' : 'Pending',
            labelColor: labelColor,
            valueColor: valueColor,
          ),
          const SizedBox(height: 10),
          _InfoRow(
            icon: Icons.badge_outlined,
            label: 'Staff',
            value: widget.staffPaymentConfirmed ? 'Confirmed' : 'Not confirmed',
            labelColor: labelColor,
            valueColor: valueColor,
          ),
        ],
      ),
    );
  }

  Widget _buildActionsSection(bool isDark) {
    final borderColor = isDark ? AppColors.darkBorder : const Color(0xFFE0E0E0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _resendLink(context, isDark),
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Update & Resend'),
                style: OutlinedButton.styleFrom(
                  foregroundColor:
                      isDark ? AppColors.skyBlue : AppColors.primaryBlue,
                  side: BorderSide(color: borderColor),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(AppConstants.radiusButton),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  textStyle: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed:
                    _markingPaid ? null : () => _markAsPaid(context, isDark),
                icon: _markingPaid
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: isDark
                              ? AppColors.mediumGreen
                              : AppColors.deepGreen,
                        ),
                      )
                    : Icon(Icons.check_circle_outline_rounded,
                        size: 16,
                        color: isDark
                            ? AppColors.mediumGreen
                            : AppColors.deepGreen),
                label: Text(
                  'Mark as Paid',
                  style: TextStyle(
                    color:
                        isDark ? AppColors.mediumGreen : AppColors.deepGreen,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: (isDark ? AppColors.mediumGreen : AppColors.deepGreen)
                        .withValues(alpha: 0.4),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(AppConstants.radiusButton),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _resendLink(BuildContext context, bool isDark) async {
    final result = await showDialog<PaymentLinkSendResult>(
      context: context,
      builder: (ctx) => PaymentLinkDialog(
        referenceLabel: widget.orderLabel,
        description: "Update the payer's contact and resend the payment link.",
        isDark: isDark,
        allowPrepaidAmount: widget.allowPrepaidAmountOnResend,
        initialPrepaidAmountHtg: widget.prepaidCapHtg,
      ),
    );
    if (result != null && mounted) {
      Navigator.pop(context, PaymentLinkStatusAction('resend', resendResult: result));
    }
  }

  Future<void> _markAsPaid(BuildContext context, bool isDark) async {
    final approved = await showAdminApprovalDialog(
      context,
      ref,
      message:
          'This action requires admin authorization. Manually marking '
          '${widget.orderLabel} as paid should only be done if you can confirm '
          'the payment was received outside the app.',
      isDark: isDark,
      title: 'Admin authorization',
      codeFieldLabel: 'Admin password / code',
      confirmButtonLabel: 'Authorize',
    );
    if (approved == true && mounted) {
      setState(() => _markingPaid = true);
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      Navigator.pop(context, const PaymentLinkStatusAction('mark_paid'));
    }
  }
}

/// Shown at the top of a bill drawer when a remote payment link is active.
/// Tapping opens the same [PaymentLinkStatusSheet] as the order card indicator.
/// When [prepaidCapHtg] and [itemsSubtotalHtg] are provided, a small prepaid
/// sub-line is shown inside the banner (amount + balance left).
///
/// When [onViewPaymentDetails] is non-null AND [staffPaymentConfirmed] is true,
/// a secondary "View payment details" row is shown below the main banner.
class PaymentLinkBillBanner extends StatelessWidget {
  final bool paymentLinkRemotePaid;
  final bool staffPaymentConfirmed;
  final bool isDark;
  final VoidCallback onTap;
  final double? prepaidCapHtg;
  final double? itemsSubtotalHtg;
  /// Callback to open the payment details sheet. Supply this once the
  /// payment is confirmed and transaction data is available (or placeholder).
  final VoidCallback? onViewPaymentDetails;

  const PaymentLinkBillBanner({
    super.key,
    this.paymentLinkRemotePaid = false,
    this.staffPaymentConfirmed = false,
    required this.isDark,
    required this.onTap,
    this.prepaidCapHtg,
    this.itemsSubtotalHtg,
    this.onViewPaymentDetails,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = staffPaymentConfirmed
        ? (isDark ? AppColors.mediumGreen : AppColors.deepGreen)
        : AppColors.amber;
    final statusLabel = staffPaymentConfirmed
        ? 'Staff confirmed paid'
        : paymentLinkRemotePaid
            ? 'Customer paid — confirm at register'
            : 'Waiting for payment';
    final muted = isDark ? AppColors.coolGray : AppColors.darkGray;

    // Prepaid sub-line
    final hasPrepaid = prepaidCapHtg != null && itemsSubtotalHtg != null;
    final double headroom = hasPrepaid
        ? prepaidHeadroomHtgFromSubtotal(
            prepaidCapHtg: prepaidCapHtg!,
            itemsSubtotalHtg: itemsSubtotalHtg!,
          )
        : 0;
    final prepaidColor =
        staffPaymentConfirmed ? AppColors.deepGreen : AppColors.amber;

    final showDetailsRow =
        staffPaymentConfirmed && onViewPaymentDetails != null;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppConstants.radiusCard),
      clipBehavior: Clip.antiAlias,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: statusColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppConstants.radiusCard),
          border: Border.all(color: statusColor.withValues(alpha: 0.28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Main tappable row ──────────────────────────────────────────
            InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppConstants.spacing12,
                  vertical: AppConstants.spacing10,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(Icons.link_rounded, size: 20, color: statusColor),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Payment link active',
                            style: AppTextStyles.caption(color: muted).copyWith(
                              fontWeight: FontWeight.w600,
                              fontSize: 11,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            statusLabel,
                            style: AppTextStyles.body(color: statusColor)
                                .copyWith(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          // Prepaid sub-line
                          if (hasPrepaid) ...[
                            const SizedBox(height: 5),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Icon(Icons.savings_outlined,
                                      size: 11,
                                      color:
                                          prepaidColor.withValues(alpha: 0.8)),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    'Prepaid ${CurrencyFormatter.local(context, prepaidCapHtg!)} · '
                                    '${CurrencyFormatter.local(context, headroom)} left',
                                    style: AppTextStyles.caption(
                                            color: prepaidColor)
                                        .copyWith(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      height: 1.25,
                                    ),
                                    maxLines: 2,
                                    softWrap: true,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: statusColor.withValues(alpha: 0.4),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        'View',
                        style:
                            AppTextStyles.caption(color: statusColor).copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right_rounded, size: 18, color: muted),
                  ],
                ),
              ),
            ),

            // ── "View payment details" row (only when confirmed) ───────────
            if (showDetailsRow) ...[
              Container(
                height: 1,
                color: statusColor.withValues(alpha: 0.18),
              ),
              InkWell(
                onTap: onViewPaymentDetails,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppConstants.spacing12, vertical: 9),
                  child: Row(
                    children: [
                      Icon(Icons.receipt_long_outlined,
                          size: 13,
                          color: statusColor.withValues(alpha: 0.85)),
                      const SizedBox(width: 7),
                      Text(
                        'View payment details',
                        style: AppTextStyles.caption(color: statusColor)
                            .copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 11.5,
                        ),
                      ),
                      const Spacer(),
                      Icon(Icons.chevron_right_rounded,
                          size: 15, color: muted),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color labelColor;
  final Color valueColor;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.labelColor,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: labelColor),
        const SizedBox(width: 8),
        Text(
          label,
          style: AppTextStyles.caption(color: labelColor)
              .copyWith(fontWeight: FontWeight.w500),
        ),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            style: AppTextStyles.body(color: valueColor)
                .copyWith(fontWeight: FontWeight.w600, fontSize: 13),
            maxLines: 3,
            softWrap: true,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }
}
