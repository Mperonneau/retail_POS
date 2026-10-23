import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../providers/device_session_provider.dart';
import '../providers/staff_session_provider.dart';
import '../utils/operator_name.dart';
import '../services/local_store.dart';

import '../models/check_credit.dart';
import '../models/customer.dart';
import '../models/order_history.dart';
import '../models/retail_fulfillment_mode.dart';
import '../models/retail_order.dart';

// ──────────────────────────────────────────────────────────────────────────────
// Seed data — 12 orders (6 active, 6 completed)
// ──────────────────────────────────────────────────────────────────────────────

final _mockRetailOrdersSeed = <RetailOrder>[
  // ── ACTIVE ORDERS ──────────────────────────────────────────────────────────

  // Paid via payment link — delivery in progress
  RetailOrder(
    id: 'ord_1',
    orderNumber: 'QTE-2026-0001',
    fromQuoteId: 'qte_1',
    clientName: 'Restaurant Ti Kay',
    clientPhone: '+509 4123-5678',
    fulfillmentMode: RetailFulfillmentMode.delivery,
    status: RetailOrderStatus.paid,
    paymentSource: RetailPaymentSource.paymentLink,
    paymentMethod: PaymentMethodType.card,
    taxPercent: 10,
    serviceChargePercent: 5,
    lines: const [
      RetailOrderLine(
        productName: 'Riz Blanc 25kg',
        productId: 1,
        quantity: 2,
        unitPriceHtg: 3200,
        unitPriceUsd: 32,
      ),
      RetailOrderLine(
        productName: 'Prestige Beer 330ml',
        productId: 5,
        quantity: 24,
        unitPriceHtg: 180,
        unitPriceUsd: 1.80,
      ),
    ],
    discountPercent: 5,
    deliveryFee: 500,
    deliveryLocation: 'Delmas 19',
    deliveryPhone: '+509 4123-5678',
    paymentLastFour: '4242',
    createdAt: DateTime.now().subtract(const Duration(hours: 26)),
    paidAt: DateTime.now().subtract(const Duration(hours: 1, minutes: 20)),
  ),

  // Paid via payment link — pickup, now ready
  RetailOrder(
    id: 'ord_2',
    orderNumber: 'QTE-2026-0003',
    fromQuoteId: 'qte_3',
    clientName: 'Jean Michel',
    clientPhone: '+1 (786) 555-0123',
    clientEmail: 'jmichel.hti@gmail.com',
    fulfillmentMode: RetailFulfillmentMode.pickup,
    status: RetailOrderStatus.ready,
    paymentSource: RetailPaymentSource.paymentLink,
    paymentMethod: PaymentMethodType.card,
    taxPercent: 10,
    serviceChargePercent: 5,
    lines: const [
      RetailOrderLine(
        productName: 'Ampoule LED 9W',
        productId: 11,
        quantity: 10,
        unitPriceHtg: 350,
        unitPriceUsd: 3.50,
      ),
      RetailOrderLine(
        productName: 'Chargeur USB-C',
        productId: 12,
        quantity: 3,
        unitPriceHtg: 800,
        unitPriceUsd: 8.00,
      ),
    ],
    paymentLastFour: '0123',
    createdAt: DateTime.now().subtract(const Duration(days: 1)),
    paidAt: DateTime.now().subtract(const Duration(hours: 18)),
  ),

  // POS sale — delivery, paid, preparing
  RetailOrder(
    id: 'ord_3',
    orderNumber: 'ORD-2026-0045',
    clientName: 'Boutique Madame Pierre',
    clientPhone: '+509 3456-7890',
    fulfillmentMode: RetailFulfillmentMode.delivery,
    status: RetailOrderStatus.paid,
    paymentSource: RetailPaymentSource.pos,
    paymentMethod: PaymentMethodType.moncash,
    taxPercent: 10,
    serviceChargePercent: 5,
    lines: const [
      RetailOrderLine(
        productName: 'Huile Végétale 1L',
        productId: 2,
        quantity: 6,
        unitPriceHtg: 600,
      ),
      RetailOrderLine(
        productName: 'Sucre 5kg',
        productId: 3,
        quantity: 3,
        unitPriceHtg: 800,
      ),
      RetailOrderLine(
        productName: 'Farine de Blé 5kg',
        productId: 4,
        quantity: 4,
        unitPriceHtg: 700,
      ),
    ],
    deliveryFee: 300,
    deliveryLocation: 'Pétion-Ville, Rue Métellus',
    deliveryPhone: '+509 3456-7890',
    paymentLastFour: '7890',
    createdAt: DateTime.now().subtract(const Duration(hours: 4)),
    paidAt: DateTime.now().subtract(const Duration(hours: 4)),
  ),

  // POS pickup — ready for customer
  RetailOrder(
    id: 'ord_4',
    orderNumber: 'ORD-2026-0044',
    clientName: 'École Nationale No.3',
    clientPhone: '+509 2222-3333',
    fulfillmentMode: RetailFulfillmentMode.pickup,
    status: RetailOrderStatus.ready,
    paymentSource: RetailPaymentSource.pos,
    paymentMethod: PaymentMethodType.cash,
    taxPercent: 10,
    lines: const [
      RetailOrderLine(
        productName: 'Cahier 100 pages',
        productId: 15,
        quantity: 50,
        unitPriceHtg: 150,
      ),
      RetailOrderLine(
        productName: 'Savon Dettol 100g',
        productId: 8,
        quantity: 12,
        unitPriceHtg: 150,
      ),
    ],
    discountPercent: 10,
    createdAt: DateTime.now().subtract(const Duration(hours: 6)),
    paidAt: DateTime.now().subtract(const Duration(hours: 6)),
  ),

  // Payment link — delivery — just paid, not yet ready
  RetailOrder(
    id: 'ord_5',
    orderNumber: 'QTE-2026-0007',
    fromQuoteId: 'qte_7',
    clientName: 'Philippe Moreau',
    clientPhone: '+1 (514) 555-9876',
    clientEmail: 'pmoreau.htmd@outlook.com',
    fulfillmentMode: RetailFulfillmentMode.delivery,
    status: RetailOrderStatus.paid,
    paymentSource: RetailPaymentSource.paymentLink,
    paymentMethod: PaymentMethodType.moncash,
    taxPercent: 10,
    serviceChargePercent: 5,
    lines: const [
      RetailOrderLine(
        productName: 'Eau Culligan 18L',
        productId: 7,
        quantity: 5,
        unitPriceHtg: 280,
        unitPriceUsd: 2.80,
      ),
      RetailOrderLine(
        productName: 'Lessive Ariel 1kg',
        productId: 9,
        quantity: 4,
        unitPriceHtg: 450,
        unitPriceUsd: 4.50,
      ),
    ],
    discountPercent: 0,
    deliveryFee: 800,
    deliveryLocation: 'Tabarre 47 — c/o Famille Moreau',
    deliveryPhone: '+509 3798-1234',
    paymentLastFour: '9876',
    createdAt: DateTime.now().subtract(const Duration(hours: 5)),
    paidAt: DateTime.now().subtract(const Duration(minutes: 45)),
  ),

  // POS in-store — paid just now, not yet completed (staff needs to action)
  RetailOrder(
    id: 'ord_6',
    orderNumber: 'ORD-2026-0046',
    clientName: 'Hôtel Roi Christophe',
    clientPhone: '+509 3600-0000',
    fulfillmentMode: RetailFulfillmentMode.inStore,
    status: RetailOrderStatus.paid,
    paymentSource: RetailPaymentSource.pos,
    paymentMethod: PaymentMethodType.cash,
    taxPercent: 10,
    lines: const [
      RetailOrderLine(
        productName: 'Bougies (paquet 10)',
        productId: 10,
        quantity: 8,
        unitPriceHtg: 200,
      ),
      RetailOrderLine(
        productName: 'Ampoule LED 9W',
        productId: 11,
        quantity: 20,
        unitPriceHtg: 350,
      ),
    ],
    createdAt: DateTime.now().subtract(const Duration(minutes: 25)),
    paidAt: DateTime.now().subtract(const Duration(minutes: 25)),
  ),

  // ── COMPLETED ORDERS ───────────────────────────────────────────────────────

  RetailOrder(
    id: 'ord_7',
    orderNumber: 'QTE-2026-0002',
    fromQuoteId: 'qte_2',
    clientName: 'Roseline Janvier',
    clientPhone: '+509 4567-8901',
    clientEmail: 'roseline.j@yahoo.fr',
    fulfillmentMode: RetailFulfillmentMode.pickup,
    status: RetailOrderStatus.pickedUp,
    paymentSource: RetailPaymentSource.paymentLink,
    paymentMethod: PaymentMethodType.card,
    taxPercent: 10,
    serviceChargePercent: 5,
    lines: const [
      RetailOrderLine(
        productName: 'Shampoo Pantene 400ml',
        productId: 13,
        quantity: 4,
        unitPriceHtg: 600,
      ),
      RetailOrderLine(
        productName: 'Dentifrice Colgate 75ml',
        productId: 14,
        quantity: 6,
        unitPriceHtg: 180,
      ),
    ],
    paymentLastFour: '4412',
    createdAt: DateTime.now().subtract(const Duration(days: 3)),
    paidAt: DateTime.now().subtract(const Duration(days: 2, hours: 8)),
  ),

  RetailOrder(
    id: 'ord_8',
    orderNumber: 'ORD-2026-0038',
    clientName: 'Supermarché Caraïbe',
    clientPhone: '+509 2811-0000',
    fulfillmentMode: RetailFulfillmentMode.delivery,
    status: RetailOrderStatus.delivered,
    paymentSource: RetailPaymentSource.pos,
    paymentMethod: PaymentMethodType.moncash,
    taxPercent: 10,
    serviceChargePercent: 5,
    lines: const [
      RetailOrderLine(
        productName: 'Riz Blanc 25kg',
        productId: 1,
        quantity: 5,
        unitPriceHtg: 3200,
      ),
      RetailOrderLine(
        productName: 'Huile Végétale 1L',
        productId: 2,
        quantity: 12,
        unitPriceHtg: 600,
      ),
    ],
    deliveryFee: 600,
    deliveryLocation: 'Centre-Ville, Ave Jean-Jacques Dessalines',
    deliveryPhone: '+509 2811-0001',
    paymentLastFour: '0001',
    createdAt: DateTime.now().subtract(const Duration(days: 4)),
    paidAt: DateTime.now().subtract(const Duration(days: 4)),
  ),

  RetailOrder(
    id: 'ord_9',
    orderNumber: 'ORD-2026-0031',
    clientName: 'Marc-Antoine Fils',
    clientPhone: '+509 3789-0123',
    fulfillmentMode: RetailFulfillmentMode.inStore,
    status: RetailOrderStatus.completed,
    paymentSource: RetailPaymentSource.pos,
    paymentMethod: PaymentMethodType.cash,
    taxPercent: 10,
    lines: const [
      RetailOrderLine(
        productName: 'Prestige Beer 330ml',
        productId: 5,
        quantity: 48,
        unitPriceHtg: 180,
      ),
      RetailOrderLine(
        productName: 'Coca-Cola 355ml',
        productId: 6,
        quantity: 24,
        unitPriceHtg: 120,
      ),
    ],
    discountPercent: 5,
    createdAt: DateTime.now().subtract(const Duration(days: 6)),
    paidAt: DateTime.now().subtract(const Duration(days: 6)),
  ),

  RetailOrder(
    id: 'ord_10',
    orderNumber: 'QTE-2026-0009',
    fromQuoteId: 'qte_9',
    clientName: 'Restaurant Lakay',
    clientPhone: '+509 3444-5555',
    clientEmail: 'commande@restaurantlakay.ht',
    fulfillmentMode: RetailFulfillmentMode.delivery,
    status: RetailOrderStatus.delivered,
    paymentSource: RetailPaymentSource.paymentLink,
    paymentMethod: PaymentMethodType.card,
    taxPercent: 10,
    serviceChargePercent: 5,
    lines: const [
      RetailOrderLine(
        productName: 'Riz Blanc 25kg',
        productId: 1,
        quantity: 3,
        unitPriceHtg: 3200,
      ),
      RetailOrderLine(
        productName: 'Huile Végétale 1L',
        productId: 2,
        quantity: 10,
        unitPriceHtg: 600,
      ),
      RetailOrderLine(
        productName: 'Sucre 5kg',
        productId: 3,
        quantity: 5,
        unitPriceHtg: 800,
      ),
    ],
    discountPercent: 8,
    deliveryFee: 700,
    deliveryLocation: 'Croix-des-Bouquets, Route Nationale 3',
    deliveryPhone: '+509 3444-5556',
    paymentLastFour: '9912',
    createdAt: DateTime.now().subtract(const Duration(days: 10)),
    paidAt: DateTime.now().subtract(const Duration(days: 9, hours: 16)),
  ),

  RetailOrder(
    id: 'ord_11',
    orderNumber: 'ORD-2026-0025',
    clientName: 'Groupe scolaire Ste-Anne',
    clientPhone: '+509 2555-6666',
    fulfillmentMode: RetailFulfillmentMode.pickup,
    status: RetailOrderStatus.pickedUp,
    paymentSource: RetailPaymentSource.pos,
    paymentMethod: PaymentMethodType.cash,
    taxPercent: 10,
    lines: const [
      RetailOrderLine(
        productName: 'Cahier 100 pages',
        productId: 15,
        quantity: 100,
        unitPriceHtg: 150,
      ),
      RetailOrderLine(
        productName: 'Savon Dettol 100g',
        productId: 8,
        quantity: 30,
        unitPriceHtg: 150,
      ),
    ],
    discountPercent: 10,
    createdAt: DateTime.now().subtract(const Duration(days: 12)),
    paidAt: DateTime.now().subtract(const Duration(days: 12)),
  ),

  RetailOrder(
    id: 'ord_12',
    orderNumber: 'QTE-2026-0013',
    fromQuoteId: 'qte_13',
    clientName: 'Famille Desroches',
    clientPhone: '+509 3222-7777',
    fulfillmentMode: RetailFulfillmentMode.inStore,
    status: RetailOrderStatus.completed,
    paymentSource: RetailPaymentSource.paymentLink,
    paymentMethod: PaymentMethodType.moncash,
    taxPercent: 10,
    serviceChargePercent: 5,
    lines: const [
      RetailOrderLine(
        productName: 'Ampoule LED 9W',
        productId: 11,
        quantity: 6,
        unitPriceHtg: 350,
      ),
      RetailOrderLine(
        productName: 'Bougies (paquet 10)',
        productId: 10,
        quantity: 3,
        unitPriceHtg: 200,
      ),
    ],
    paymentLastFour: '7777',
    createdAt: DateTime.now().subtract(const Duration(days: 8)),
    paidAt: DateTime.now().subtract(const Duration(days: 7, hours: 20)),
  ),
];

