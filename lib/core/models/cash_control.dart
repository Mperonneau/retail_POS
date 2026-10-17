import 'package:flutter_riverpod/flutter_riverpod.dart';

// ─── Enums ────────────────────────────────────────────────────────────────────

enum CashSessionStatus { open, closed }

enum CashMovementType { cashIn, cashOut, adjustment }

/// How a movement is settled (drawer vs electronic). Used by hotel front desk.
enum PaymentTender {
  cashHtg,
  cashUsd,
  moncash,
  card,
  check,
}

extension PaymentTenderX on PaymentTender {
  String get label {
    switch (this) {
      case PaymentTender.cashHtg:
        return 'Espèces (HTG)';
      case PaymentTender.cashUsd:
        return 'Espèces (USD)';
      case PaymentTender.moncash:
        return 'MonCash';
      case PaymentTender.card:
        return 'Carte de crédit / débit';
      case PaymentTender.check:
        return 'Check';
    }
  }
}

// ─── Session model ────────────────────────────────────────────────────────────

class CashSession {
  final String id;
  final String openedBy;
  final DateTime openedAt;
  final DateTime? closedAt;
  final double openingBalanceHtg;
  final double openingBalanceUsd;
  final CashSessionStatus status;
  final String? closingNote;

  const CashSession({
    required this.id,
    required this.openedBy,
    required this.openedAt,
    this.closedAt,
    required this.openingBalanceHtg,
    this.openingBalanceUsd = 0,
    required this.status,
    this.closingNote,
  });

  CashSession copyWith({
    String? id,
    String? openedBy,
    DateTime? openedAt,
    Object? closedAt = _sentinel,
    double? openingBalanceHtg,
    double? openingBalanceUsd,
    CashSessionStatus? status,
    Object? closingNote = _sentinel,
  }) {
    return CashSession(
      id: id ?? this.id,
      openedBy: openedBy ?? this.openedBy,
      openedAt: openedAt ?? this.openedAt,
      closedAt: closedAt == _sentinel ? this.closedAt : closedAt as DateTime?,
      openingBalanceHtg: openingBalanceHtg ?? this.openingBalanceHtg,
      openingBalanceUsd: openingBalanceUsd ?? this.openingBalanceUsd,
      status: status ?? this.status,
      closingNote:
          closingNote == _sentinel ? this.closingNote : closingNote as String?,
    );
  }
}

// ─── Movement model ───────────────────────────────────────────────────────────

class CashMovement {
  final String id;
  final String sessionId;
  final CashMovementType type;
  final double amountHtg;
  final double amountUsd;
  final double tipsHtg;
  final double tipsUsd;
  final String description;
  final String? linkedOrderId;
  final String? linkedTableNumber;
  final String? linkedWaiterName;
  final DateTime timestamp;
  final String recordedBy;

  /// Drawer cash vs MonCash / card / check (hotel front desk).
  final PaymentTender tender;

  const CashMovement({
    required this.id,
    required this.sessionId,
    required this.type,
    required this.amountHtg,
    this.amountUsd = 0,
    this.tipsHtg = 0,
    this.tipsUsd = 0,
    required this.description,
    this.linkedOrderId,
    this.linkedTableNumber,
    this.linkedWaiterName,
    required this.timestamp,
    required this.recordedBy,
    this.tender = PaymentTender.cashHtg,
  });

  double get totalHtg => amountHtg + tipsHtg;
  double get totalUsd => amountUsd + tipsUsd;
  bool get hasTableContext =>
      linkedTableNumber != null || linkedWaiterName != null;
}

extension CashMovementAdjustmentUi on CashMovement {
  /// For [CashMovementType.adjustment]: `true` = add to drawer, `false` = remove.
  bool get adjustmentAddsToDrawer {
    if (type != CashMovementType.adjustment) return true;
    if (amountHtg != 0) return amountHtg > 0;
    if (amountUsd != 0) return amountUsd > 0;
    return true;
  }
}

// ─── Session summary (for history) ───────────────────────────────────────────

class SessionSummary {
  final CashSession session;
  final double totalInHtg;
  final double totalInUsd;
  final double totalOutHtg;
  final double totalOutUsd;
  final double finalBalanceHtg;
  final double finalBalanceUsd;
  final String closedBy;

