import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/device_session_provider.dart';
import 'pending_operation.dart';

// ─── Enums ────────────────────────────────────────────────────────────────────

enum CustomerTransactionType { charge, payment, adjustment }

// ─── Supporting Models ────────────────────────────────────────────────────────

class CustomerNote {
  final String id;
  final String customerId;
  final String text;
  final String createdBy;
  final DateTime createdAt;

  const CustomerNote({
    required this.id,
    required this.customerId,
    required this.text,
    required this.createdBy,
    required this.createdAt,
  });
}

class CustomerPaymentSchedule {
  final String id;
  final String customerId;
  final DateTime scheduledDate;
  final double amountHtg;

  const CustomerPaymentSchedule({
    required this.id,
    required this.customerId,
    required this.scheduledDate,
    required this.amountHtg,
  });
}

// ─── Models ───────────────────────────────────────────────────────────────────

class Customer {
  final String id;
  final String name;
  final String phone;
  final String? secondaryPhone;
  final String? address;
  final String? notes;
  final double? creditLimitHtg;
  final double? creditLimitUsd;
  final bool isCreditBlocked;
  final String? blockedReason;
  final String? blockedBy;
  final DateTime? blockedAt;
  final DateTime createdAt;
  final bool isActive;
  /// Optional structured identity for store-credit verification (also see [name]).
  final String? firstName;
  final String? lastName;
  final DateTime? dateOfBirth;
  /// Government ID when available; if empty, [dateOfBirth] should be set for credit identity.
  final String? governmentId;

  Customer({
    required this.id,
    required this.name,
    required this.phone,
    this.secondaryPhone,
    this.address,
    this.notes,
    this.creditLimitHtg,
    this.creditLimitUsd,
    this.isCreditBlocked = false,
    this.blockedReason,
    this.blockedBy,
    this.blockedAt,
    required this.createdAt,
    this.isActive = true,
    this.firstName,
    this.lastName,
    this.dateOfBirth,
    this.governmentId,
  });

  /// Profile complete enough to hold and redeem **store credit** (prepaid balance).
  bool get hasStoreCreditIdentity {
    final fn = firstName?.trim() ?? '';
    final ln = lastName?.trim() ?? '';
    if (fn.isEmpty || ln.isEmpty) return false;
    final id = governmentId?.trim() ?? '';
    if (id.isNotEmpty) return true;
    return dateOfBirth != null;
  }

  String get displayFirstLastName {
    final fn = firstName?.trim() ?? '';
    final ln = lastName?.trim() ?? '';
    if (fn.isNotEmpty || ln.isNotEmpty) return '$fn $ln'.trim();
    return name;
  }

  double get outstandingBalanceHtg => _balance;
  double _balance = 0;

  Customer withBalance(double balance) {
    final c = Customer(
      id: id,
      name: name,
      phone: phone,
      secondaryPhone: secondaryPhone,
      address: address,
      notes: notes,
      creditLimitHtg: creditLimitHtg,
      creditLimitUsd: creditLimitUsd,
      isCreditBlocked: isCreditBlocked,
      blockedReason: blockedReason,
      blockedBy: blockedBy,
      blockedAt: blockedAt,
      createdAt: createdAt,
      isActive: isActive,
      firstName: firstName,
      lastName: lastName,
      dateOfBirth: dateOfBirth,
      governmentId: governmentId,
    );
    c._balance = balance;
    return c;
  }

