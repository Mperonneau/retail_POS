import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'customer.dart';

// ─── Enums ────────────────────────────────────────────────────────────────────

enum PayLinkStatus {
  /// Sent to payer, awaiting payment.
  active,

  /// Payment received — amount has been issued as store credit to the client.
  paidUnused,

  /// Canceled or expired — no longer actionable.
  inactive,
}

enum PayLinkChannel { whatsApp, email, sms }

enum PayLinkSource { standalone, orderBill }

// ─── Model ────────────────────────────────────────────────────────────────────

class PayLink {
  final String id;
  final String customerId;
  final String customerName;
  final String customerPhone;

  /// Email of the payer (optional — separate from customer email).
  final String? payerEmail;

  final double amountHtg;

  final PayLinkStatus status;
  final PayLinkChannel channel;
  final PayLinkSource source;

  /// Phone number or email the link was last sent to.
  final String sentTo;

  final DateTime createdAt;
  final DateTime? paidAt;
  final DateTime? canceledAt;
  final DateTime? expiresAt;

  /// Reference number shown on receipts (e.g. PL-2026-0001).
  final String reference;

  final String createdBy;
  final String? note;
  final String? linkedOrderId;

  // ─ Payment confirmation (filled in when status → paidUnused) ─
  final String? paymentTransactionId;
  final String? paymentLast4;
  final String? paymentMethod;

  /// Who canceled the link (if inactive).
  final String? canceledBy;

  const PayLink({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.customerPhone,
    this.payerEmail,
    required this.amountHtg,
    required this.status,
    required this.channel,
    this.source = PayLinkSource.standalone,
    required this.sentTo,
    required this.createdAt,
    this.paidAt,
    this.canceledAt,
    this.expiresAt,
    required this.reference,
    this.createdBy = 'Staff',
    this.note,
    this.linkedOrderId,
    this.paymentTransactionId,
    this.paymentLast4,
    this.paymentMethod,
    this.canceledBy,
  });

  bool get isExpired {
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(expiresAt!);
  }

  PayLink copyWith({
    String? id,
    String? customerId,
    String? customerName,
    String? customerPhone,
    Object? payerEmail = _sentinel,
    double? amountHtg,
    PayLinkStatus? status,
    PayLinkChannel? channel,
    PayLinkSource? source,
    String? sentTo,
    DateTime? createdAt,
    Object? paidAt = _sentinel,
    Object? canceledAt = _sentinel,
    Object? expiresAt = _sentinel,
    String? reference,
    String? createdBy,
    Object? note = _sentinel,
    Object? linkedOrderId = _sentinel,
    Object? paymentTransactionId = _sentinel,
    Object? paymentLast4 = _sentinel,
    Object? paymentMethod = _sentinel,
    Object? canceledBy = _sentinel,
  }) {
    return PayLink(
      id: id ?? this.id,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      payerEmail: payerEmail == _sentinel ? this.payerEmail : payerEmail as String?,
      amountHtg: amountHtg ?? this.amountHtg,
      status: status ?? this.status,
      channel: channel ?? this.channel,
      source: source ?? this.source,
      sentTo: sentTo ?? this.sentTo,
      createdAt: createdAt ?? this.createdAt,
      paidAt: paidAt == _sentinel ? this.paidAt : paidAt as DateTime?,
      canceledAt: canceledAt == _sentinel ? this.canceledAt : canceledAt as DateTime?,
      expiresAt: expiresAt == _sentinel ? this.expiresAt : expiresAt as DateTime?,
      reference: reference ?? this.reference,
      createdBy: createdBy ?? this.createdBy,
      note: note == _sentinel ? this.note : note as String?,
      linkedOrderId: linkedOrderId == _sentinel ? this.linkedOrderId : linkedOrderId as String?,
      paymentTransactionId: paymentTransactionId == _sentinel
          ? this.paymentTransactionId
          : paymentTransactionId as String?,
      paymentLast4: paymentLast4 == _sentinel ? this.paymentLast4 : paymentLast4 as String?,
      paymentMethod: paymentMethod == _sentinel ? this.paymentMethod : paymentMethod as String?,
      canceledBy: canceledBy == _sentinel ? this.canceledBy : canceledBy as String?,
    );
  }
}

// ─── State ────────────────────────────────────────────────────────────────────

class PayLinkState {
  final List<PayLink> links;

  const PayLinkState({this.links = const []});