  const SessionSummary({
    required this.session,
    required this.totalInHtg,
    required this.totalInUsd,
    required this.totalOutHtg,
    required this.totalOutUsd,
    required this.finalBalanceHtg,
    required this.finalBalanceUsd,
    required this.closedBy,
  });

  double get expectedHtg =>
      session.openingBalanceHtg + totalInHtg - totalOutHtg;
  double get expectedUsd =>
      session.openingBalanceUsd + totalInUsd - totalOutUsd;
  double get overShortHtg => finalBalanceHtg - expectedHtg;
  double get overShortUsd => finalBalanceUsd - expectedUsd;
  bool get isBalanced => overShortHtg.abs() < 1.0;
}

// ─── State ────────────────────────────────────────────────────────────────────

class CashControlState {
  final CashSession? activeSession;
  final List<CashMovement> movements;
  final List<SessionSummary> sessionHistory;

  const CashControlState({
    this.activeSession,
    this.movements = const [],
    this.sessionHistory = const [],
  });

  // HTG aggregates for current session
  double get totalIn => movements
      .where((m) =>
          m.sessionId == activeSession?.id &&
          m.type == CashMovementType.cashIn)
      .fold(0, (s, m) => s + m.totalHtg);

  double get totalOut => movements
      .where((m) =>
          m.sessionId == activeSession?.id &&
          m.type == CashMovementType.cashOut)
      .fold(0, (s, m) => s + m.totalHtg);

  double get expectedBalance =>
      (activeSession?.openingBalanceHtg ?? 0) + totalIn - totalOut;

  // USD aggregates for current session
  double get totalInUsd => movements
      .where((m) =>
          m.sessionId == activeSession?.id &&
          m.type == CashMovementType.cashIn)
      .fold(0, (s, m) => s + m.totalUsd);

  double get totalOutUsd => movements
      .where((m) =>
          m.sessionId == activeSession?.id &&
          m.type == CashMovementType.cashOut)
      .fold(0, (s, m) => s + m.totalUsd);

  double get expectedBalanceUsd =>
      (activeSession?.openingBalanceUsd ?? 0) + totalInUsd - totalOutUsd;

  List<CashMovement> get sessionMovements => movements
      .where((m) => m.sessionId == activeSession?.id)
      .toList()
      .reversed
      .toList();

  static bool _isDrawerTender(PaymentTender t) =>
      t == PaymentTender.cashHtg || t == PaymentTender.cashUsd;

  /// Net effect on physical HTG drawer (opening + in − out + adjustments).
  double get drawerExpectedHtg {
    var e = activeSession?.openingBalanceHtg ?? 0.0;
    for (final m in sessionMovements) {
      if (!_isDrawerTender(m.tender)) continue;
      switch (m.type) {
        case CashMovementType.cashIn:
          e += m.totalHtg;
          break;
        case CashMovementType.cashOut:
          e -= m.totalHtg;
          break;
        case CashMovementType.adjustment:
          e += m.amountHtg;
          break;
      }
    }
    return e;
  }

  /// Net effect on USD bills in drawer.
  double get drawerExpectedUsd {
    var e = activeSession?.openingBalanceUsd ?? 0.0;
    for (final m in sessionMovements) {
      if (!_isDrawerTender(m.tender)) continue;
      switch (m.type) {
        case CashMovementType.cashIn:
          e += m.totalUsd;
          break;
        case CashMovementType.cashOut:
          e -= m.totalUsd;
          break;
        case CashMovementType.adjustment:
          e += m.amountUsd;
          break;
      }
    }
    return e;
  }

  double get drawerCashInHtg => sessionMovements
      .where((m) =>
          _isDrawerTender(m.tender) && m.type == CashMovementType.cashIn)
      .fold(0.0, (s, m) => s + m.totalHtg);

  double get drawerCashOutHtg => sessionMovements
      .where((m) =>
          _isDrawerTender(m.tender) && m.type == CashMovementType.cashOut)
      .fold(0.0, (s, m) => s + m.totalHtg);

  double get drawerCashInUsd => sessionMovements
      .where((m) =>
          _isDrawerTender(m.tender) && m.type == CashMovementType.cashIn)
      .fold(0.0, (s, m) => s + m.totalUsd);

