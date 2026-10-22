import 'package:flutter/material.dart';

import '../../models/order_history.dart';
import '../../printing/shop_pdf.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../utils/constants.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/input_formatters.dart';
import '../../widgets/phone_field.dart';
import '../../widgets/payment_link_details_sheet.dart';
import '../../widgets/payment_method_block.dart';
import '../../widgets/app_close_button.dart';

bool _showServiceChargeRow(OrderHistoryRecord record) {
  if (record.serviceChargePercent <= 0) return false;
  if (record.module != OrderHistoryModule.retail) return true;
  return record.paymentMethod == PaymentMethodType.moncash ||
      record.paymentMethod == PaymentMethodType.card ||
      record.paidViaPaymentLink;
}

/// Standalone full-screen page used on mobile.
class OrderHistoryDetailPage extends StatelessWidget {
  final OrderHistoryRecord record;

  const OrderHistoryDetailPage({super.key, required this.record});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.warmOffWhite,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppConstants.spacing16),
        child: _DetailBody(
          record: record,
          isDark: isDark,
          onClose: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }
}

Future<void> _showPrintDialog(BuildContext context, OrderHistoryRecord record) {
  final safe = record.receiptNumber.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
  return printShopPdf(
    context,
    filename: 'recu-${safe.isEmpty ? 'vente' : safe}.pdf',
    document: shopPdfFromHistory(
      record: record,
      shopName: shopNameFrom(context),
      money: (amount) => localMoney(context, amount),
    ),
  );
}

/// Reusable detail body — used both in desktop drawer and mobile page.
class OrderHistoryDetailContent extends StatelessWidget {
  final OrderHistoryRecord record;
  final bool isDark;
  final VoidCallback? onClose;

