import 'order_history.dart';
import 'retail_check_payment.dart';
import 'retail_fulfillment_mode.dart';

/// Lifecycle status for an active / completed retail order.
enum RetailOrderStatus {
  checkPending, // Check received, waiting until it clears
  paid,         // Just paid (all sources) — initial state
  partiallyPaid, // Cash received is less than the sale total
  ready,        // Prepared and ready for pickup / delivery
  pickedUp,     // Customer picked up (pickup mode)
  delivered,    // Delivered to customer (delivery mode)
  completed,    // Closed / finalised (in-store or explicit manager action)
}

/// Status written the moment a sale is paid in full.
///
/// Retrait is finished as soon as it is paid, so it is marked Terminé.
/// En magasin and Livraison stay Payé: the goods still have to be handed over.
RetailOrderStatus statusAfterFullPayment(RetailFulfillmentMode mode) {
  if (mode == RetailFulfillmentMode.inStore ||
      mode == RetailFulfillmentMode.delivery) {
    return RetailOrderStatus.paid;
  }
  return RetailOrderStatus.completed;
}

extension RetailOrderStatusExt on RetailOrderStatus {
  String get label => switch (this) {
        RetailOrderStatus.checkPending => 'Chèque en attente',
        RetailOrderStatus.paid => 'Payé',
        RetailOrderStatus.partiallyPaid => 'Partiellement payée',
        RetailOrderStatus.ready => 'Prêt',
        RetailOrderStatus.pickedUp => 'Retiré',
        RetailOrderStatus.delivered => 'Livré',
        RetailOrderStatus.completed => 'Terminé',
      };

  /// Terminal statuses belong to the "Terminé" tab.
  bool get isTerminal =>
      this == RetailOrderStatus.pickedUp ||
      this == RetailOrderStatus.delivered ||
      this == RetailOrderStatus.completed;
}

/// How the payment was initiated.
enum RetailPaymentSource { pos, paymentLink, storefront }

extension RetailPaymentSourceExt on RetailPaymentSource {
  String get label => switch (this) {
        RetailPaymentSource.pos => 'Caisse',
        RetailPaymentSource.paymentLink => 'Lien de paiement',
        RetailPaymentSource.storefront => 'Vitrine',
      };
}

/// A snapshot of one product line — prices are captured at order creation time
/// so catalog changes never alter historical records.
class RetailOrderLine {
  final String productName;  // snapshot — NOT the live catalog name
  final int productId;       // reference only
  final int quantity;
  final double unitPriceHtg; // snapshot — NOT the live catalog price
  final double? unitPriceUsd;

  const RetailOrderLine({
    required this.productName,
    required this.productId,
    required this.quantity,
    required this.unitPriceHtg,
    this.unitPriceUsd,
  });

  double get lineTotalHtg => unitPriceHtg * quantity;

  Map<String, dynamic> toJson() => {
        'productName': productName,
        'productId': productId,
        'quantity': quantity,
        'unitPriceHtg': unitPriceHtg,
        'unitPriceUsd': unitPriceUsd,
      };

  static RetailOrderLine fromJson(Map<String, dynamic> json) => RetailOrderLine(
        productName: json['productName']?.toString() ?? '',
        productId: (json['productId'] as num?)?.toInt() ?? 0,
        quantity: (json['quantity'] as num?)?.toInt() ?? 1,
        unitPriceHtg: (json['unitPriceHtg'] as num?)?.toDouble() ?? 0,
        unitPriceUsd: (json['unitPriceUsd'] as num?)?.toDouble(),
      );
}

/// A retail order (created from direct POS payment or from a paid quote).
class RetailOrder {
  final String id;
  final String orderNumber;   // e.g. QTE-2026-0001 (from quote) or ORD-2026-0001
  final String? fromQuoteId;  // null for direct POS orders
  final String? clientName;
  final String? clientPhone;
  final String? clientEmail;
  final RetailFulfillmentMode fulfillmentMode;
  final RetailOrderStatus status;
  final RetailPaymentSource paymentSource;
  /// Tender used at checkout (POS or after payment link).
  final PaymentMethodType paymentMethod;
  final List<RetailOrderLine> lines;
  final double discountPercent;
  /// Tax on merchandise subtotal (percent), before discount in amount calc (see getters).
  final double taxPercent;
  /// Service / gratuity on subtotal when [appliesElectronicServiceFee] is true.
  final double serviceChargePercent;
  final double deliveryFee;
  final String? deliveryLocation;
  final String? deliveryPhone;
  final DateTime createdAt;
  final DateTime paidAt;

  /// Clerk or account that recorded the sale. Older sales have none.
  final String? recordedBy;

