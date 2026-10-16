import 'order_history.dart';
import 'retail_fulfillment_mode.dart';

/// Lifecycle status for an active / completed retail order.
enum RetailOrderStatus {
  paid,       // Just paid (all sources) — initial state
  ready,      // Prepared and ready for pickup / delivery
  pickedUp,   // Customer picked up (pickup mode)
  delivered,  // Delivered to customer (delivery mode)
  completed,  // Closed / finalised (in-store or explicit manager action)
}

extension RetailOrderStatusExt on RetailOrderStatus {
  String get label => switch (this) {
        RetailOrderStatus.paid => 'Paid',
        RetailOrderStatus.ready => 'Ready',
        RetailOrderStatus.pickedUp => 'Picked Up',
        RetailOrderStatus.delivered => 'Delivered',
        RetailOrderStatus.completed => 'Completed',
      };

  /// Terminal statuses belong to the "Completed" tab.
  bool get isTerminal =>
      this == RetailOrderStatus.pickedUp ||
      this == RetailOrderStatus.delivered ||
      this == RetailOrderStatus.completed;
}

/// How the payment was initiated.
enum RetailPaymentSource { pos, paymentLink }

extension RetailPaymentSourceExt on RetailPaymentSource {
  String get label => switch (this) {
        RetailPaymentSource.pos => 'POS',
        RetailPaymentSource.paymentLink => 'Payment Link',
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

  /// Card last 4, MonCash phone last 4, or credit account last 4 (mock / gateway).
  final String? paymentLastFour;

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
    this.paymentLastFour,
  });

  double get subtotalHtg => lines.fold(0, (s, l) => s + l.lineTotalHtg);
  double get discountAmountHtg => subtotalHtg * (discountPercent / 100);

  /// Service charge applies for payment link, MonCash, and card (not cash / store credit).
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
    Object? paymentLastFour = _sentinel,
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
      paymentLastFour: paymentLastFour == _sentinel
          ? this.paymentLastFour
          : paymentLastFour as String?,
    );
  }
}

const Object _sentinel = Object();