  Customer copyWith({
    String? id,
    String? name,
    String? phone,
    Object? secondaryPhone = _sentinel,
    Object? address = _sentinel,
    Object? notes = _sentinel,
    Object? creditLimitHtg = _sentinel,
    Object? creditLimitUsd = _sentinel,
    bool? isCreditBlocked,
    Object? blockedReason = _sentinel,
    Object? blockedBy = _sentinel,
    Object? blockedAt = _sentinel,
    DateTime? createdAt,
    bool? isActive,
    Object? firstName = _sentinel,
    Object? lastName = _sentinel,
    Object? dateOfBirth = _sentinel,
    Object? governmentId = _sentinel,
  }) {
    return Customer(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      secondaryPhone:
          secondaryPhone == _sentinel ? this.secondaryPhone : secondaryPhone as String?,
      address: address == _sentinel ? this.address : address as String?,
      notes: notes == _sentinel ? this.notes : notes as String?,
      creditLimitHtg: creditLimitHtg == _sentinel
          ? this.creditLimitHtg
          : creditLimitHtg as double?,
      creditLimitUsd: creditLimitUsd == _sentinel
          ? this.creditLimitUsd
          : creditLimitUsd as double?,
      isCreditBlocked: isCreditBlocked ?? this.isCreditBlocked,
      blockedReason:
          blockedReason == _sentinel ? this.blockedReason : blockedReason as String?,
      blockedBy: blockedBy == _sentinel ? this.blockedBy : blockedBy as String?,
      blockedAt: blockedAt == _sentinel ? this.blockedAt : blockedAt as DateTime?,
      createdAt: createdAt ?? this.createdAt,
      isActive: isActive ?? this.isActive,
      firstName: firstName == _sentinel ? this.firstName : firstName as String?,
      lastName: lastName == _sentinel ? this.lastName : lastName as String?,
      dateOfBirth:
          dateOfBirth == _sentinel ? this.dateOfBirth : dateOfBirth as DateTime?,
      governmentId: governmentId == _sentinel
          ? this.governmentId
          : governmentId as String?,
    );
  }

  bool get isOverLimit {
    if (creditLimitHtg == null) return false;
    return _balance >= creditLimitHtg!;
  }
}

class CustomerTransaction {
  final String id;
  final String customerId;
  final CustomerTransactionType type;
  final double amountHtg;
  final double amountUsd;
  final double paidAmountHtg;
  final double balanceAfterHtg;
  final String? linkedOrderId;
  final String? linkedTableName;
  final String? serverName;
  final String cashierName;
  final String description;
  final DateTime timestamp;
  final bool receiptSent;
  /// Payment method label (e.g. "Espèces", "MonCash", "Carte"). Only set for payment type.
  final String? paymentMethodLabel;
  /// Receipt number for account payments (e.g. "PAY-2026-001").
  final String? receiptNumber;

  const CustomerTransaction({
    required this.id,
    required this.customerId,
    required this.type,
    required this.amountHtg,
    this.amountUsd = 0,
    this.paidAmountHtg = 0,
    required this.balanceAfterHtg,
    this.linkedOrderId,
    this.linkedTableName,
    this.serverName,
    required this.cashierName,
    required this.description,
    required this.timestamp,
    this.receiptSent = false,
    this.paymentMethodLabel,
    this.receiptNumber,
  });

  double get creditedHtg => amountHtg - paidAmountHtg;
}

/// Prepaid / promotional balance the customer can spend (separate from A/R charges).
enum StoreCreditEntryKind { issued, redeemed }

class StoreCreditLedgerEntry {
  final String id;
  final String customerId;
  final StoreCreditEntryKind kind;
  final double amountHtg;
  final String description;
  final DateTime createdAt;
  final String? orderId;
  final String recordedBy;

  const StoreCreditLedgerEntry({
    required this.id,
    required this.customerId,
    required this.kind,
    required this.amountHtg,
    required this.description,
    required this.createdAt,
    this.orderId,
    this.recordedBy = 'Personnel',
  });
}

// ─── State ────────────────────────────────────────────────────────────────────

class CustomerState {
  final List<Customer> customers;
  final List<CustomerTransaction> transactions;
  final List<StoreCreditLedgerEntry> storeCreditLedger;
  final Map<String, List<CustomerNote>> notesByCustomer;
  final Map<String, List<CustomerPaymentSchedule>> schedulesByCustomer;

  const CustomerState({
    this.customers = const [],
    this.transactions = const [],
    this.storeCreditLedger = const [],
    this.notesByCustomer = const {},
    this.schedulesByCustomer = const {},
  });

  List<CustomerTransaction> transactionsFor(String customerId, {int? limit}) {
    final list = transactions
        .where((t) => t.customerId == customerId)
        .toList()
        .reversed
        .toList();
    if (limit != null) return list.take(limit).toList();
    return list;
  }