  /// Cash applied to this sale. Null means the sale was paid in full
  /// (including every sale recorded before partial payments existed).
  final double? amountPaidHtg;

  /// Remainder the cashier left unpaid, using the total confirmed at
  /// checkout. Null means nothing is owed.
  final double? balanceDueHtg;

  /// Card last 4, MonCash phone last 4, or credit account last 4 (mock / gateway).
  final String? paymentLastFour;

  /// Present when the sale was paid by check.
  final RetailCheckPayment? checkPayment;

  const RetailOrder({
    required this.id,
    required this.orderNumber,
    this.fromQuoteId,
    this.clientName,
    this.clientPhone,
    this.clientEmail,
    this.fulfillmentMode = RetailFulfillmentMode.inStore,
    required this.status,
    required this.paymentSource,
    this.paymentMethod = PaymentMethodType.cash,
    required this.lines,
    this.discountPercent = 0,
    this.taxPercent = 0,
    this.serviceChargePercent = 0,
    this.deliveryFee = 0,
    this.deliveryLocation,
    this.deliveryPhone,
    required this.createdAt,
    required this.paidAt,
    this.recordedBy,
    this.amountPaidHtg,
    this.balanceDueHtg,
    this.paymentLastFour,
    this.checkPayment,
  });

  /// Unpaid remainder. Older sales, and any sale without a stored balance, owe nothing.
  double get unpaidBalanceHtg {
    final stored = balanceDueHtg;
    if (stored != null) return stored > 0.009 ? stored : 0;
    final paid = amountPaidHtg;
    if (paid == null) return 0;
    final due = totalHtg - paid;
    return due > 0.009 ? due : 0;
  }

  double get subtotalHtg => lines.fold(0, (s, l) => s + l.lineTotalHtg);
  double get discountAmountHtg => subtotalHtg * (discountPercent / 100);

  /// Service charge applies for a payment link, MonCash, and card.
  /// Cash, check, and store credit do not add it.
  bool get appliesElectronicServiceFee =>
      paymentSource == RetailPaymentSource.paymentLink ||
      paymentMethod == PaymentMethodType.moncash ||
      paymentMethod == PaymentMethodType.card;

  double get serviceChargeAmountHtg =>
      appliesElectronicServiceFee && serviceChargePercent > 0
          ? subtotalHtg * (serviceChargePercent / 100)
          : 0;

  double get taxAmountHtg =>
      taxPercent > 0 ? subtotalHtg * (taxPercent / 100) : 0;

  double get totalHtg =>
      subtotalHtg -
      discountAmountHtg +
      deliveryFee +
      taxAmountHtg +
      serviceChargeAmountHtg;