  double get drawerCashOutUsd => sessionMovements
      .where((m) =>
          _isDrawerTender(m.tender) && m.type == CashMovementType.cashOut)
      .fold(0.0, (s, m) => s + m.totalUsd);

  /// Net HTG for this tender (in − out + adjustment amount).
  double tenderNetHtg(PaymentTender tender) {
    var n = 0.0;
    for (final m in sessionMovements) {
      if (m.tender != tender) continue;
      switch (m.type) {
        case CashMovementType.cashIn:
          n += m.totalHtg;
          break;
        case CashMovementType.cashOut:
          n -= m.totalHtg;
          break;
        case CashMovementType.adjustment:
          n += m.amountHtg;
          break;
      }
    }
    return n;
  }

  /// Net USD for this tender (used for the cashUsd card display).
  double tenderNetUsd(PaymentTender tender) {
    var n = 0.0;
    for (final m in sessionMovements) {
      if (m.tender != tender) continue;
      switch (m.type) {
        case CashMovementType.cashIn:
          n += m.totalUsd;
          break;
        case CashMovementType.cashOut:
          n -= m.totalUsd;
          break;
        case CashMovementType.adjustment:
          n += m.amountUsd;
          break;
      }
    }
    return n;
  }

  CashControlState copyWith({
    Object? activeSession = _sentinel,
    List<CashMovement>? movements,
    List<SessionSummary>? sessionHistory,
  }) {
    return CashControlState(
      activeSession: activeSession == _sentinel
          ? this.activeSession
          : activeSession as CashSession?,
      movements: movements ?? this.movements,
      sessionHistory: sessionHistory ?? this.sessionHistory,
    );
  }
}

// ─── Notifier ─────────────────────────────────────────────────────────────────

class CashSessionNotifier extends StateNotifier<CashControlState> {
  CashSessionNotifier({bool hotelFrontDesk = false, bool retail = false})
      : _hotelFrontDesk = hotelFrontDesk,
        _retail = retail,
        assert(!(hotelFrontDesk && retail),
            'CashSessionNotifier : hôtel réception et détail s\'excluent'),
        super(_buildInitialState());

  final bool _hotelFrontDesk;
  final bool _retail;
  int _movementCounter = 0;

  void openSession({
    required String openedBy,
    required double openingBalanceHtg,
    double openingBalanceUsd = 0,
  }) {
    final sessionId = 'session_${DateTime.now().millisecondsSinceEpoch}';
    final session = CashSession(
      id: sessionId,
      openedBy: openedBy,
      openedAt: DateTime.now(),
      openingBalanceHtg: openingBalanceHtg,
      openingBalanceUsd: openingBalanceUsd,
      status: CashSessionStatus.open,
    );
    final now = DateTime.now();
    final seedMovements = _retail
        ? _buildRetailSeedMovements(sessionId, now)
        : _hotelFrontDesk
            ? _buildHotelFrontDeskSeedMovements(sessionId, now)
            : _buildSeedMovements(sessionId, now);
    state = CashControlState(
      activeSession: session,
      movements: [...state.movements, ...seedMovements],
      sessionHistory: state.sessionHistory,
    );
    _movementCounter += seedMovements.length;
  }