  List<PayLink> get active =>
      links.where((l) => l.status == PayLinkStatus.active).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  List<PayLink> get paid =>
      links.where((l) => l.status == PayLinkStatus.paidUnused).toList()
        ..sort((a, b) => b.paidAt!.compareTo(a.paidAt!));

  List<PayLink> get inactive =>
      links.where((l) => l.status == PayLinkStatus.inactive).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  double get totalActivePendingHtg =>
      active.fold(0, (s, l) => s + l.amountHtg);

  double get totalPaidHtg =>
      paid.fold(0, (s, l) => s + l.amountHtg);
}

// ─── Notifier ─────────────────────────────────────────────────────────────────

class PayLinkNotifier extends StateNotifier<PayLinkState> {
  PayLinkNotifier(
    super.initial,
    this._ref,
    this._customerProvider,
  );

  final Ref _ref;
  final StateNotifierProvider<CustomerNotifier, CustomerState> _customerProvider;
  int _counter = 0;

  /// Creates and returns the paylink record. The public checkout URL is derived
  /// when sending (e.g. `…/pl/{id}`) — it does not exist before this call.
  PayLink create({
    required String customerId,
    required String customerName,
    required String customerPhone,
    String? payerEmail,
    required double amountHtg,
    required PayLinkChannel channel,
    required String sentTo,
    String createdBy = 'Staff',
    String? note,
    DateTime? expiresAt,
    PayLinkSource source = PayLinkSource.standalone,
    String? linkedOrderId,
  }) {
    _counter++;
    final now = DateTime.now();
    final link = PayLink(
      id: 'pl_${now.millisecondsSinceEpoch}_$_counter',
      customerId: customerId,
      customerName: customerName,
      customerPhone: customerPhone,
      payerEmail: payerEmail,
      amountHtg: amountHtg,
      status: PayLinkStatus.active,
      channel: channel,
      source: source,
      sentTo: sentTo,
      createdAt: now,
      reference: 'PL-${now.year}-${_counter.toString().padLeft(4, '0')}',
      createdBy: createdBy,
      note: note,
      expiresAt: expiresAt,
      linkedOrderId: linkedOrderId,
    );
    state = PayLinkState(links: [...state.links, link]);
    return link;
  }

  /// Marks a paylink as paid and automatically issues store credit to the client.
  void markPaid(
    String id, {
    String? transactionId,
    String? last4,
    String? paymentMethod,
  }) {
    final link = state.links.firstWhere((l) => l.id == id);
    _update(
      id,
      (l) => l.copyWith(
        status: PayLinkStatus.paidUnused,
        paidAt: DateTime.now(),
        paymentTransactionId: transactionId,
        paymentLast4: last4,
        paymentMethod: paymentMethod,
      ),
    );
    // Auto-issue the full amount as store credit on the customer profile.
    _ref.read(_customerProvider.notifier).issueStoreCredit(
      customerId: link.customerId,
      amountHtg: link.amountHtg,
      description: 'Paylink ${link.reference} — payment received',
      recordedBy: 'System',
    );
  }

  void cancel(String id, {String canceledBy = 'Staff'}) {
    _update(
      id,
      (l) => l.copyWith(
        status: PayLinkStatus.inactive,
        canceledAt: DateTime.now(),
        canceledBy: canceledBy,
      ),
    );
  }

  /// Updates payer contact info and channel without changing status.
  void updateContact(
    String id, {
    required String sentTo,
    required PayLinkChannel channel,
    String? payerEmail,
  }) {
    _update(
      id,
      (l) => l.copyWith(
        sentTo: sentTo,
        channel: channel,
        payerEmail: payerEmail ?? l.payerEmail,
      ),
    );
  }

  void _update(String id, PayLink Function(PayLink) fn) {
    state = PayLinkState(
      links: [for (final l in state.links) l.id == id ? fn(l) : l],
    );
  }
}

// ─── Providers ────────────────────────────────────────────────────────────────

final retailPayLinkProvider =
    StateNotifierProvider<PayLinkNotifier, PayLinkState>((ref) {
  return PayLinkNotifier(_buildSeedState(), ref, customerProvider);
});

final restaurantPayLinkProvider =
    StateNotifierProvider<PayLinkNotifier, PayLinkState>((ref) {
  return PayLinkNotifier(_buildSeedState(), ref, restaurantCustomersProvider);
});

final hotelPayLinkProvider =
    StateNotifierProvider<PayLinkNotifier, PayLinkState>((ref) {
  return PayLinkNotifier(_buildSeedState(), ref, hotelCustomersProvider);
});

