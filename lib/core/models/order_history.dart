enum PaymentMethodType { moncash, card, cash, credit, paymentLink }

extension PaymentMethodTypeExt on PaymentMethodType {
  String get label {
    switch (this) {
      case PaymentMethodType.moncash:
        return 'MonCash';
      case PaymentMethodType.card:
        return 'Carte';
      case PaymentMethodType.cash:
        return 'Espèces';
      case PaymentMethodType.credit:
        return 'Crédit';
      case PaymentMethodType.paymentLink:
        return 'Lien de paiement';
    }
  }
}

/// Full details for a payment confirmed via a payment link.
/// Persisted locally after webhook confirmation to avoid extra API calls.
class PaymentLinkDetails {
  /// Processor charge / payment-intent / transaction ID.
  final String transactionId;
  /// When the processor received the payment.
  final DateTime paidAt;
  /// Amount captured in HTG.
  final double amountHtg;
  /// ISO 3166-1 alpha-2 billing country (e.g. "HT", "US").
  final String? country;
  /// Optional note entered by the payer at checkout.
  final String? payerNote;
  /// Card / wallet brand (e.g. "Visa", "Mastercard", "Apple Pay").
  final String? methodBrand;
  /// Last 4 digits of card, or last 4 of mobile-money phone.
  final String? last4;

  const PaymentLinkDetails({
    required this.transactionId,
    required this.paidAt,
    required this.amountHtg,
    this.country,
    this.payerNote,
    this.methodBrand,
    this.last4,
  });
}

/// A single payment line — supports orders settled with multiple methods
/// (e.g. part via link, remainder in cash).
class PaymentLine {
  final PaymentMethodType method;
  final double amountHtg;
  final DateTime paidAt;
  /// Non-null when [method] == [PaymentMethodType.paymentLink].
  final PaymentLinkDetails? linkDetails;
  /// For cash lines: optional staff member who recorded the payment.
  final String? recordedBy;

  const PaymentLine({
    required this.method,
    required this.amountHtg,
    required this.paidAt,
    this.linkDetails,
    this.recordedBy,
  });
}

enum OrderHistoryModule { restaurant, hotel, retail }

class OrderHistoryItem {
  final String name;
  final int quantity;
  final double priceHtg;

  const OrderHistoryItem({
    required this.name,
    required this.quantity,
    required this.priceHtg,
  });

  double get lineTotalHtg => priceHtg * quantity;
}

class OrderHistoryRecord {
  final String receiptNumber;
  final DateTime paidAt;
  final String? receiptName;
  final String source; // e.g. "Table 4", "Chambre 102", "Caisse"
  final List<OrderHistoryItem> items;
  final double serviceChargePercent;
  final double taxPercent;
  final double discountPercent;
  final PaymentMethodType paymentMethod;
  final OrderHistoryModule module;

  /// Retail: true when paid via quote payment link (show service fee like card/MonCash).
  final bool paidViaPaymentLink;

  /// Card / MonCash phone / credit account — last digits for display (optional).
  final String? paymentLastFour;

  /// Multi-payment lines. When set, used for detailed display instead of
  /// the single [paymentMethod] field. Supports orders split across methods
  /// (e.g. partial via link + remainder in cash).
  final List<PaymentLine>? paymentLines;

  const OrderHistoryRecord({
    required this.receiptNumber,
    required this.paidAt,
    this.receiptName,
    required this.source,
    required this.items,
    this.serviceChargePercent = 0,
    this.taxPercent = 0,
    this.discountPercent = 0,
    required this.paymentMethod,
    required this.module,
    this.paidViaPaymentLink = false,
    this.paymentLastFour,
    this.paymentLines,
  });

  /// All distinct payment methods for this record (respects [paymentLines] when set).
  List<PaymentMethodType> get allPaymentMethods {
    if (paymentLines != null && paymentLines!.isNotEmpty) {
      return paymentLines!.map((l) => l.method).toList();
    }
    return [paymentMethod];
  }

  double get subtotal => items.fold(0, (s, i) => s + i.lineTotalHtg);
  double get serviceChargeAmount => subtotal * (serviceChargePercent / 100);
  double get taxAmount => subtotal * (taxPercent / 100);
  double get discountAmount => subtotal * (discountPercent / 100);
  double get total => subtotal + serviceChargeAmount + taxAmount - discountAmount;
}