  List<CashMovement> _buildSeedMovements(String sessionId, DateTime base) {
    int c = _movementCounter;
    return [
      CashMovement(
        id: 'mov_seed_${c++}',
        sessionId: sessionId,
        type: CashMovementType.cashIn,
        amountHtg: 10100,
        amountUsd: 101.00,
        tipsHtg: 500,
        tipsUsd: 5.00,
        description: 'Paiement table — espèces',
        linkedOrderId: '103',
        linkedTableNumber: 'Table 4',
        linkedWaiterName: 'Claudine',
        timestamp: base.subtract(const Duration(minutes: 42)),
        recordedBy: 'Claudine',
        tender: PaymentTender.cashHtg,
      ),
      CashMovement(
        id: 'mov_seed_${c++}',
        sessionId: sessionId,
        type: CashMovementType.cashIn,
        amountHtg: 8500,
        tipsHtg: 400,
        description: 'Paiement table — MonCash',
        linkedOrderId: '102',
        linkedTableNumber: 'Table 6',
        linkedWaiterName: 'Pierre',
        timestamp: base.subtract(const Duration(minutes: 35)),
        recordedBy: 'Pierre',
        tender: PaymentTender.moncash,
      ),
      CashMovement(
        id: 'mov_seed_${c++}',
        sessionId: sessionId,
        type: CashMovementType.cashIn,
        amountHtg: 3300,
        amountUsd: 33.00,
        tipsHtg: 200,
        tipsUsd: 2.00,
        description: 'Paiement table — espèces',
        linkedOrderId: '101',
        linkedTableNumber: 'Table 2',
        linkedWaiterName: 'Marie-Carmel',
        timestamp: base.subtract(const Duration(minutes: 68)),
        recordedBy: 'Marie-Carmel',
        tender: PaymentTender.cashHtg,
      ),
      CashMovement(
        id: 'mov_seed_${c++}',
        sessionId: sessionId,
        type: CashMovementType.cashIn,
        amountHtg: 6200,
        tipsHtg: 300,
        description: 'Paiement table — carte',
        linkedOrderId: '105',
        linkedTableNumber: 'Table 1',
        linkedWaiterName: 'Claudine',
        timestamp: base.subtract(const Duration(minutes: 20)),
        recordedBy: 'Claudine',
        tender: PaymentTender.card,
      ),
      CashMovement(
        id: 'mov_seed_${c++}',
        sessionId: sessionId,
        type: CashMovementType.cashIn,
        amountHtg: 0,
        amountUsd: 45.00,
        tipsUsd: 5.00,
        description: 'Paiement table — espèces USD',
        linkedTableNumber: 'Terrasse A',
        linkedWaiterName: 'Pierre',
        timestamp: base.subtract(const Duration(minutes: 25)),
        recordedBy: 'Pierre',
        tender: PaymentTender.cashUsd,
      ),
      CashMovement(
        id: 'mov_seed_${c++}',
        sessionId: sessionId,
        type: CashMovementType.cashIn,
        amountHtg: 300,
        amountUsd: 3.00,
        description: 'Pourboire supplémentaire — comptoir',
        linkedTableNumber: 'Terrasse B',
        linkedWaiterName: 'Pierre',
        timestamp: base.subtract(const Duration(minutes: 30)),
        recordedBy: 'Pierre',
        tender: PaymentTender.cashHtg,
      ),
      CashMovement(
        id: 'mov_seed_${c++}',
        sessionId: sessionId,
        type: CashMovementType.cashIn,
        amountHtg: 2500,
        amountUsd: 25.00,
        description: 'Collection — Jean-Pierre Dupont',
        timestamp: base.subtract(const Duration(minutes: 38)),
        recordedBy: 'Gérant',
        tender: PaymentTender.cashHtg,
      ),
      CashMovement(
        id: 'mov_seed_${c++}',
        sessionId: sessionId,
        type: CashMovementType.cashIn,
        amountHtg: 4800,
        description: 'MonCash — group lunch prepay',
        linkedTableNumber: 'Table 8',
        timestamp: base.subtract(const Duration(minutes: 15)),
        recordedBy: 'Gérant',
        tender: PaymentTender.moncash,
      ),
      CashMovement(
        id: 'mov_seed_${c++}',
        sessionId: sessionId,
        type: CashMovementType.cashOut,
        amountHtg: 750,
        amountUsd: 7.50,
        description: 'Cleaning supplies',
        timestamp: base.subtract(const Duration(minutes: 55)),
        recordedBy: 'Gérant',
        tender: PaymentTender.cashHtg,
      ),
      CashMovement(
        id: 'mov_seed_${c++}',
        sessionId: sessionId,
        type: CashMovementType.cashOut,
        amountHtg: 5000,
        amountUsd: 50.00,
        description: 'Morning bank drop',
        timestamp: base.subtract(const Duration(minutes: 90)),
        recordedBy: 'Gérant',
        tender: PaymentTender.cashHtg,
      ),
    ];
  }

