import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../../core/models/retail_fulfillment_mode.dart';
import '../../core/models/retail_order.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/constants.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/date_formatter.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_close_button.dart';
import '../../core/widgets/payment_method_block.dart';
import '../receipt/sale_receipt_pdf.dart';
import '../receipt/sale_receipt_text.dart';
import '../receipt/share_receipt_file.dart';

/// The sale the cashier just recorded, laid out as a receipt that can be
/// printed, downloaded, or shared.
class SaleReceiptPanel extends ConsumerStatefulWidget {
  final RetailOrder order;
  final SaleReceiptFigures figures;
  final String? contextSubtitle;
  final String statusLine;
  final VoidCallback onDone;

  const SaleReceiptPanel({
    super.key,
    required this.order,
    required this.figures,
    required this.statusLine,
    required this.onDone,
    this.contextSubtitle,
  });

  @override
  ConsumerState<SaleReceiptPanel> createState() => _SaleReceiptPanelState();
}

class _SaleReceiptPanelState extends ConsumerState<SaleReceiptPanel> {
  bool _busy = false;
  Uint8List? _pdfBytes;
  String? _pdfShop;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _preparePdf());
  }

  Future<void> _preparePdf() async {
    if (!mounted) return;
    final shop = ref.read(authProvider).businessName?.trim() ?? '';
    try {
      final bytes = await _pdf(shop, PdfPageFormat.a4);
      if (!mounted) return;
      setState(() {
        _pdfBytes = bytes;
        _pdfShop = shop;
      });
    } catch (_) {
      // The share buttons build the file again if this pass fails.
    }
  }

  Future<Uint8List> _readyPdf(String shopName) async {
    final cached = _pdfBytes;
    if (cached != null && _pdfShop == shopName) return cached;
    final bytes = await _pdf(shopName, PdfPageFormat.a4);
    _pdfBytes = bytes;
    _pdfShop = shopName;
    return bytes;
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Impossible de préparer le reçu.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _money(double amount) => CurrencyFormatter.local(context, amount);

  Future<Uint8List> _pdf(String shopName, PdfPageFormat format) {
    final usd = CurrencyFormatter.usdEquivalentOrNull(
      context,
      widget.figures.total,
    );
    return buildSaleReceiptPdf(
      format: format,
      order: widget.order,
      figures: widget.figures,
      shopName: shopName,
      money: _money,
      usdTotal: usd,
    );
  }

  Future<void> _print(String shopName) {
    return Printing.layoutPdf(
      onLayout: (format) => _pdf(shopName, format),
      name: saleReceiptFilename(widget.order),
    );
  }

  Future<void> _download(String shopName) async {
    final bytes = await _readyPdf(shopName);
    await Printing.sharePdf(
      bytes: bytes,
      filename: saleReceiptFilename(widget.order),
    );
  }

  /// WhatsApp, e-mail, and the share button all hand the PDF to the phone.
  Future<void> _sharePdf(String shopName) async {
    final bytes = await _readyPdf(shopName);
    await shareReceiptFile(
      bytes: bytes,
      filename: saleReceiptFilename(widget.order),
      subject: 'Reçu ${widget.order.orderNumber}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? AppColors.warmWhite : AppColors.nearBlack;
    final muted = isDark ? AppColors.coolGray : AppColors.darkGray;
    final pending = saleReceiptCheckPending(widget.order);
    final shop = ref.watch(authProvider).businessName?.trim() ?? '';
    final order = widget.order;
    final figures = widget.figures;
    final usd = CurrencyFormatter.usdEquivalentOrNull(context, figures.total);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                color: ink,
                onPressed: _busy ? null : widget.onDone,
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      'Reçu',
                      style: AppTextStyles.h2(
                        color: isDark
                            ? AppColors.warmWhite
                            : AppColors.primaryBlue,
                      ),
                    ),
                    if (widget.contextSubtitle != null &&
                        widget.contextSubtitle!.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        widget.contextSubtitle!.trim(),
                        style: AppTextStyles.caption(color: muted),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              AppCloseButton(onPressed: _busy ? null : widget.onDone),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: (pending ? AppColors.amber : AppColors.deepGreen)
                          .withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      pending
                          ? Icons.account_balance_outlined
                          : Icons.check_circle_rounded,
                      color: pending ? AppColors.amber : AppColors.deepGreen,
                      size: 40,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  saleReceiptHeadline(order),
                  key: const Key('receipt-headline'),
                  style: AppTextStyles.h1(color: ink),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  _money(figures.total),
                  style: AppTextStyles.price().copyWith(fontSize: 24),
                  textAlign: TextAlign.center,
                ),
                if (usd != null)
                  Text(
                    usd,
                    style: AppTextStyles.caption(color: muted),
                    textAlign: TextAlign.center,
                  ),
                const SizedBox(height: 4),
                Text(
                  widget.statusLine,
                  style: AppTextStyles.body(color: muted),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                _ReceiptCard(
                  isDark: isDark,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (shop.isNotEmpty)
                        Text(shop, style: AppTextStyles.h3(color: ink)),
                      Text(
                        order.orderNumber,
                        style: AppTextStyles.h3(
                          color: isDark
                              ? AppColors.skyBlue
                              : AppColors.primaryBlue,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${DateFormatter.shortDate(order.createdAt)} · ${DateFormatter.timeOfDay(order.createdAt)}',
                        style: AppTextStyles.caption(color: muted),
                      ),
                      if ((order.recordedBy ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 6),
                        _meta(
                          Icons.badge_outlined,
                          'Caissier : ${order.recordedBy!.trim()}',
                          ink,
                        ),
                      ],
                      const SizedBox(height: 10),
                      if ((order.clientName ?? '').trim().isNotEmpty)
                        _meta(
                          Icons.person_outline,
                          order.clientName!.trim(),
                          ink,
                        ),
                      if ((order.clientPhone ?? '').trim().isNotEmpty)
                        _meta(
                          Icons.phone_outlined,
                          order.clientPhone!.trim(),
                          ink,
                        ),
                      if ((order.clientEmail ?? '').trim().isNotEmpty)
                        _meta(
                          Icons.email_outlined,
                          order.clientEmail!.trim(),
                          ink,
                        ),
                      _meta(
                        Icons.place_outlined,
                        order.fulfillmentMode.label,
                        ink,
                      ),
                      if (order.fulfillmentMode ==
                              RetailFulfillmentMode.delivery &&
                          (order.deliveryLocation ?? '').trim().isNotEmpty)
                        _meta(
                          Icons.local_shipping_outlined,
                          order.deliveryLocation!.trim(),
                          ink,
                        ),
                      const SizedBox(height: 12),
                      Text(
                        'Articles',
                        style: AppTextStyles.h3(color: AppColors.amber),
                      ),
                      const SizedBox(height: 8),
                      for (final line in order.lines) ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    line.productName,
                                    style: AppTextStyles.body(color: ink),
                                  ),
                                  Text(
                                    '${line.quantity} × ${_money(line.unitPriceHtg)}',
                                    style: AppTextStyles.caption(color: muted),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              _money(line.lineTotalHtg),
                              style: AppTextStyles.body(color: ink),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                      const Divider(height: 16),
                      _amountRow(
                        'Sous-total',
                        _money(figures.subtotal),
                        muted,
                        ink,
                      ),
                      if (figures.discountAmount > 0)
                        _amountRow(
                          'Remise (${_pct(figures.discountPercent)} %)',
                          '-${_money(figures.discountAmount)}',
                          muted,
                          AppColors.boldRed,
                        ),
                      if (figures.taxAmount > 0)
                        _amountRow(
                          'Taxe (${_pct(figures.taxPercent)} %)',
                          _money(figures.taxAmount),
                          muted,
                          ink,
                        ),
                      if (figures.serviceAmount > 0)
                        _amountRow(
                          'Frais de service (${_pct(figures.servicePercent)} %)',
                          _money(figures.serviceAmount),
                          muted,
                          ink,
                        ),
                      if (figures.deliveryFee > 0)
                        _amountRow(
                          'Frais de livraison',
                          _money(figures.deliveryFee),
                          muted,
                          ink,
                        ),
                      const SizedBox(height: 4),
                      _amountRow(
                        'TOTAL',
                        _money(figures.total),
                        ink,
                        ink,
                        bold: true,
                      ),
                      const Divider(height: 20),
                      Text(
                        'Paiement',
                        style: AppTextStyles.h3(color: AppColors.amber),
                      ),
                      const SizedBox(height: 8),
                      PaymentMethodBlock(
                        isDark: isDark,
                        paymentMethod: order.paymentMethod,
                        paymentLastFour: order.paymentLastFour,
                        check: order.checkPayment,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                AppButton(
                  key: const Key('receipt-print'),
                  label: 'Imprimer le reçu',
                  icon: Icons.print_outlined,
                  variant: AppButtonVariant.secondary,
                  onPressed: _busy ? null : () => _run(() => _print(shop)),
                ),
                const SizedBox(height: 8),
                AppButton(
                  key: const Key('receipt-download'),
                  label: 'Télécharger le reçu',
                  icon: Icons.download_outlined,
                  variant: AppButtonVariant.secondary,
                  onPressed: _busy ? null : () => _run(() => _download(shop)),
                ),
                const SizedBox(height: 8),
                AppButton(
                  key: const Key('receipt-whatsapp'),
                  label: 'Envoyer le reçu par WhatsApp',
                  icon: Icons.send_outlined,
                  onPressed: _busy ? null : () => _run(() => _sharePdf(shop)),
                ),
                const SizedBox(height: 8),
                AppButton(
                  key: const Key('receipt-email'),
                  label: 'Envoyer le reçu par e-mail',
                  icon: Icons.email_outlined,
                  variant: AppButtonVariant.secondary,
                  onPressed: _busy ? null : () => _run(() => _sharePdf(shop)),
                ),
                const SizedBox(height: 8),
                AppButton(
                  key: const Key('receipt-share'),
                  label: 'Partager le reçu',
                  icon: Icons.share_outlined,
                  variant: AppButtonVariant.secondary,
                  onPressed: _busy ? null : () => _run(() => _sharePdf(shop)),
                ),
                const SizedBox(height: 8),
                Center(
                  child: TextButton(
                    onPressed: _busy ? null : widget.onDone,
                    child: Text(
                      'Terminé',
                      style: AppTextStyles.button(
                        color: isDark
                            ? AppColors.skyBlue
                            : AppColors.primaryBlue,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _meta(IconData icon, String text, Color ink) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: ink.withValues(alpha: 0.7)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text, style: AppTextStyles.body(color: ink)),
          ),
        ],
      ),
    );
  }

  Widget _amountRow(
    String label,
    String value,
    Color labelColor,
    Color valueColor, {
    bool bold = false,
  }) {
    final style = AppTextStyles.body(
      color: valueColor,
    ).copyWith(fontWeight: bold ? FontWeight.w700 : FontWeight.w500);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: AppTextStyles.body(color: labelColor)),
          ),
          Text(value, style: style),
        ],
      ),
    );
  }
}

String _pct(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toStringAsFixed(1);
}

class _ReceiptCard extends StatelessWidget {
  final bool isDark;
  final Widget child;

  const _ReceiptCard({required this.isDark, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkBackground : AppColors.white,
        borderRadius: BorderRadius.circular(AppConstants.radiusCard),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : const Color(0xFFE6E6E6),
        ),
      ),
      child: Padding(padding: const EdgeInsets.all(14), child: child),
    );
  }
}