  int transactionCountFor(String customerId) =>
      transactions.where((t) => t.customerId == customerId).length;

  double balanceFor(String customerId) {
    double balance = 0;
    for (final t in transactions.where((t) => t.customerId == customerId)) {
      if (t.type == CustomerTransactionType.charge) {
        balance += t.creditedHtg;
      } else if (t.type == CustomerTransactionType.payment) {
        balance -= t.amountHtg;
      } else if (t.type == CustomerTransactionType.adjustment) {
        balance += t.amountHtg;
      }
    }
    return balance < 0 ? 0 : balance;
  }

  List<CustomerNote> notesFor(String customerId) =>
      notesByCustomer[customerId] ?? [];

  List<CustomerPaymentSchedule> schedulesFor(String customerId) =>
      schedulesByCustomer[customerId] ?? [];

  List<Customer> get customersWithBalance => customers
      .map((c) => c.withBalance(balanceFor(c.id)))
      .where((c) => c.outstandingBalanceHtg > 0)
      .toList()
    ..sort((a, b) =>
        b.outstandingBalanceHtg.compareTo(a.outstandingBalanceHtg));

  List<Customer> get blockedCustomers =>
      customers.where((c) => c.isCreditBlocked).toList();

  double get totalOutstandingHtg =>
      customers.fold(0, (s, c) => s + balanceFor(c.id));

  List<StoreCreditLedgerEntry> storeCreditHistoryFor(String customerId) {
    final list = storeCreditLedger
        .where((e) => e.customerId == customerId)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  double storeCreditBalanceFor(String customerId) {
    double bal = 0;
    for (final e in storeCreditLedger.where((e) => e.customerId == customerId)) {
      if (e.kind == StoreCreditEntryKind.issued) {
        bal += e.amountHtg;
      } else {
        bal -= e.amountHtg;
      }
    }
    return bal < 0 ? 0 : bal;
  }
}

// ─── Notifier ─────────────────────────────────────────────────────────────────

class CustomerNotifier extends StateNotifier<CustomerState> {
  CustomerNotifier(super.initial, {this.journal});

  final PendingJournal? journal;

  String _nameOf(String customerId) =>
      state.customers.where((c) => c.id == customerId).firstOrNull?.name ?? 'Client';

  void _logAccount(String customerId, String action, double? amountHtg) {
    journal?.call(
      PendingOperationKind.customerAccount,
      '$action · ${_nameOf(customerId)}',
      amountHtg: amountHtg,
    );
  }

  int _txCounter = 0;
  int _storeCreditCounter = 0;

  /// Replaces state with loaded data (e.g. for lazy-loaded module).
  void loadState(CustomerState newState) {
    state = newState;
  }

  int _noteCounter = 0;
  int _scheduleCounter = 0;

  void addCustomer(Customer c) {
    state = CustomerState(
      customers: [...state.customers, c],
      transactions: state.transactions,
      storeCreditLedger: state.storeCreditLedger,
      notesByCustomer: state.notesByCustomer,
      schedulesByCustomer: state.schedulesByCustomer,
    );
    journal?.call(PendingOperationKind.customer, 'Client ajouté · ${c.name}');
  }

  void updateCustomer(Customer c) {
    state = CustomerState(
      customers: [
        for (final r in state.customers) r.id == c.id ? c : r
      ],
      transactions: state.transactions,
      storeCreditLedger: state.storeCreditLedger,
      notesByCustomer: state.notesByCustomer,
      schedulesByCustomer: state.schedulesByCustomer,
    );
    journal?.call(PendingOperationKind.customer, 'Client modifié · ${c.name}');
  }

  /// Adds spendable store credit (e.g. unused prepaid balance returned to guest).
  void issueStoreCredit({
    required String customerId,
    required double amountHtg,
    required String description,
    String? orderId,
    String recordedBy = 'Personnel',
  }) {
    if (amountHtg <= 0) return;
    _storeCreditCounter++;
    final entry = StoreCreditLedgerEntry(
      id: 'sc_$_storeCreditCounter',
      customerId: customerId,
      kind: StoreCreditEntryKind.issued,
      amountHtg: amountHtg,
      description: description,
      createdAt: DateTime.now(),
      orderId: orderId,
      recordedBy: recordedBy,
    );
    state = CustomerState(
      customers: state.customers,
      transactions: state.transactions,
      storeCreditLedger: [...state.storeCreditLedger, entry],
      notesByCustomer: state.notesByCustomer,
      schedulesByCustomer: state.schedulesByCustomer,
    );
    _logAccount(customerId, 'Avoir émis', amountHtg);
  }