  /// Demo movements for retail POS (cash drawer session).
  List<CashMovement> _buildRetailSeedMovements(
      String sessionId, DateTime base) {
    int c = _movementCounter;
    return [
      CashMovement(
        id: 'mov_seed_${c++}',
        sessionId: sessionId,
        type: CashMovementType.cashIn,
        amountHtg: 12800,
        amountUsd: 0,
        tipsHtg: 400,
        tipsUsd: 0,
        description: 'Vente caisse — espèces',
        linkedOrderId: '2',
        linkedTableNumber: 'RCP-2042',
        linkedWaiterName: 'Roseline',
        timestamp: base.subtract(const Duration(minutes: 38)),
        recordedBy: 'Roseline',
        tender: PaymentTender.cashHtg,
      ),
      CashMovement(
        id: 'mov_seed_${c++}',
        sessionId: sessionId,
        type: CashMovementType.cashIn,
        amountHtg: 9450,
        amountUsd: 0,
        tipsHtg: 0,
        description: 'Vente caisse — MonCash',
        linkedOrderId: '5',
        linkedTableNumber: 'RCP-2039',
        linkedWaiterName: 'Marcel',
        timestamp: base.subtract(const Duration(minutes: 52)),
        recordedBy: 'Marcel',
        tender: PaymentTender.moncash,
      ),
      CashMovement(
        id: 'mov_seed_${c++}',
        sessionId: sessionId,
        type: CashMovementType.cashIn,
        amountHtg: 0,
        amountUsd: 62.00,
        tipsUsd: 2.00,
        description: 'Vente caisse — espèces USD',
        linkedOrderId: '3',
        linkedTableNumber: 'RCP-2040',
        linkedWaiterName: 'Marcel',
        timestamp: base.subtract(const Duration(minutes: 44)),
        recordedBy: 'Marcel',
        tender: PaymentTender.cashUsd,
      ),
      CashMovement(
        id: 'mov_seed_${c++}',
        sessionId: sessionId,
        type: CashMovementType.cashIn,
        amountHtg: 22100,
        amountUsd: 0,
        description: 'Vente caisse — carte',
        linkedOrderId: '4',
        linkedTableNumber: 'RCP-2037',
        linkedWaiterName: 'Roseline',
        timestamp: base.subtract(const Duration(minutes: 28)),
        recordedBy: 'Roseline',
        tender: PaymentTender.card,
      ),
      CashMovement(
        id: 'mov_seed_${c++}',
        sessionId: sessionId,
        type: CashMovementType.cashIn,
        amountHtg: 5600,
        amountUsd: 0,
        description: 'Comptoir — épicerie, espèces',
        linkedTableNumber: 'RCP-2043',
        linkedWaiterName: 'Roseline',
        timestamp: base.subtract(const Duration(minutes: 15)),
        recordedBy: 'Roseline',
        tender: PaymentTender.cashHtg,
      ),
      CashMovement(
        id: 'mov_seed_${c++}',
        sessionId: sessionId,
        type: CashMovementType.cashIn,
        amountHtg: 18750,
        amountUsd: 0,
        description: 'Paiement compte grossiste',
        timestamp: base.subtract(const Duration(minutes: 61)),
        recordedBy: 'Gérant',
        tender: PaymentTender.cashHtg,
      ),
      CashMovement(
        id: 'mov_seed_${c++}',
        sessionId: sessionId,
        type: CashMovementType.cashOut,
        amountHtg: 1200,
        amountUsd: 0,
        description: 'Petite caisse — papier reçu',
        timestamp: base.subtract(const Duration(minutes: 72)),
        recordedBy: 'Gérant',
        tender: PaymentTender.cashHtg,
      ),
      CashMovement(
        id: 'mov_seed_${c++}',
        sessionId: sessionId,
        type: CashMovementType.cashOut,
        amountHtg: 15000,
        amountUsd: 150.00,
        description: 'Mid-day bank deposit',
        timestamp: base.subtract(const Duration(minutes: 95)),
        recordedBy: 'Gérant',
        tender: PaymentTender.cashHtg,
      ),
    ];
  }