// ─── Seed data ────────────────────────────────────────────────────────────────

PayLinkState _buildSeedState() {
  final now = DateTime.now();

  // 20 active paylinks
  final active = <PayLink>[
    _active('pl_a1',  'c1',  'Jean-Pierre Étienne',     '+509 3456-1234', 5000,  PayLinkChannel.whatsApp, '+509 3456-1234', 'PL-2026-0001', now, 3),
    _active('pl_a2',  'c2',  'Marie-Josée Beaumont',    '+509 3789-5678', 8500,  PayLinkChannel.email,    'marie.beaumont@email.com', 'PL-2026-0002', now, 5),
    _active('pl_a3',  'c3',  'Boutique Soleil',         '+509 4111-2222', 12000, PayLinkChannel.whatsApp, '+509 4111-2222', 'PL-2026-0003', now, 7),
    _active('pl_a4',  'c4',  'Rosnel Dupont',           '+509 3222-9900', 3000,  PayLinkChannel.sms,      '+509 3222-9900', 'PL-2026-0004', now, 10),
    _active('pl_a5',  'c5',  'Hôtel Mont Joli',         '+509 3600-1111', 25000, PayLinkChannel.email,    'hotel@montjoli.ht', 'PL-2026-0005', now, 1),
    _active('pl_a6',  'c6',  'Sophie Laurent',          '+509 3711-3344', 4500,  PayLinkChannel.whatsApp, '+509 3711-3344', 'PL-2026-0006', now, 12),
    _active('pl_a7',  'c7',  'Restaurant Le Gourmet',   '+509 3800-5555', 15000, PayLinkChannel.whatsApp, '+509 3800-5555', 'PL-2026-0007', now, 2),
    _active('pl_a8',  'c8',  'Marc Antoine',            '+509 3912-6677', 2000,  PayLinkChannel.sms,      '+509 3912-6677', 'PL-2026-0008', now, 20),
    _active('pl_a9',  'c9',  'École Saint-Louis',       '+509 4023-7788', 30000, PayLinkChannel.email,    'admin@ecole-sl.ht', 'PL-2026-0009', now, 4),
    _active('pl_a10', 'c10', 'Claudette Jean',          '+509 4134-8899', 1500,  PayLinkChannel.whatsApp, '+509 4134-8899', 'PL-2026-0010', now, 25),
    _active('pl_a11', 'c11', 'Boulangerie Douceur',     '+509 4245-9900', 7000,  PayLinkChannel.whatsApp, '+509 4245-9900', 'PL-2026-0011', now, 18),
    _active('pl_a12', 'c12', 'Pierre Emmanuel',         '+509 4356-1011', 3500,  PayLinkChannel.sms,      '+509 4356-1011', 'PL-2026-0012', now, 30),
    _active('pl_a13', 'c13', 'Clinique Bon Samaritain', '+509 4467-2122', 50000, PayLinkChannel.email,    'finance@clinique-bs.ht', 'PL-2026-0013', now, 6),
    _active('pl_a14', 'c14', 'Marie-Claire Dupuis',     '+509 4578-3233', 2500,  PayLinkChannel.whatsApp, '+509 4578-3233', 'PL-2026-0014', now, 8),
    _active('pl_a15', 'c15', 'Super Marché Central',    '+509 4689-4344', 20000, PayLinkChannel.whatsApp, '+509 4689-4344', 'PL-2026-0015', now, 9),
    _active('pl_a16', 'c1',  'Jean-Pierre Étienne',     '+509 3456-1234', 6000,  PayLinkChannel.whatsApp, '+509 3456-1234', 'PL-2026-0016', now, 15),
    _active('pl_a17', 'c2',  'Marie-Josée Beaumont',    '+509 3789-5678', 9000,  PayLinkChannel.email,    'marie.beaumont@email.com', 'PL-2026-0017', now, 16),
    _active('pl_a18', 'c5',  'Hôtel Mont Joli',         '+509 3600-1111', 18000, PayLinkChannel.email,    'hotel@montjoli.ht', 'PL-2026-0018', now, 17),
    _active('pl_a19', 'c7',  'Restaurant Le Gourmet',   '+509 3800-5555', 11000, PayLinkChannel.whatsApp, '+509 3800-5555', 'PL-2026-0019', now, 22),
    _active('pl_a20', 'c9',  'École Saint-Louis',       '+509 4023-7788', 14000, PayLinkChannel.email,    'admin@ecole-sl.ht', 'PL-2026-0020', now, 28),
  ];

  // 3 paid paylinks (amount already issued as store credit to the customer)
  final paid = <PayLink>[
    PayLink(
      id: 'pl_p1', customerId: 'c2', customerName: 'Marie-Josée Beaumont',
      customerPhone: '+509 3789-5678', payerEmail: 'marie.beaumont@email.com',
      amountHtg: 8500, status: PayLinkStatus.paidUnused,
      channel: PayLinkChannel.email, sentTo: 'marie.beaumont@email.com',
      createdAt: now.subtract(const Duration(days: 3)),
      paidAt: now.subtract(const Duration(days: 2)),
      reference: 'PL-2026-0021', createdBy: 'Cashier',
      paymentTransactionId: 'TXN-MC-2026-88421',
      paymentLast4: '4829', paymentMethod: 'MonCash',
    ),
    PayLink(
      id: 'pl_p2', customerId: 'c9', customerName: 'École Saint-Louis',
      customerPhone: '+509 4023-7788', payerEmail: 'admin@ecole-sl.ht',
      amountHtg: 20000, status: PayLinkStatus.paidUnused,
      channel: PayLinkChannel.email, sentTo: 'admin@ecole-sl.ht',
      createdAt: now.subtract(const Duration(days: 5)),
      paidAt: now.subtract(const Duration(days: 4)),
      reference: 'PL-2026-0022', createdBy: 'Manager',
      paymentTransactionId: 'TXN-MC-2026-77310',
      paymentLast4: '1122', paymentMethod: 'MonCash',
      note: 'School semester prepaid',
    ),
    PayLink(
      id: 'pl_p3', customerId: 'c5', customerName: 'Hôtel Mont Joli',
      customerPhone: '+509 3600-1111', payerEmail: 'hotel@montjoli.ht',
      amountHtg: 35000, status: PayLinkStatus.paidUnused,
      channel: PayLinkChannel.email, sentTo: 'hotel@montjoli.ht',
      createdAt: now.subtract(const Duration(days: 1)),
      paidAt: now.subtract(const Duration(hours: 6)),
      reference: 'PL-2026-0023', createdBy: 'Manager',
      paymentTransactionId: 'TXN-CARD-2026-55901',
      paymentLast4: '7743', paymentMethod: 'Card',
    ),
  ];

  // 2 inactive
  final inactive = <PayLink>[
    PayLink(
      id: 'pl_i1', customerId: 'c3', customerName: 'Boutique Soleil',
      customerPhone: '+509 4111-2222', amountHtg: 3000,
      status: PayLinkStatus.inactive, channel: PayLinkChannel.sms,
      sentTo: '+509 4111-2222',
      createdAt: now.subtract(const Duration(days: 12)),
      canceledAt: now.subtract(const Duration(days: 10)),
      reference: 'PL-2026-0024', createdBy: 'Staff',
      note: 'Client canceled order', canceledBy: 'Manager',
    ),
    PayLink(
      id: 'pl_i2', customerId: 'c4', customerName: 'Rosnel Dupont',
      customerPhone: '+509 3222-9900', amountHtg: 5000,
      status: PayLinkStatus.inactive, channel: PayLinkChannel.whatsApp,
      sentTo: '+509 3222-9900',
      createdAt: now.subtract(const Duration(days: 30)),
      canceledAt: now.subtract(const Duration(days: 28)),
      expiresAt: now.subtract(const Duration(days: 20)),
      reference: 'PL-2026-0025', createdBy: 'Cashier',
      note: 'Link expired without payment', canceledBy: 'System',
    ),
  ];

  return PayLinkState(links: [...active, ...paid, ...inactive]);
}

PayLink _active(
  String id,
  String customerId,
  String customerName,
  String phone,
  double amount,
  PayLinkChannel channel,
  String sentTo,
  String reference,
  DateTime now,
  int hoursAgo,
) {
  return PayLink(
    id: id,
    customerId: customerId,
    customerName: customerName,
    customerPhone: phone,
    payerEmail: channel == PayLinkChannel.email ? sentTo : null,
    amountHtg: amount,
    status: PayLinkStatus.active,
    channel: channel,
    source: PayLinkSource.standalone,
    sentTo: sentTo,
    createdAt: now.subtract(Duration(hours: hoursAgo)),
    reference: reference,
    createdBy: 'Staff',
  );
}

const Object _sentinel = Object();
