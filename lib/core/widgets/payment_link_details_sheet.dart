import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/order_history.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/currency_formatter.dart';

// ── Public API ────────────────────────────────────────────────────────────────

/// Shows a full-screen bottom sheet with per-method payment details.
///
/// [lines] must contain at least one [PaymentLine]. For mixed payments
/// (e.g. link + cash), pass both lines. Each renders as its own card.
Future<void> showPaymentDetailsSheet({
  required BuildContext context,
  required bool isDark,
  required List<PaymentLine> lines,
  String? receiptLabel,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PaymentDetailsSheet(
      lines: lines,
      isDark: isDark,
      receiptLabel: receiptLabel,
    ),
  );
}

// ── Sheet ─────────────────────────────────────────────────────────────────────

class _PaymentDetailsSheet extends StatelessWidget {
  final List<PaymentLine> lines;
  final bool isDark;
  final String? receiptLabel;

  const _PaymentDetailsSheet({
    required this.lines,
    required this.isDark,
    this.receiptLabel,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? AppColors.darkSurface : AppColors.white;
    final maxH = MediaQuery.of(context).size.height * 0.92;

    return Container(
      constraints: BoxConstraints(maxHeight: maxH),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: (isDark ? AppColors.coolGray : AppColors.darkGray)
                    .withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              child: PaymentLinesDetailBlock(
                lines: lines,
                isDark: isDark,
                receiptLabel: receiptLabel,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Reusable block (also embedded in order history detail) ────────────────────

/// Renders one card per [PaymentLine] with full details.
/// Used in both the bottom sheet and the order history detail's Payment section.
class PaymentLinesDetailBlock extends StatelessWidget {
  final List<PaymentLine> lines;
  final bool isDark;
  final String? receiptLabel;

  const PaymentLinesDetailBlock({
    super.key,
    required this.lines,
    required this.isDark,
    this.receiptLabel,
  });

  @override
  Widget build(BuildContext context) {
    final muted = isDark ? AppColors.coolGray : AppColors.darkGray;
    final surface = isDark ? AppColors.darkBackground : AppColors.warmOffWhite;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header ──────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.deepGreen.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.check_circle_rounded,
                  color: AppColors.deepGreen,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Payment Confirmed',
                      style: AppTextStyles.h2(
                        color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
                      ),
                    ),
                    if (receiptLabel != null)
                      Text(
                        receiptLabel!,
                        style: AppTextStyles.caption(color: muted),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // ── One card per payment line ────────────────────────────────────
        ...lines.asMap().entries.map((entry) {
          final line = entry.value;
          final isLast = entry.key == lines.length - 1;
          return Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
            child: line.method == PaymentMethodType.paymentLink
                ? _LinkPaymentCard(line: line, isDark: isDark, surface: surface)
                : _CashPaymentCard(line: line, isDark: isDark, surface: surface),
          );
        }),

        // ── Multi-payment total footer ───────────────────────────────────
        if (lines.length > 1) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: AppColors.primaryBlue.withValues(alpha: 0.18)),
            ),
            child: Row(
              children: [
                Text(
                  'Total paid',
                  style: AppTextStyles.body(
                          color: isDark ? AppColors.skyBlue : AppColors.primaryBlue)
                      .copyWith(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                Text(
                  CurrencyFormatter.local(
                    context,
                    lines.fold(0.0, (sum, l) => sum + l.amountHtg),
                  ),
                  style: AppTextStyles.price(
                      color: isDark ? AppColors.skyBlue : AppColors.primaryBlue),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ── Payment link card ─────────────────────────────────────────────────────────

class _LinkPaymentCard extends StatelessWidget {
  final PaymentLine line;
  final bool isDark;
  final Color surface;

  const _LinkPaymentCard({
    required this.line,
    required this.isDark,
    required this.surface,
  });

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF7C3AED);
    final muted = isDark ? AppColors.coolGray : AppColors.darkGray;
    final d = line.linkDetails;

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.07),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(11)),
            ),
            child: Row(
              children: [
                Icon(Icons.link_rounded, size: 16, color: accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Payment Link',
                    style: AppTextStyles.body(color: accent)
                        .copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  CurrencyFormatter.local(context, line.amountHtg),
                  style: AppTextStyles.price(color: accent),
                ),
              ],
            ),
          ),

          // Details rows
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            child: Column(
              children: [
                _DetailRow(
                  icon: Icons.access_time_rounded,
                  label: 'Paid at',
                  value: _formatDateTime(line.paidAt),
                  isDark: isDark,
                ),
                if (d != null) ...[
                  const SizedBox(height: 8),
                  // Method — brand + masked card
                  _DetailRow(
                    icon: _methodIcon(d),
                    label: 'Method',
                    value: _methodLabel(d),
                    isDark: isDark,
                  ),
                  const SizedBox(height: 8),
                  // Transaction ID with copy button
                  _TransactionIdRow(
                    transactionId: d.transactionId,
                    isDark: isDark,
                    muted: muted,
                  ),
                  if (d.country != null) ...[
                    const SizedBox(height: 8),
                    _DetailRow(
                      icon: Icons.public_rounded,
                      label: 'Country',
                      value: _countryLabel(d.country!),
                      isDark: isDark,
                    ),
                  ],
                  if (d.payerNote != null && d.payerNote!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _NoteRow(note: d.payerNote!, isDark: isDark, muted: muted),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _methodIcon(PaymentLinkDetails d) {
    final brand = (d.methodBrand ?? '').toLowerCase();
    if (brand.contains('apple')) return Icons.apple;
    if (brand.contains('google')) return Icons.g_mobiledata_rounded;
    return Icons.credit_card_outlined;
  }

  String _methodLabel(PaymentLinkDetails d) {
    final parts = <String>[];
    if (d.methodBrand != null) parts.add(d.methodBrand!);
    if (d.last4 != null) parts.add('•••• ${d.last4}');
    return parts.isEmpty ? 'Online' : parts.join('  ');
  }
}

// ── Cash card ─────────────────────────────────────────────────────────────────

class _CashPaymentCard extends StatelessWidget {
  final PaymentLine line;
  final bool isDark;
  final Color surface;

  const _CashPaymentCard({
    required this.line,
    required this.isDark,
    required this.surface,
  });

  @override
  Widget build(BuildContext context) {
    const accent = AppColors.deepGreen;

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.07),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(11)),
            ),
            child: Row(
              children: [
                const Icon(Icons.payments_outlined, size: 16, color: accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Cash',
                    style: AppTextStyles.body(color: accent)
                        .copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  CurrencyFormatter.local(context, line.amountHtg),
                  style: AppTextStyles.price(color: accent),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            child: Column(
              children: [
                _DetailRow(
                  icon: Icons.access_time_rounded,
                  label: 'Recorded at',
                  value: _formatDateTime(line.paidAt),
                  isDark: isDark,
                ),
                if (line.recordedBy != null) ...[
                  const SizedBox(height: 8),
                  _DetailRow(
                    icon: Icons.person_outline,
                    label: 'Recorded by',
                    value: line.recordedBy!,
                    isDark: isDark,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared detail rows ────────────────────────────────────────────────────────

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool isDark;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final muted = isDark ? AppColors.coolGray : AppColors.darkGray;
    final strong = isDark ? AppColors.warmWhite : AppColors.nearBlack;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 14, color: muted),
        ),
        const SizedBox(width: 8),
        Text(label,
            style:
                AppTextStyles.caption(color: muted).copyWith(fontSize: 11.5)),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            style: AppTextStyles.caption(color: strong).copyWith(
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
            textAlign: TextAlign.end,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// Transaction ID row with a copy icon button.
class _TransactionIdRow extends StatefulWidget {
  final String transactionId;
  final bool isDark;
  final Color muted;

  const _TransactionIdRow({
    required this.transactionId,
    required this.isDark,
    required this.muted,
  });

  @override
  State<_TransactionIdRow> createState() => _TransactionIdRowState();
}

class _TransactionIdRowState extends State<_TransactionIdRow> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.transactionId));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final strong = widget.isDark ? AppColors.warmWhite : AppColors.nearBlack;
    final truncated = widget.transactionId.length > 24
        ? '${widget.transactionId.substring(0, 10)}…${widget.transactionId.substring(widget.transactionId.length - 8)}'
        : widget.transactionId;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(Icons.tag_rounded, size: 14, color: widget.muted),
        const SizedBox(width: 8),
        Text(
          'Transaction',
          style: AppTextStyles.caption(color: widget.muted)
              .copyWith(fontSize: 11.5),
        ),
        const Spacer(),
        Flexible(
          child: Text(
            truncated,
            style: AppTextStyles.caption(color: strong).copyWith(
              fontWeight: FontWeight.w600,
              fontSize: 11.5,
              fontFamily: 'monospace',
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
          ),
        ),
        const SizedBox(width: 4),
        GestureDetector(
          onTap: _copy,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _copied
                ? Icon(Icons.check_rounded,
                    key: const ValueKey('check'),
                    size: 15,
                    color: AppColors.deepGreen)
                : Icon(Icons.copy_rounded,
                    key: const ValueKey('copy'),
                    size: 15,
                    color: widget.muted),
          ),
        ),
      ],
    );
  }
}

/// Payer note row — displayed as a highlighted block.
class _NoteRow extends StatelessWidget {
  final String note;
  final bool isDark;
  final Color muted;

  const _NoteRow({
    required this.note,
    required this.isDark,
    required this.muted,
  });

  @override
  Widget build(BuildContext context) {
    final strong = isDark ? AppColors.warmWhite : AppColors.nearBlack;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.amber.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.amber.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.chat_bubble_outline_rounded,
                  size: 12, color: AppColors.amber),
              const SizedBox(width: 5),
              Text(
                'Note from payer',
                style: AppTextStyles.caption(color: AppColors.amber)
                    .copyWith(fontWeight: FontWeight.w700, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            note,
            style: AppTextStyles.body(color: strong).copyWith(
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

String _formatDateTime(DateTime dt) {
  final months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final h = dt.hour.toString().padLeft(2, '0');
  final m = dt.minute.toString().padLeft(2, '0');
  return '${dt.day} ${months[dt.month - 1]} ${dt.year}  $h:$m';
}

String _countryLabel(String code) {
  const map = {
    'HT': '🇭🇹  Haiti',
    'US': '🇺🇸  United States',
    'FR': '🇫🇷  France',
    'CA': '🇨🇦  Canada',
    'DO': '🇩🇴  Dominican Republic',
    'JM': '🇯🇲  Jamaica',
    'CU': '🇨🇺  Cuba',
    'GB': '🇬🇧  United Kingdom',
    'DE': '🇩🇪  Germany',
  };
  return map[code.toUpperCase()] ?? code.toUpperCase();
}