  RetailOrder copyWith({
    String? id,
    String? orderNumber,
    Object? fromQuoteId = _sentinel,
    Object? clientName = _sentinel,
    Object? clientPhone = _sentinel,
    Object? clientEmail = _sentinel,
    RetailFulfillmentMode? fulfillmentMode,
    RetailOrderStatus? status,
    RetailPaymentSource? paymentSource,
    PaymentMethodType? paymentMethod,
    List<RetailOrderLine>? lines,
    double? discountPercent,
    double? taxPercent,
    double? serviceChargePercent,
    double? deliveryFee,
    Object? deliveryLocation = _sentinel,
    Object? deliveryPhone = _sentinel,
    DateTime? createdAt,
    DateTime? paidAt,
    Object? recordedBy = _sentinel,
    Object? amountPaidHtg = _sentinel,
    Object? balanceDueHtg = _sentinel,
    Object? paymentLastFour = _sentinel,
    Object? checkPayment = _sentinel,
  }) {
    return RetailOrder(
      id: id ?? this.id,
      orderNumber: orderNumber ?? this.orderNumber,
      fromQuoteId:
          fromQuoteId == _sentinel ? this.fromQuoteId : fromQuoteId as String?,
      clientName:
          clientName == _sentinel ? this.clientName : clientName as String?,
      clientPhone:
          clientPhone == _sentinel ? this.clientPhone : clientPhone as String?,
      clientEmail:
          clientEmail == _sentinel ? this.clientEmail : clientEmail as String?,
      fulfillmentMode: fulfillmentMode ?? this.fulfillmentMode,
      status: status ?? this.status,
      paymentSource: paymentSource ?? this.paymentSource,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      lines: lines ?? this.lines,
      discountPercent: discountPercent ?? this.discountPercent,
      taxPercent: taxPercent ?? this.taxPercent,
      serviceChargePercent:
          serviceChargePercent ?? this.serviceChargePercent,
      deliveryFee: deliveryFee ?? this.deliveryFee,
      deliveryLocation: deliveryLocation == _sentinel
          ? this.deliveryLocation
          : deliveryLocation as String?,
      deliveryPhone: deliveryPhone == _sentinel
          ? this.deliveryPhone
          : deliveryPhone as String?,
      createdAt: createdAt ?? this.createdAt,
      paidAt: paidAt ?? this.paidAt,
      recordedBy: recordedBy == _sentinel
          ? this.recordedBy
          : recordedBy as String?,
      amountPaidHtg: amountPaidHtg == _sentinel
          ? this.amountPaidHtg
          : amountPaidHtg as double?,
      balanceDueHtg: balanceDueHtg == _sentinel
          ? this.balanceDueHtg
          : balanceDueHtg as double?,
      paymentLastFour: paymentLastFour == _sentinel
          ? this.paymentLastFour
          : paymentLastFour as String?,
      checkPayment: checkPayment == _sentinel
          ? this.checkPayment
          : checkPayment as RetailCheckPayment?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'orderNumber': orderNumber,
        'fromQuoteId': fromQuoteId,
        'clientName': clientName,
        'clientPhone': clientPhone,
        'clientEmail': clientEmail,
        'fulfillmentMode': fulfillmentMode.name,
        'status': status.name,
        'paymentSource': paymentSource.name,
        'paymentMethod': paymentMethod.name,
        'lines': [for (final line in lines) line.toJson()],
        'discountPercent': discountPercent,
        'taxPercent': taxPercent,
        'serviceChargePercent': serviceChargePercent,
        'deliveryFee': deliveryFee,
        'deliveryLocation': deliveryLocation,
        'deliveryPhone': deliveryPhone,
        'createdAt': createdAt.toIso8601String(),
        'paidAt': paidAt.toIso8601String(),
        'recordedBy': recordedBy,
        'amountPaidHtg': amountPaidHtg,
        'balanceDueHtg': balanceDueHtg,
        'paymentLastFour': paymentLastFour,
        'checkPayment': checkPayment?.toJson(),
      };

  static RetailOrder? fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString() ?? '';
    if (id.isEmpty) return null;
    final linesRaw = json['lines'];
    final lines = <RetailOrderLine>[
      if (linesRaw is List)
        for (final item in linesRaw)
          if (item is Map) RetailOrderLine.fromJson(item.cast<String, dynamic>()),
    ];
    T enumValue<T>(List<T> values, Object? raw, T fallback) {
      final name = raw?.toString();
      for (final value in values) {
        if (value.toString().split('.').last == name) return value;
      }
      return fallback;
    }

    final now = DateTime.now();
    return RetailOrder(
      id: id,
      orderNumber: json['orderNumber']?.toString() ?? id,
      fromQuoteId: json['fromQuoteId']?.toString(),
      clientName: json['clientName']?.toString(),
      clientPhone: json['clientPhone']?.toString(),
      clientEmail: json['clientEmail']?.toString(),
      fulfillmentMode: enumValue(
        RetailFulfillmentMode.values,
        json['fulfillmentMode'],
        RetailFulfillmentMode.inStore,
      ),
      status: enumValue(
        RetailOrderStatus.values,
        json['status'],
        RetailOrderStatus.paid,
      ),
      paymentSource: enumValue(
        RetailPaymentSource.values,
        json['paymentSource'],
        RetailPaymentSource.pos,
      ),
      paymentMethod: enumValue(
        PaymentMethodType.values,
        json['paymentMethod'],
        PaymentMethodType.cash,
      ),
      lines: lines,
      discountPercent: (json['discountPercent'] as num?)?.toDouble() ?? 0,
      taxPercent: (json['taxPercent'] as num?)?.toDouble() ?? 0,
      serviceChargePercent:
          (json['serviceChargePercent'] as num?)?.toDouble() ?? 0,
      deliveryFee: (json['deliveryFee'] as num?)?.toDouble() ?? 0,
      deliveryLocation: json['deliveryLocation']?.toString(),
      deliveryPhone: json['deliveryPhone']?.toString(),
      createdAt: DateTime.tryParse('${json['createdAt']}') ?? now,
      paidAt: DateTime.tryParse('${json['paidAt']}') ?? now,
      recordedBy: _recordedBy(json['recordedBy']),
      amountPaidHtg: (json['amountPaidHtg'] as num?)?.toDouble(),
      balanceDueHtg: (json['balanceDueHtg'] as num?)?.toDouble(),
      paymentLastFour: json['paymentLastFour']?.toString(),
      checkPayment: RetailCheckPayment.fromJson(json['checkPayment']),
    );
  }
}

const Object _sentinel = Object();

String? _recordedBy(Object? raw) {
  final name = raw?.toString().trim() ?? '';
  return name.isEmpty ? null : name;
}