  /// Demo movements for hotel front desk (mixed tenders).
  List<CashMovement> _buildHotelFrontDeskSeedMovements(
      String sessionId, DateTime base) {
    int c = _movementCounter;
    return [
      CashMovement(
        id: 'mov_seed_${c++}',
        sessionId: sessionId,
        type: CashMovementType.cashIn,
        amountHtg: 18500,
        amountUsd: 0,
        description: 'Chambre 201 — solde au départ',
        linkedTableNumber: 'Chambre 201',
        timestamp: base.subtract(const Duration(minutes: 55)),
        recordedBy: 'Réception',
        tender: PaymentTender.cashHtg,
      ),
      CashMovement(
        id: 'mov_seed_${c++}',
        sessionId: sessionId,
        type: CashMovementType.cashIn,
        amountHtg: 12400,
        amountUsd: 0,
        description: 'MonCash — acompte client',
        timestamp: base.subtract(const Duration(minutes: 48)),
        recordedBy: 'Réception',
        tender: PaymentTender.moncash,
      ),
      CashMovement(
        id: 'mov_seed_${c++}',
        sessionId: sessionId,
        type: CashMovementType.cashIn,
        amountHtg: 32000,
        amountUsd: 0,
        description: 'Carte — prépaiement OTA',
        timestamp: base.subtract(const Duration(minutes: 35)),
        recordedBy: 'Réception',
        tender: PaymentTender.card,
      ),
      CashMovement(
        id: 'mov_seed_${c++}',
        sessionId: sessionId,
        type: CashMovementType.cashIn,
        amountHtg: 15000,
        amountUsd: 0,
        description: 'Check #4421 — corporate',
        timestamp: base.subtract(const Duration(minutes: 28)),
        recordedBy: 'Réception',
        tender: PaymentTender.check,
      ),
      CashMovement(
        id: 'mov_seed_${c++}',
        sessionId: sessionId,
        type: CashMovementType.cashIn,
        amountHtg: 0,
        amountUsd: 45,
        description: 'Espèces USD — minibar',
        timestamp: base.subtract(const Duration(minutes: 15)),
        recordedBy: 'Réception',
        tender: PaymentTender.cashUsd,
      ),
      CashMovement(
        id: 'mov_seed_${c++}',
        sessionId: sessionId,
        type: CashMovementType.cashOut,
        amountHtg: 2000,
        amountUsd: 0,
        description: 'Fonds de caisse vers le restaurant',
        timestamp: base.subtract(const Duration(minutes: 60)),
        recordedBy: 'Gérant',
        tender: PaymentTender.cashHtg,
      ),
      CashMovement(
        id: 'mov_seed_${c++}',
        sessionId: sessionId,
        type: CashMovementType.cashOut,
        amountHtg: 8000,
        amountUsd: 0,
        description: 'Bank deposit',
        timestamp: base.subtract(const Duration(minutes: 120)),
        recordedBy: 'Gérant',
        tender: PaymentTender.cashHtg,
      ),
    ];
  }

  void addMovement({
    required CashMovementType type,
    required double amountHtg,
    double amountUsd = 0,
    double tipsHtg = 0,
    double tipsUsd = 0,
    required String description,
    String? linkedOrderId,
    String? linkedTableNumber,
    String? linkedWaiterName,
    required String recordedBy,
    PaymentTender tender = PaymentTender.cashHtg,
  }) {
    final session = state.activeSession;
    if (session == null || session.status != CashSessionStatus.open) return;
    _movementCounter++;
    final movement = CashMovement(
      id: 'mov_$_movementCounter',
      sessionId: session.id,
      type: type,
      amountHtg: amountHtg,
      amountUsd: amountUsd,
      tipsHtg: tipsHtg,
      tipsUsd: tipsUsd,
      description: description,
      linkedOrderId: linkedOrderId,
      linkedTableNumber: linkedTableNumber,
      linkedWaiterName: linkedWaiterName,
      timestamp: DateTime.now(),
      recordedBy: recordedBy,
      tender: tender,
    );
    state = state.copyWith(movements: [...state.movements, movement]);
  }