// ──────────────────────────────────────────────────────────────────────────────
// State notifier + provider
// ──────────────────────────────────────────────────────────────────────────────

class RetailOrdersNotifier extends StateNotifier<List<RetailOrder>> {
  RetailOrdersNotifier(this._ref) : super(_mockRetailOrdersSeed) {
    Future<void>.microtask(_hydrate);
  }

  final Ref _ref;

  Future<void> _hydrate() async {
    final saved = await LocalStore.instance.loadExtraOrders();
    if (saved.isEmpty) return;
    final known = state.map((order) => order.id).toSet();
    final extras = [
      for (final order in saved)
        if (!known.contains(order.id)) order,
    ];
    if (extras.isEmpty) return;
    state = [...extras, ...state];
  }

  /// Marks the check cleared. A waiting remainder is posted as credit.
  /// Returns a French error when the credit cannot be posted.
  String? clearCheck(String id) {
    final order = _order(id);
    final check = order?.checkPayment;
    if (order == null || check == null || check.cleared || check.refused) {
      return null;
    }
    final now = DateTime.now();
    final remainder = order.unpaidBalanceHtg;
    if (remainder > 0.009) {
      final error = _guardCredit(
        customerId: check.creditCustomerId,
        remainder: remainder,
        exceptOrderId: order.id,
      );
      if (error != null) return error;
      _ref.read(customerProvider.notifier).postCharge(
            customerId: check.creditCustomerId!,
            amountHtg: remainder,
            cashierName: _operator(),
            linkedOrderId: order.id,
            description:
                'Solde du chèque ${order.orderNumber} après compensation',
          );
    }
    final updated = order.copyWith(
      status: order.status == RetailOrderStatus.checkPending
          ? (remainder > 0.009
              ? RetailOrderStatus.partiallyPaid
              : RetailOrderStatus.paid)
          : order.status,
      paidAt: now,
      checkPayment: check.copyWith(
        cleared: true,
        clearedAt: now,
        clearedBy: _operator(),
        creditPosted: remainder > 0.009,
      ),
    );
    _replace(updated, statusChange: true);
    return null;
  }

