import '../../core/models/order_history.dart';
import '../../core/models/retail_check_payment.dart';
import '../../core/models/retail_fulfillment_mode.dart';
import '../../core/models/retail_order.dart';
import '../../core/utils/date_formatter.dart';

/// Charges shown on the receipt. Checkout passes the figures the cashier
/// just confirmed so the printed total matches that screen.
class SaleReceiptFigures {
  final double subtotal;
  final double discountPercent;
  final double discountAmount;
  final double taxPercent;
  final double taxAmount;
  final double servicePercent;
  final double serviceAmount;
  final double deliveryFee;
  final double total;

  /// Remainder still owed. Zero means the sale was paid in full.
  final double balanceDue;

  const SaleReceiptFigures({
    required this.subtotal,
    required this.discountPercent,
    required this.discountAmount,
    required this.taxPercent,
    required this.taxAmount,
    required this.servicePercent,
    required this.serviceAmount,
    required this.deliveryFee,
    required this.total,
    this.balanceDue = 0,
  });

  double get amountPaid {
    final paid = total - balanceDue;
    if (paid <= 0) return 0;
    return paid;
  }

  bool get hasBalanceDue => balanceDue > 0.009;

  factory SaleReceiptFigures.fromOrder(RetailOrder order) {
    return SaleReceiptFigures(
      subtotal: order.subtotalHtg,
      discountPercent: order.discountPercent,
      discountAmount: order.discountAmountHtg,
      taxPercent: order.taxPercent,
      taxAmount: order.taxAmountHtg,
      servicePercent: order.serviceChargePercent,
      serviceAmount: order.serviceChargeAmountHtg,
      deliveryFee: order.deliveryFee,
      total: order.totalHtg,
      balanceDue: order.unpaidBalanceHtg,
    );
  }
}

/// A check that was recorded and not cleared is not a confirmed payment.
bool saleReceiptCheckPending(RetailOrder order) {
  final check = order.checkPayment;
  return order.paymentMethod == PaymentMethodType.check &&
      check != null &&
      !check.cleared;
}

String saleReceiptHeadline(RetailOrder order) {
  if (saleReceiptCheckPending(order)) return 'Chèque en attente';
  if (order.status == RetailOrderStatus.partiallyPaid ||
      order.unpaidBalanceHtg > 0.009) {
    return 'Paiement partiel';
  }
  return 'Paiement confirmé !';
}

String saleReceiptFilename(RetailOrder order) {
  final safe = order.orderNumber.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
  return 'recu-${safe.isEmpty ? 'vente' : safe}.pdf';
}

/// Digits for wa.me. An 8-digit Haiti number gets the 509 prefix.
String? receiptWhatsAppPhone(String? raw) {
  if (raw == null) return null;
  var digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.startsWith('00')) digits = digits.substring(2);
  if (digits.isEmpty) return null;
  if (digits.length == 8) digits = '509$digits';
  if (digits.length < 10) return null;
  return digits;
}

String whatsAppReceiptUrl({String? phone, required String text}) {
  final encoded = Uri.encodeComponent(text);
  final number = receiptWhatsAppPhone(phone);
  if (number == null) return 'https://wa.me/?text=$encoded';
  return 'https://wa.me/$number?text=$encoded';
}

String emailReceiptUrl({
  String? to,
  required String subject,
  required String body,
}) {
  return Uri(
    scheme: 'mailto',
    path: (to ?? '').trim(),
    queryParameters: {'subject': subject, 'body': body},
  ).toString();
}

String _percent(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toStringAsFixed(1);
}

String _moneyLine(String label, String amount) => '$label : $amount';

/// Plain-text receipt used for WhatsApp, e-mail, and the phone share sheet.
String saleReceiptText({
  required RetailOrder order,
  required SaleReceiptFigures figures,
  required String shopName,
  required String Function(double amount) money,
  String? usdTotal,
}) {
  final lines = <String>[];
  final shop = shopName.trim();
  if (shop.isNotEmpty) lines.add(shop);
  lines.add('Reçu ${order.orderNumber}');
  lines.add(
    '${DateFormatter.shortDate(order.createdAt)} ${DateFormatter.timeOfDay(order.createdAt)}',
  );
  lines.add(saleReceiptHeadline(order));
  final clerk = order.recordedBy?.trim() ?? '';
  if (clerk.isNotEmpty) lines.add('Caissier : $clerk');
  lines.add('');

  final client = order.clientName?.trim() ?? '';
  if (client.isNotEmpty) lines.add('Client : $client');
  final phone = order.clientPhone?.trim() ?? '';
  if (phone.isNotEmpty) lines.add('Téléphone : $phone');
  final email = order.clientEmail?.trim() ?? '';
  if (email.isNotEmpty) lines.add('E-mail : $email');
  lines.add(order.fulfillmentMode.label);
  if (order.fulfillmentMode == RetailFulfillmentMode.delivery) {
    final place = order.deliveryLocation?.trim() ?? '';
    if (place.isNotEmpty) lines.add('Adresse : $place');
    final deliveryPhone = order.deliveryPhone?.trim() ?? '';
    if (deliveryPhone.isNotEmpty) lines.add('Tél. livraison : $deliveryPhone');
  }
  lines.add('');
  lines.add('Articles');
  for (final line in order.lines) {
    lines.add('${line.quantity} × ${line.productName}');
    lines.add('${money(line.unitPriceHtg)}    ${money(line.lineTotalHtg)}');
  }
  lines.add('');
  lines.add(_moneyLine('Sous-total', money(figures.subtotal)));
  if (figures.discountAmount > 0) {
    lines.add(
      _moneyLine(
        'Remise (${_percent(figures.discountPercent)} %)',
        '-${money(figures.discountAmount)}',
      ),
    );
  }
  if (figures.taxAmount > 0) {
    lines.add(
      _moneyLine(
        'Taxe (${_percent(figures.taxPercent)} %)',
        money(figures.taxAmount),
      ),
    );
  }
  if (figures.serviceAmount > 0) {
    lines.add(
      _moneyLine(
        'Frais de service (${_percent(figures.servicePercent)} %)',
        money(figures.serviceAmount),
      ),
    );
  }
  if (figures.deliveryFee > 0) {
    lines.add(_moneyLine('Frais de livraison', money(figures.deliveryFee)));
  }
  final total = money(figures.total);
  lines.add(
    _moneyLine('TOTAL', usdTotal == null ? total : '$total ($usdTotal)'),
  );
  if (figures.hasBalanceDue) {
    lines.add(_moneyLine('Payé', money(figures.amountPaid)));
    lines.add(_moneyLine('SOLDE IMPAYÉ', money(figures.balanceDue)));
  }
  lines.add('');
  lines.add('Paiement : ${order.paymentMethod.label}');
  final check = order.checkPayment;
  if (check != null) {
    lines.addAll(_checkLines(check));
  }
  return lines.join('\n');
}

List<String> _checkLines(RetailCheckPayment check) {
  return [
    'N° chèque : ${check.number}',
    'Banque : ${check.bank}',
    'Tireur : ${check.payerName}',
    'Date du chèque : ${DateFormatter.shortDate(check.date)}',
    check.clearanceLabel,
    if (check.imageBytes != null) 'Photo du chèque enregistrée.',
  ];
}