  /// Deducts from the customer's store-credit balance (e.g. applied to a bill).
  void redeemStoreCredit({
    required String customerId,
    required double amountHtg,
    required String description,
    String? orderId,
    String recordedBy = 'Personnel',
  }) {
    if (amountHtg <= 0) return;
    final available = state.storeCreditBalanceFor(customerId);
    final use = amountHtg > available ? available : amountHtg;
    if (use <= 0) return;
    _storeCreditCounter++;
    final entry = StoreCreditLedgerEntry(
      id: 'sc_$_storeCreditCounter',
      customerId: customerId,
      kind: StoreCreditEntryKind.redeemed,
      amountHtg: use,
      description: description,
      createdAt: DateTime.now(),
      orderId: orderId,
      recordedBy: recordedBy,
    );
    state = CustomerState(
      customers: state.customers,
      transactions: state.transactions,
      storeCreditLedger: [...state.storeCreditLedger, entry],
      notesByCustomer: state.notesByCustomer,
      schedulesByCustomer: state.schedulesByCustomer,
    );
    _logAccount(customerId, 'Avoir utilisé', use);
  }

  void blockCustomer(String id,
      {required String reason, required String blockedBy}) {
    final c = state.customers.firstWhere((c) => c.id == id);
    updateCustomer(c.copyWith(
      isCreditBlocked: true,
      blockedReason: reason,
      blockedBy: blockedBy,
      blockedAt: DateTime.now(),
    ));
  }

  void unblockCustomer(String id) {
    final c = state.customers.firstWhere((c) => c.id == id);
    updateCustomer(c.copyWith(
      isCreditBlocked: false,
      blockedReason: null,
      blockedBy: null,
      blockedAt: null,
    ));
  }

  void postCharge({
    required String customerId,
    required double amountHtg,
    double amountUsd = 0,
    double paidAmountHtg = 0,
    String? linkedOrderId,
    String? linkedTableName,
    String? serverName,
    required String cashierName,
    required String description,
  }) {
    _txCounter++;
    final currentBalance = state.balanceFor(customerId);
    final creditedHtg = amountHtg - paidAmountHtg;
    final newBalance = currentBalance + creditedHtg;

    final tx = CustomerTransaction(
      id: 'tx_$_txCounter',
      customerId: customerId,
      type: CustomerTransactionType.charge,
      amountHtg: amountHtg,
      amountUsd: amountUsd,
      paidAmountHtg: paidAmountHtg,
      balanceAfterHtg: newBalance,
      linkedOrderId: linkedOrderId,
      linkedTableName: linkedTableName,
      serverName: serverName,
      cashierName: cashierName,
      description: description,
      timestamp: DateTime.now(),
    );
    state = CustomerState(
      customers: state.customers,
      transactions: [...state.transactions, tx],
      storeCreditLedger: state.storeCreditLedger,
      notesByCustomer: state.notesByCustomer,
      schedulesByCustomer: state.schedulesByCustomer,
    );
    _logAccount(customerId, 'Vente à crédit', creditedHtg);
  }

  void postPayment({
    required String customerId,
    required double amountHtg,
    required String cashierName,
    String description = 'Paiement reçu',
    String? paymentMethodLabel,
    String? receiptNumber,
    String? linkedOrderId,
  }) {
    _txCounter++;
    final currentBalance = state.balanceFor(customerId);
    final newBalance = (currentBalance - amountHtg).clamp(0.0, double.infinity);
    final tx = CustomerTransaction(
      id: 'tx_$_txCounter',
      customerId: customerId,
      type: CustomerTransactionType.payment,
      amountHtg: amountHtg,
      balanceAfterHtg: newBalance,
      cashierName: cashierName,
      description: description,
      timestamp: DateTime.now(),
      paymentMethodLabel: paymentMethodLabel,
      receiptNumber: receiptNumber,
      linkedOrderId: linkedOrderId,
    );
    state = CustomerState(
      customers: state.customers,
      transactions: [...state.transactions, tx],
      storeCreditLedger: state.storeCreditLedger,
      notesByCustomer: state.notesByCustomer,
      schedulesByCustomer: state.schedulesByCustomer,
    );
    _logAccount(customerId, 'Paiement reçu', amountHtg);
  }