  /// Updates the check after it was recorded. A pending remainder stays
  /// reserved. A cleared remainder is adjusted on the client account.
  String? updateCheck({
    required String orderId,
    required double amountHtg,
    required String number,
    required String bank,
    required String payerName,
    required DateTime date,
    String? imageDataUrl,
    String? creditCustomerId,
  }) {
    final order = _order(orderId);
    final check = order?.checkPayment;
    if (order == null || check == null) return 'Ce chèque est introuvable.';
    if (check.refused) return 'Ce chèque a été refusé.';
    final n = number.trim();
    final b = bank.trim();
    final payer = payerName.trim();
    if (n.isEmpty || b.isEmpty || payer.isEmpty) {
      return 'Le numéro, la banque et le tireur sont requis.';
    }
    if (amountHtg < 1) {
      return 'Le montant du chèque doit être d\'au moins 1 HTG.';
    }
    final saleTotal = checkSaleTotal(order);
    if (amountHtg - saleTotal > 0.009) {
      return 'Le chèque ne peut pas dépasser le total.';
    }
    final remainder =
        saleTotal - amountHtg > 0.009 ? saleTotal - amountHtg : 0.0;
    final customerId = (creditCustomerId ?? check.creditCustomerId)?.trim();
    final photo = (imageDataUrl ?? check.imageDataUrl).trim();
    if (photo.isEmpty) return 'La photo du chèque est requise.';

    if (!check.cleared) {
      if (remainder > 0.009) {
        final error = _guardCredit(
          customerId: customerId,
          remainder: remainder,
          exceptOrderId: order.id,
        );
        if (error != null) return error;
      }
      _replace(
        order.copyWith(
          amountPaidHtg: amountHtg,
          balanceDueHtg: remainder,
          checkPayment: check.copyWith(
            number: n,
            bank: b,
            payerName: payer,
            date: DateTime(date.year, date.month, date.day),
            imageDataUrl: photo,
            amountHtg: amountHtg,
            creditCustomerId: remainder > 0.009 ? customerId : null,
            creditPosted: false,
          ),
        ),
      );
      return null;
    }

    final oldRemainder = order.unpaidBalanceHtg;
    final delta = remainder - oldRemainder;
    if (delta > 0.009) {
      final error = _guardCredit(
        customerId: customerId,
        remainder: delta,
        exceptOrderId: order.id,
      );
      if (error != null) return error;
      _ref.read(customerProvider.notifier).postCharge(
            customerId: customerId!,
            amountHtg: delta,
            cashierName: _operator(),
            linkedOrderId: order.id,
            description: 'Ajustement du chèque ${order.orderNumber}',
          );
    } else if (delta < -0.009 && check.creditPosted && customerId != null) {
      _ref.read(customerProvider.notifier).postPayment(
            customerId: customerId,
            amountHtg: -delta,
            cashierName: _operator(),
            description: 'Ajustement du chèque ${order.orderNumber}',
            paymentMethodLabel: 'Chèque',
          );
    }
    final status = remainder > 0.009
        ? (order.status == RetailOrderStatus.paid ||
                order.status == RetailOrderStatus.checkPending
            ? RetailOrderStatus.partiallyPaid
            : order.status)
        : (order.status == RetailOrderStatus.partiallyPaid
            ? RetailOrderStatus.paid
            : order.status);
    _replace(
      order.copyWith(
        status: status,
        amountPaidHtg: amountHtg,
        balanceDueHtg: remainder,
        checkPayment: check.copyWith(
          number: n,
          bank: b,
          payerName: payer,
          date: DateTime(date.year, date.month, date.day),
          imageDataUrl: photo,
          amountHtg: amountHtg,
          creditCustomerId: remainder > 0.009 ? customerId : check.creditCustomerId,
          creditPosted: remainder > 0.009 || check.creditPosted,
        ),
      ),
    );
    return null;
  }