  void closeSession({String? note, String closedBy = 'Gérant'}) {
    final session = state.activeSession;
    if (session == null) return;

    // Compute totals from this session's movements
    final sessionMovs = state.movements
        .where((m) => m.sessionId == session.id)
        .toList();
    final totalInHtg = sessionMovs
        .where((m) => m.type == CashMovementType.cashIn)
        .fold(0.0, (s, m) => s + m.totalHtg);
    final totalInUsd = sessionMovs
        .where((m) => m.type == CashMovementType.cashIn)
        .fold(0.0, (s, m) => s + m.totalUsd);
    final totalOutHtg = sessionMovs
        .where((m) => m.type == CashMovementType.cashOut)
        .fold(0.0, (s, m) => s + m.totalHtg);
    final totalOutUsd = sessionMovs
        .where((m) => m.type == CashMovementType.cashOut)
        .fold(0.0, (s, m) => s + m.totalUsd);
    final finalBalanceHtg =
        session.openingBalanceHtg + totalInHtg - totalOutHtg;
    final finalBalanceUsd =
        session.openingBalanceUsd + totalInUsd - totalOutUsd;

    final closedSession = session.copyWith(
      closedAt: DateTime.now(),
      status: CashSessionStatus.closed,
      closingNote: note,
    );

    final summary = SessionSummary(
      session: closedSession,
      totalInHtg: totalInHtg,
      totalInUsd: totalInUsd,
      totalOutHtg: totalOutHtg,
      totalOutUsd: totalOutUsd,
      finalBalanceHtg: finalBalanceHtg,
      finalBalanceUsd: finalBalanceUsd,
      closedBy: closedBy,
    );

    state = state.copyWith(
      activeSession: closedSession,
      sessionHistory: [summary, ...state.sessionHistory],
    );
  }
}

// ─── Seed history ─────────────────────────────────────────────────────────────