  void postAdjustment({
    required String customerId,
    required double amountHtg,
    required String cashierName,
    required String description,
  }) {
    _txCounter++;
    final currentBalance = state.balanceFor(customerId);
    final newBalance = (currentBalance + amountHtg).clamp(0.0, double.infinity);
    final tx = CustomerTransaction(
      id: 'tx_$_txCounter',
      customerId: customerId,
      type: CustomerTransactionType.adjustment,
      amountHtg: amountHtg,
      balanceAfterHtg: newBalance,
      cashierName: cashierName,
      description: description,
      timestamp: DateTime.now(),
    );
    state = CustomerState(
      customers: state.customers,
      transactions: [...state.transactions, tx],
      storeCreditLedger: state.storeCreditLedger,
      notesByCustomer: state.notesByCustomer,
      schedulesByCustomer: state.schedulesByCustomer,
    );
    _logAccount(customerId, 'Ajustement de solde', amountHtg);
  }

  void addNote({
    required String customerId,
    required String text,
    required String createdBy,
  }) {
    _noteCounter++;
    final note = CustomerNote(
      id: 'note_$_noteCounter',
      customerId: customerId,
      text: text,
      createdBy: createdBy,
      createdAt: DateTime.now(),
    );
    final existing = state.notesFor(customerId);
    final updated = {...state.notesByCustomer};
    updated[customerId] = [...existing, note];
    state = CustomerState(
      customers: state.customers,
      transactions: state.transactions,
      storeCreditLedger: state.storeCreditLedger,
      notesByCustomer: updated,
      schedulesByCustomer: state.schedulesByCustomer,
    );
    _logAccount(customerId, 'Note ajoutée', null);
  }