  /// Drops a pending check. The reserved credit is released and the sale
  /// stays unpaid for its full amount.
  void refuseCheck(String id) {
    final order = _order(id);
    final check = order?.checkPayment;
    if (order == null || check == null || check.cleared || check.refused) {
      return;
    }
    final total = checkSaleTotal(order);
    _replace(
      order.copyWith(
        status: RetailOrderStatus.partiallyPaid,
        amountPaidHtg: 0.0,
        balanceDueHtg: total,
        checkPayment: check.copyWith(
          refused: true,
          creditCustomerId: null,
          creditPosted: false,
        ),
      ),
      statusChange: true,
    );
  }

  RetailOrder? _order(String id) {
    for (final order in state) {
      if (order.id == id) return order;
    }
    return null;
  }

  String _operator() {
    return currentOperatorName(
      staffName: _ref.read(staffSessionProvider)?.employeeName,
      accountName: _ref.read(authProvider).userName,
    );
  }

  String? _guardCredit({
    required String? customerId,
    required double remainder,
    required String exceptOrderId,
  }) {
    final customers = _ref.read(customerProvider).customers;
    Customer? customer;
    for (final item in customers) {
      if (item.id == customerId) {
        customer = item;
        break;
      }
    }
    return checkCreditBlockReason(
      customer: customer,
      remainder: remainder,
      orders: state,
      postedBalance: customer == null
          ? 0
          : _ref.read(customerProvider).balanceFor(customer.id),
      exceptOrderId: exceptOrderId,
    );
  }