CashControlState _buildInitialState() {
  final now = DateTime.now();

  DateTime day(int daysBack, int hour, int minute) {
    final d = now.subtract(Duration(days: daysBack));
    return DateTime(d.year, d.month, d.day, hour, minute);
  }

  // ── This week ─────────────────────────────────────────────────────────────

  // Yesterday — balanced
  final sess1 = CashSession(
    id: 'session_seed_1',
    openedBy: 'Gérant',
    openedAt: day(1, 8, 0),
    closedAt: day(1, 16, 30),
    openingBalanceHtg: 3000,
    openingBalanceUsd: 30,
    status: CashSessionStatus.closed,
    closingNote: 'Tout est juste, caisse équilibrée.',
  );
  final summary1 = SessionSummary(
    session: sess1,
    totalInHtg: 28450,
    totalInUsd: 284.50,
    totalOutHtg: 8200,
    totalOutUsd: 82.00,
    finalBalanceHtg: 23250,
    finalBalanceUsd: 232.50,
    closedBy: 'Gérant',
  );

  // 2 days ago — short
  final sess2 = CashSession(
    id: 'session_seed_2',
    openedBy: 'Gérant',
    openedAt: day(2, 7, 30),
    closedAt: day(2, 15, 45),
    openingBalanceHtg: 5000,
    openingBalanceUsd: 50,
    status: CashSessionStatus.closed,
    closingNote: 'Manque de 400 HTG — recomptage confirmé, en cours de vérification.',
  );
  final summary2 = SessionSummary(
    session: sess2,
    totalInHtg: 22100,
    totalInUsd: 221.00,
    totalOutHtg: 6800,
    totalOutUsd: 68.00,
    finalBalanceHtg: 19900,
    finalBalanceUsd: 202.00,
    closedBy: 'Supervisor',
  );

  // 4 days ago — balanced
  final sess3 = CashSession(
    id: 'session_seed_3',
    openedBy: 'Cashier A',
    openedAt: day(4, 8, 15),
    closedAt: day(4, 17, 0),
    openingBalanceHtg: 2500,
    openingBalanceUsd: 25,
    status: CashSessionStatus.closed,
    closingNote: 'Service calme, rien à signaler.',
  );
  final summary3 = SessionSummary(
    session: sess3,
    totalInHtg: 31200,
    totalInUsd: 312.00,
    totalOutHtg: 9500,
    totalOutUsd: 95.00,
    finalBalanceHtg: 24200,
    finalBalanceUsd: 242.00,
    closedBy: 'Cashier A',
  );

  // ── Last week ─────────────────────────────────────────────────────────────

  // 8 days ago — balanced
  final sess4 = CashSession(
    id: 'session_seed_4',
    openedBy: 'Gérant',
    openedAt: day(8, 8, 0),
    closedAt: day(8, 16, 0),
    openingBalanceHtg: 4000,
    openingBalanceUsd: 40,
    status: CashSessionStatus.closed,
    closingNote: 'Good day, high lunch volume.',
  );
  final summary4 = SessionSummary(
    session: sess4,
    totalInHtg: 41500,
    totalInUsd: 415.00,
    totalOutHtg: 12000,
    totalOutUsd: 120.00,
    finalBalanceHtg: 33500,
    finalBalanceUsd: 335.00,
    closedBy: 'Gérant',
  );

  // 10 days ago — short
  final sess5 = CashSession(
    id: 'session_seed_5',
    openedBy: 'Cashier B',
    openedAt: day(10, 7, 45),
    closedAt: day(10, 15, 30),
    openingBalanceHtg: 3500,
    openingBalanceUsd: 35,
    status: CashSessionStatus.closed,
    closingNote: 'HTG 250 discrepancy — under review.',
  );
  final summary5 = SessionSummary(
    session: sess5,
    totalInHtg: 19800,
    totalInUsd: 198.00,
    totalOutHtg: 5500,
    totalOutUsd: 55.00,
    finalBalanceHtg: 17550,
    finalBalanceUsd: 178.00,
    closedBy: 'Cashier B',
  );

  // 12 days ago — balanced
  final sess6 = CashSession(
    id: 'session_seed_6',
    openedBy: 'Gérant',
    openedAt: day(12, 8, 30),
    closedAt: day(12, 17, 15),
    openingBalanceHtg: 3000,
    openingBalanceUsd: 30,
    status: CashSessionStatus.closed,
    closingNote: 'Normal day.',
  );
  final summary6 = SessionSummary(
    session: sess6,
    totalInHtg: 25600,
    totalInUsd: 256.00,
    totalOutHtg: 7800,
    totalOutUsd: 78.00,
    finalBalanceHtg: 20800,
    finalBalanceUsd: 208.00,
    closedBy: 'Gérant',
  );

  // ── Two weeks ago ─────────────────────────────────────────────────────────

  // 15 days ago — balanced
  final sess7 = CashSession(
    id: 'session_seed_7',
    openedBy: 'Cashier A',
    openedAt: day(15, 8, 0),
    closedAt: day(15, 16, 45),
    openingBalanceHtg: 2000,
    openingBalanceUsd: 20,
    status: CashSessionStatus.closed,
  );
  final summary7 = SessionSummary(
    session: sess7,
    totalInHtg: 18900,
    totalInUsd: 189.00,
    totalOutHtg: 6100,
    totalOutUsd: 61.00,
    finalBalanceHtg: 14800,
    finalBalanceUsd: 148.00,
    closedBy: 'Cashier A',
  );

  // 18 days ago — short
  final sess8 = CashSession(
    id: 'session_seed_8',
    openedBy: 'Gérant',
    openedAt: day(18, 7, 30),
    closedAt: day(18, 16, 0),
    openingBalanceHtg: 4500,
    openingBalanceUsd: 45,
    status: CashSessionStatus.closed,
    closingNote: 'Excédent de 10 USD — un billet en trop dans le tiroir.',
  );
  final summary8 = SessionSummary(
    session: sess8,
    totalInHtg: 33000,
    totalInUsd: 330.00,
    totalOutHtg: 10000,
    totalOutUsd: 100.00,
    finalBalanceHtg: 27500,
    finalBalanceUsd: 285.00,
    closedBy: 'Gérant',
  );

  return CashControlState(sessionHistory: [
    summary1, summary2, summary3,   // this week
    summary4, summary5, summary6,   // last week
    summary7, summary8,             // two weeks ago
  ]);
}

// ─── Provider ─────────────────────────────────────────────────────────────────

final cashSessionProvider =
    StateNotifierProvider<CashSessionNotifier, CashControlState>(
  (ref) => CashSessionNotifier(),
);

/// Hotel front desk: mixed tenders (MonCash, card, check) + physical drawer.
final hotelFrontDeskCashProvider =
    StateNotifierProvider<CashSessionNotifier, CashControlState>(
  (ref) => CashSessionNotifier(hotelFrontDesk: true),
);

/// Retail POS: separate drawer session from restaurant / hotel.
final retailCashSessionProvider =
    StateNotifierProvider<CashSessionNotifier, CashControlState>(
  (ref) => CashSessionNotifier(retail: true),
);

const Object _sentinel = Object();