  void addSchedule({
    required String customerId,
    required DateTime scheduledDate,
    required double amountHtg,
  }) {
    _scheduleCounter++;
    final schedule = CustomerPaymentSchedule(
      id: 'sched_$_scheduleCounter',
      customerId: customerId,
      scheduledDate: scheduledDate,
      amountHtg: amountHtg,
    );
    final existing = state.schedulesFor(customerId);
    final updated = {...state.schedulesByCustomer};
    updated[customerId] = [...existing, schedule];
    state = CustomerState(
      customers: state.customers,
      transactions: state.transactions,
      storeCreditLedger: state.storeCreditLedger,
      notesByCustomer: state.notesByCustomer,
      schedulesByCustomer: updated,
    );
    _logAccount(customerId, 'Échéance ajoutée', amountHtg);
  }
}

// ─── Providers ────────────────────────────────────────────────────────────────

final customerProvider =
    StateNotifierProvider<CustomerNotifier, CustomerState>((ref) {
  return CustomerNotifier(_buildSeedState(), journal: pendingJournal(ref));
});

/// Hotel module: loaded by default when opening Customers page.
final hotelCustomersProvider =
    StateNotifierProvider<CustomerNotifier, CustomerState>((ref) {
  return CustomerNotifier(_buildSeedState());
});

/// Restaurant module: same seed data as other modules.
final restaurantCustomersProvider =
    StateNotifierProvider<CustomerNotifier, CustomerState>((ref) {
  return CustomerNotifier(_buildSeedState());
});

/// Kept for backward compatibility — no longer triggers a lazy load.
final restaurantCustomersLoadProvider = FutureProvider<void>((_) async {});

// ─── Seed Data ────────────────────────────────────────────────────────────────

CustomerState _buildSeedState() {
  final now = DateTime.now();

  final customers = [
    Customer(
      id: 'c1',
      name: 'Jean-Pierre Étienne',
      firstName: 'Jean-Pierre',
      lastName: 'Étienne',
      governmentId: 'HA-889912',
      phone: '+509 3456-1234',
      address: 'Pétion-Ville, Port-au-Prince',
      createdAt: now.subtract(const Duration(days: 120)),
    ),
    Customer(
      id: 'c2',
      name: 'Marie-Josée Beaumont',
      firstName: 'Marie-Josée',
      lastName: 'Beaumont',
      dateOfBirth: DateTime(1988, 3, 14),
      phone: '+509 3789-5678',
      notes: 'Regular — usually pays within 2 weeks',
      createdAt: now.subtract(const Duration(days: 60)),
    ),
    Customer(
      id: 'c3',
      name: 'Boutique Soleil',
      phone: '+509 4111-2222',
      address: 'Delmas 33',
      creditLimitHtg: 50000,
      notes: 'Compte professionnel',
      createdAt: now.subtract(const Duration(days: 200)),
    ),
    Customer(
      id: 'c4',
      name: 'Rosnel Dupont',
      phone: '+509 3222-9900',
      isCreditBlocked: true,
      blockedReason: 'Solde impayé depuis plus de 45 jours',
      blockedBy: 'Gérant',
      blockedAt: now.subtract(const Duration(days: 5)),
      createdAt: now.subtract(const Duration(days: 180)),
    ),
    Customer(
      id: 'c5',
      name: 'Hôtel Mont Joli',
      phone: '+509 3600-1111',
      creditLimitHtg: 200000,
      notes: 'Corporate — monthly invoice',
      createdAt: now.subtract(const Duration(days: 365)),
    ),
    Customer(
      id: 'c6',
      name: 'Sophie Laurent',
      phone: '+509 3711-3344',
      address: 'Kenscoff',
      createdAt: now.subtract(const Duration(days: 90)),
    ),
    Customer(
      id: 'c7',
      name: 'Restaurant Le Gourmet',
      phone: '+509 3800-5555',
      address: 'Pétion-Ville',
      creditLimitHtg: 75000,
      createdAt: now.subtract(const Duration(days: 150)),
    ),
    Customer(
      id: 'c8',
      name: 'Marc Antoine',
      phone: '+509 3912-6677',
      createdAt: now.subtract(const Duration(days: 45)),
    ),
    Customer(
      id: 'c9',
      name: 'École Saint-Louis',
      phone: '+509 4023-7788',
      address: 'Delmas 75',
      creditLimitHtg: 100000,
      notes: 'School cafeteria',
      createdAt: now.subtract(const Duration(days: 220)),
    ),
    Customer(
      id: 'c10',
      name: 'Claudette Jean',
      phone: '+509 4134-8899',
      createdAt: now.subtract(const Duration(days: 30)),
    ),
    Customer(
      id: 'c11',
      name: 'Boulangerie Douceur',
      phone: '+509 4245-9900',
      address: 'Carrefour',
      creditLimitHtg: 25000,
      createdAt: now.subtract(const Duration(days: 100)),
    ),
    Customer(
      id: 'c12',
      name: 'Pierre Emmanuel',
      phone: '+509 4356-1011',
      createdAt: now.subtract(const Duration(days: 15)),
    ),
    Customer(
      id: 'c13',
      name: 'Clinique Bon Samaritain',
      phone: '+509 4467-2122',
      address: 'Tabarre',
      creditLimitHtg: 150000,
      notes: 'Medical facility',
      createdAt: now.subtract(const Duration(days: 280)),
    ),
    Customer(
      id: 'c14',
      name: 'Marie-Claire Dupuis',
      phone: '+509 4578-3233',
      createdAt: now.subtract(const Duration(days: 8)),
    ),
    Customer(
      id: 'c15',
      name: 'Super Marché Central',
      phone: '+509 4689-4344',
      address: 'Croix-des-Bouquets',
      creditLimitHtg: 80000,
      createdAt: now.subtract(const Duration(days: 170)),
    ),
  ];

  final txs = <CustomerTransaction>[
    // c1 — owes 2,400 HTG
    CustomerTransaction(
      id: 'tx_s1',
      customerId: 'c1',
      type: CustomerTransactionType.charge,
      amountHtg: 3200,
      paidAmountHtg: 800,
      balanceAfterHtg: 2400,
      linkedTableName: 'Table 3',
      serverName: 'Marie-Carmel',
      cashierName: 'Caissier',
      description: 'Dîner — Table 3',
      timestamp: now.subtract(const Duration(days: 3)),
    ),
    // c2 — charge then payments, balance 4,693 HTG
    CustomerTransaction(
      id: 'tx_s2',
      customerId: 'c2',
      type: CustomerTransactionType.charge,
      amountHtg: 5750,
      paidAmountHtg: 0,
      balanceAfterHtg: 5750,
      linkedTableName: 'Terrasse A',
      serverName: 'Joseph',
      cashierName: 'Caissier',
      description: 'Déjeuner en famille — Terrasse A',
      timestamp: now.subtract(const Duration(days: 1)),
    ),
    CustomerTransaction(
      id: 'tx_s2a',
      customerId: 'c2',
      type: CustomerTransactionType.payment,
      amountHtg: 900,
      balanceAfterHtg: 4850,
      cashierName: 'Caissier',
      description: 'Paiement reçu',
      timestamp: now.subtract(const Duration(days: 1)),
    ),
    CustomerTransaction(
      id: 'tx_s2b',
      customerId: 'c2',
      type: CustomerTransactionType.payment,
      amountHtg: 67,
      balanceAfterHtg: 4783,
      cashierName: 'Caissier',
      description: 'Paiement reçu',
      timestamp: now.subtract(const Duration(days: 1)),
    ),
    CustomerTransaction(
      id: 'tx_s2c',
      customerId: 'c2',
      type: CustomerTransactionType.payment,
      amountHtg: 90,
      balanceAfterHtg: 4693,
      cashierName: 'Caissier',
      description: 'Paiement reçu',
      timestamp: now.subtract(const Duration(days: 1)),
    ),
    // c3 — owes 12,000 HTG
    CustomerTransaction(
      id: 'tx_s3',
      customerId: 'c3',
      type: CustomerTransactionType.charge,
      amountHtg: 18500,
      paidAmountHtg: 6500,
      balanceAfterHtg: 12000,
      linkedTableName: 'Salon VIP',
      serverName: 'Claudine',
      cashierName: 'Caissier',
      description: 'Événement — salon VIP',
      timestamp: now.subtract(const Duration(days: 7)),
    ),
    // c4 (blocked) — owes 8,900 HTG
    CustomerTransaction(
      id: 'tx_s4',
      customerId: 'c4',
      type: CustomerTransactionType.charge,
      amountHtg: 8900,
      paidAmountHtg: 0,
      balanceAfterHtg: 8900,
      linkedTableName: 'Table 2',
      serverName: 'Pierre',
      cashierName: 'Caissier',
      description: 'Dîner — Table 2',
      timestamp: now.subtract(const Duration(days: 50)),
    ),
    // c5 — owes 24,000 HTG
    CustomerTransaction(
      id: 'tx_s5',
      customerId: 'c5',
      type: CustomerTransactionType.charge,
      amountHtg: 45000,
      paidAmountHtg: 21000,
      balanceAfterHtg: 24000,
      linkedTableName: 'Salon VIP',
      serverName: 'Claudine',
      cashierName: 'Caissier',
      description: 'Dîner de groupe — salon VIP',
      timestamp: now.subtract(const Duration(days: 14)),
    ),
    // c6 — owes 1,500 HTG
    CustomerTransaction(
      id: 'tx_s6',
      customerId: 'c6',
      type: CustomerTransactionType.charge,
      amountHtg: 1500,
      paidAmountHtg: 0,
      balanceAfterHtg: 1500,
      cashierName: 'Caissier',
      description: 'Lunch',
      timestamp: now.subtract(const Duration(days: 2)),
    ),
    // c7 — owes 8,000 HTG
    CustomerTransaction(
      id: 'tx_s7',
      customerId: 'c7',
      type: CustomerTransactionType.charge,
      amountHtg: 8000,
      paidAmountHtg: 0,
      balanceAfterHtg: 8000,
      cashierName: 'Caissier',
      description: 'Commande en gros',
      timestamp: now.subtract(const Duration(days: 5)),
    ),
    // c8 — settled (had balance, paid)
    CustomerTransaction(
      id: 'tx_s8a',
      customerId: 'c8',
      type: CustomerTransactionType.charge,
      amountHtg: 500,
      paidAmountHtg: 0,
      balanceAfterHtg: 500,
      cashierName: 'Caissier',
      description: 'Coffee',
      timestamp: now.subtract(const Duration(days: 10)),
    ),
    CustomerTransaction(
      id: 'tx_s8b',
      customerId: 'c8',
      type: CustomerTransactionType.payment,
      amountHtg: 500,
      balanceAfterHtg: 0,
      cashierName: 'Caissier',
      description: 'Paiement reçu',
      timestamp: now.subtract(const Duration(days: 9)),
    ),
    // c9 — owes 15,000 HTG
    CustomerTransaction(
      id: 'tx_s9',
      customerId: 'c9',
      type: CustomerTransactionType.charge,
      amountHtg: 15000,
      paidAmountHtg: 0,
      balanceAfterHtg: 15000,
      cashierName: 'Caissier',
      description: 'Fournitures scolaires',
      timestamp: now.subtract(const Duration(days: 12)),
    ),
    // c10, c11, c12 — no transactions (settled/zero balance)
    // c13 — owes 3,200 HTG
    CustomerTransaction(
      id: 'tx_s13',
      customerId: 'c13',
      type: CustomerTransactionType.charge,
      amountHtg: 3200,
      paidAmountHtg: 0,
      balanceAfterHtg: 3200,
      cashierName: 'Caissier',
      description: 'Medical supplies',
      timestamp: now.subtract(const Duration(days: 4)),
    ),
    // c14 — settled
    CustomerTransaction(
      id: 'tx_s14a',
      customerId: 'c14',
      type: CustomerTransactionType.charge,
      amountHtg: 200,
      paidAmountHtg: 0,
      balanceAfterHtg: 200,
      cashierName: 'Caissier',
      description: 'Snack',
      timestamp: now.subtract(const Duration(days: 7)),
    ),
    CustomerTransaction(
      id: 'tx_s14b',
      customerId: 'c14',
      type: CustomerTransactionType.payment,
      amountHtg: 200,
      balanceAfterHtg: 0,
      cashierName: 'Caissier',
      description: 'Paiement reçu',
      timestamp: now.subtract(const Duration(days: 6)),
    ),
    // c15 — owes 5,000 HTG
    CustomerTransaction(
      id: 'tx_s15',
      customerId: 'c15',
      type: CustomerTransactionType.charge,
      amountHtg: 5000,
      paidAmountHtg: 0,
      balanceAfterHtg: 5000,
      cashierName: 'Caissier',
      description: 'Groceries',
      timestamp: now.subtract(const Duration(days: 3)),
    ),
  ];

  final storeCredit = <StoreCreditLedgerEntry>[
    StoreCreditLedgerEntry(
      id: 'sc_seed_1',
      customerId: 'c1',
      kind: StoreCreditEntryKind.issued,
      amountHtg: 5000,
      description: 'Prépayé non utilisé — rendu au compte client',
      createdAt: now.subtract(const Duration(days: 4)),
    ),
    StoreCreditLedgerEntry(
      id: 'sc_seed_2',
      customerId: 'c1',
      kind: StoreCreditEntryKind.redeemed,
      amountHtg: 800,
      description: 'Appliqué à la note du restaurant',
      orderId: '101',
      createdAt: now.subtract(const Duration(days: 2)),
    ),
    StoreCreditLedgerEntry(
      id: 'sc_seed_3',
      customerId: 'c2',
      kind: StoreCreditEntryKind.issued,
      amountHtg: 2200,
      description: 'Avoir commercial — approbation du gérant',
      createdAt: now.subtract(const Duration(days: 6)),
    ),
  ];

  return CustomerState(
    customers: customers,
    transactions: txs,
    storeCreditLedger: storeCredit,
  );
}

const Object _sentinel = Object();