  void _replace(RetailOrder updated, {bool statusChange = false}) {
    state = [
      for (final order in state)
        if (order.id == updated.id) updated else order,
    ];
    _ref
        .read(deviceSessionProvider.notifier)
        .captureOrder(updated, statusChange: statusChange);
  }

  void updateStatus(String id, RetailOrderStatus status) {
    state = [
      for (final o in state)
        if (o.id == id) o.copyWith(status: status) else o,
    ];
    final updated = state.where((order) => order.id == id).firstOrNull;
    if (updated != null) {
      _ref
          .read(deviceSessionProvider.notifier)
          .captureOrder(updated, statusChange: true);
    }
  }

  void add(RetailOrder order) {
    state = [order, ...state];
    _ref.read(deviceSessionProvider.notifier).captureOrder(order);
  }

  List<RetailOrder> get active =>
      state.where((o) => !o.status.isTerminal).toList()
        ..sort((a, b) => b.paidAt.compareTo(a.paidAt));

  List<RetailOrder> get completed =>
      state.where((o) => o.status.isTerminal).toList()
        ..sort((a, b) => b.paidAt.compareTo(a.paidAt));
}

final retailOrdersProvider =
    StateNotifierProvider<RetailOrdersNotifier, List<RetailOrder>>(
  (ref) => RetailOrdersNotifier(ref),
);