  const OrderHistoryDetailContent({
    super.key,
    required this.record,
    required this.isDark,
    this.onClose,
  });

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
              builder: (ctx2, setD2) => PhoneField(
                controller: ctrl,
                label: 'Numéro de téléphone',
                errorText: err,
                onChanged: (_) => setD2(() => err = null),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
              FilledButton(
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
                      borderRadius: BorderRadius.circular(AppConstants.radiusInput)),
                ),
                keyboardType: TextInputType.emailAddress,
                inputFormatters: InputFormatters.email,
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
              FilledButton(
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

  Widget _buildPaymentSection(BuildContext context) {
    // If paymentLines are provided, render full detail cards.
    final lines = record.paymentLines;
    if (lines != null && lines.isNotEmpty) {
      return PaymentLinesDetailBlock(
        lines: lines,
        isDark: isDark,
        receiptLabel: record.receiptNumber,
      );
    }
    // Single payment-link payment without explicit lines: synthesise one line
    // so the rich UI is still shown.
    if (record.paymentMethod == PaymentMethodType.paymentLink ||
        record.paidViaPaymentLink) {
      final syntheticLine = PaymentLine(
        method: PaymentMethodType.paymentLink,
        amountHtg: record.total,
        paidAt: record.paidAt,
        linkDetails: PaymentLinkDetails(
          transactionId: 'pi_placeholder_${record.receiptNumber.replaceAll('-', '_')}',
          paidAt: record.paidAt,
          amountHtg: record.total,
          country: 'HT',
          payerNote: null,
          methodBrand: record.paymentLastFour != null ? 'Visa' : null,
          last4: record.paymentLastFour,
        ),
      );
      return PaymentLinesDetailBlock(
        lines: [syntheticLine],
        isDark: isDark,
        receiptLabel: record.receiptNumber,
      );
    }
    // Regular payment: existing chip + last-four.
    return PaymentMethodBlock(
      isDark: isDark,
      paymentMethod: record.paymentMethod,
      paymentLastFour: record.paymentLastFour,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (onClose != null) ...[
                AppCloseButton(onPressed: onClose),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(record.receiptNumber,
                        style: AppTextStyles.h2(
                            color: isDark
                                ? AppColors.skyBlue
                                : AppColors.primaryBlue)),
                    const SizedBox(height: 2),
                    Text(_formatDateFull(record.paidAt),
                        style: AppTextStyles.caption(
                            color: isDark
                                ? AppColors.coolGray
                                : AppColors.darkGray)),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => _showWhatsAppDialog(context),
                icon: Icon(Icons.send_outlined,
                    size: 18,
                    color: isDark ? AppColors.coolGray : AppColors.darkGray),
                tooltip: 'Partager par WhatsApp',
              ),
              IconButton(
                onPressed: () => _showEmailDialog(context),
                icon: Icon(Icons.email_outlined,
                    size: 18,
                    color: isDark ? AppColors.coolGray : AppColors.darkGray),
                tooltip: 'Envoyer par e-mail',
              ),
              IconButton(
                onPressed: () => _showPrintDialog(context, record),
                icon: Icon(Icons.print_outlined,
                    size: 18,
                    color: isDark ? AppColors.coolGray : AppColors.darkGray),
                tooltip: 'Imprimer',
              ),
            ],
          ),
        ),
        if (record.receiptName != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Icon(Icons.person_outline,
                    size: 15,
                    color: isDark ? AppColors.coolGray : AppColors.darkGray),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(record.receiptName!,
                      style: AppTextStyles.body(
                          color: isDark
                              ? AppColors.warmWhite
                              : AppColors.nearBlack)),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: Row(
            children: [
              Icon(Icons.place_outlined,
                  size: 15,
                  color: isDark ? AppColors.coolGray : AppColors.darkGray),
              const SizedBox(width: 6),
              Text(record.source,
                  style: AppTextStyles.caption(
                      color: isDark ? AppColors.coolGray : AppColors.darkGray)),
              const SizedBox(width: 10),
              _ModuleChip(module: record.module),
            ],
          ),
        ),
        const SizedBox(height: AppConstants.spacing12),
        const Divider(height: 1),
        // Items
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text('Articles',
              style: AppTextStyles.h3(
                  color: isDark ? AppColors.amber : AppColors.amber)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _LinesTable(
            rows: record.items
                .map((item) => (
                      item.quantity,
                      item.name,
                      item.priceHtg,
                      item.lineTotalHtg,
                    ))
                .toList(),
            isDark: isDark,
          ),
        ),
        const SizedBox(height: AppConstants.spacing12),
        const Divider(height: 1),
        // Charges summary
        _SummaryRow(
            label: 'Sous-total',
            value: CurrencyFormatter.local(context, record.subtotal),
            isDark: isDark),
        if (_showServiceChargeRow(record))
          _SummaryRow(
              label: 'Frais de service (${record.serviceChargePercent.toInt()} %)',
              value: CurrencyFormatter.local(context, record.serviceChargeAmount),
              isDark: isDark),
        if (record.taxPercent > 0)
          _SummaryRow(
              label: 'Taxe (${record.taxPercent.toInt()} %)',
              value: CurrencyFormatter.local(context, record.taxAmount),
              isDark: isDark),
        if (record.discountPercent > 0)
          _SummaryRow(
              label: 'Remise (${record.discountPercent.toInt()} %)',
              value: '-${CurrencyFormatter.local(context, record.discountAmount)}',
              isDark: isDark,
              valueColor: AppColors.boldRed),
        const Divider(height: 1),
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                  child: Text('TOTAL',
                      style: AppTextStyles.h2(
                          color: isDark
                              ? AppColors.warmWhite
                              : AppColors.nearBlack))),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(CurrencyFormatter.local(context, record.total),
                      style: AppTextStyles.price()),
                  if (CurrencyFormatter.usdEquivalentOrNull(
                          context, record.total) !=
                      null)
                    Text(
                      CurrencyFormatter.usdEquivalent(context, record.total),
                      style: AppTextStyles.caption(
                        color: isDark
                            ? AppColors.coolGray
                            : AppColors.darkGray,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // Payment (below charges)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text(
            'Paiement',
            style: AppTextStyles.h3(
                color: isDark ? AppColors.amber : AppColors.amber),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: _buildPaymentSection(context),
        ),
        const Divider(height: 1),
        const SizedBox(height: AppConstants.spacing16),
      ],
    ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  final OrderHistoryRecord record;
  final bool isDark;
  final VoidCallback? onClose;

  const _DetailBody({
    required this.record,
    required this.isDark,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return OrderHistoryDetailContent(
      record: record,
      isDark: isDark,
      onClose: onClose,
    );
  }
}

// ── Small widgets ─────────────────────────────────────────────────────────────

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isDark;
  final Color? valueColor;

  const _SummaryRow({
    required this.label,
    required this.value,
    required this.isDark,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Expanded(
              child: Text(label,
                  style: AppTextStyles.body(
                      color:
                          isDark ? AppColors.coolGray : AppColors.darkGray))),
          Text(value,
              style: AppTextStyles.body(
                  color: valueColor ??
                      (isDark ? AppColors.warmWhite : AppColors.nearBlack))),
        ],
      ),
    );
  }
}

class _ModuleChip extends StatelessWidget {
  final OrderHistoryModule module;
  const _ModuleChip({required this.module});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (module) {
      OrderHistoryModule.restaurant => ('Restaurant', AppColors.primaryBlue),
      OrderHistoryModule.hotel => ('Hôtel', AppColors.deepGreen),
      OrderHistoryModule.retail => ('Détail', AppColors.amber),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: AppTextStyles.caption(color: color)
              .copyWith(fontWeight: FontWeight.w600)),
    );
  }
}

String _formatDateFull(DateTime dt) {
  final months = [
    'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
    'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre',
  ];
  final h = dt.hour.toString().padLeft(2, '0');
  final m = dt.minute.toString().padLeft(2, '0');
  return '${dt.day} ${months[dt.month - 1]} ${dt.year} à $h:$m';
}

// ── Lines table ───────────────────────────────────────────────────────────────

/// Compact POS-style table: Qty | Item | Unit | Total
/// Each [rows] entry is (qty, name, unitPriceHtg, lineTotalHtg).
class _LinesTable extends StatelessWidget {
  final List<(int, String, double, double)> rows;
  final bool isDark;

  const _LinesTable({required this.rows, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final hdrBg = isDark ? AppColors.darkBackground : const Color(0xFFEEF2F7);
    final rowBg = isDark ? AppColors.darkSurface.withValues(alpha: 0.6) : AppColors.white;
    final divColor = isDark ? AppColors.darkBorder : const Color(0xFFE4E8EE);
    final hdrColor = isDark ? AppColors.coolGray : AppColors.darkGray;
    final valColor = isDark ? AppColors.warmWhite : AppColors.nearBlack;

    TextStyle hdr() => AppTextStyles.caption(color: hdrColor)
        .copyWith(fontWeight: FontWeight.w700, fontSize: 10.5);
    TextStyle val({bool bold = false}) =>
        AppTextStyles.caption(color: valColor)
            .copyWith(fontSize: 11.5, fontWeight: bold ? FontWeight.w600 : FontWeight.normal);

    Widget headerRow() => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          color: hdrBg,
          child: Row(children: [
            SizedBox(width: 28, child: Text('Qté', style: hdr(), textAlign: TextAlign.center)),
            const SizedBox(width: 8),
            Expanded(child: Text('Article', style: hdr())),
            SizedBox(width: 70, child: Text('Unité', style: hdr(), textAlign: TextAlign.right)),
            const SizedBox(width: 6),
            SizedBox(width: 70, child: Text('Total', style: hdr(), textAlign: TextAlign.right)),
          ]),
        );

    Widget dataRow(int qty, String name, double unit, double total, {bool last = false}) =>
        Container(
          color: rowBg,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 28,
                    child: Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primaryBlue.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('$qty',
                          style: hdr().copyWith(
                              color: isDark ? AppColors.skyBlue : AppColors.primaryBlue,
                              fontSize: 11),
                          textAlign: TextAlign.center),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(name,
                          style: val(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis)),
                  SizedBox(
                      width: 70,
                      child: Text(CurrencyFormatter.amountOnly(unit),
                          style: val(), textAlign: TextAlign.right)),
                  const SizedBox(width: 6),
                  SizedBox(
                      width: 70,
                      child: Text(CurrencyFormatter.amountOnly(total),
                          style: val(bold: true), textAlign: TextAlign.right)),
                ],
              ),
            ),
            if (!last)
              Container(height: 0.5, color: divColor, margin: const EdgeInsets.symmetric(horizontal: 10)),
          ]),
        );

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: divColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        headerRow(),
        Container(height: 1, color: divColor),
        ...rows.asMap().entries.map((e) => dataRow(
              e.value.$1,
              e.value.$2,
              e.value.$3,
              e.value.$4,
              last: e.key == rows.length - 1,
            )),
      ]),
    );
  }
}
