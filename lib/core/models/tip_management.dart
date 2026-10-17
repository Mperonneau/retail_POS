import 'package:flutter_riverpod/flutter_riverpod.dart';

// ─── Enums ────────────────────────────────────────────────────────────────────

enum TipEntryType { tip, adjustment, payout }

// ─── Model ────────────────────────────────────────────────────────────────────

class TipEntry {
  final String id;
  final String waiterName;

  /// For `tip`: always positive.
  /// For `adjustment`: positive = add, negative = subtract.
  /// For `payout`: positive (amount being paid out; balance calculation subtracts it).
  final double amountHtg;
  final double amountUsd;
  final TipEntryType type;
  final String? linkedTable;
  final String reason;
  final DateTime timestamp;

  const TipEntry({
    required this.id,
    required this.waiterName,
    required this.amountHtg,
    required this.amountUsd,
    required this.type,
    this.linkedTable,
    required this.reason,
    required this.timestamp,
  });
}

// ─── State ────────────────────────────────────────────────────────────────────

class TipState {
  final List<TipEntry> entries;

  const TipState({this.entries = const []});

  /// Ordered list of unique waiter names in order of first appearance.
  List<String> get waiterNames {
    final seen = <String>{};
    final names = <String>[];
    for (final e in entries) {
      if (seen.add(e.waiterName)) names.add(e.waiterName);
    }
    return names;
  }

  double balanceHtgFor(String waiter) => entries
      .where((e) => e.waiterName == waiter)
      .fold(0.0, (s, e) =>
          e.type == TipEntryType.payout ? s - e.amountHtg : s + e.amountHtg);

  double balanceUsdFor(String waiter) => entries
      .where((e) => e.waiterName == waiter)
      .fold(0.0, (s, e) =>
          e.type == TipEntryType.payout ? s - e.amountUsd : s + e.amountUsd);

  /// All entries for a waiter, newest first.
  List<TipEntry> historyFor(String waiter) => entries
      .where((e) => e.waiterName == waiter)
      .toList()
      .reversed
      .toList();

  double get totalOutstandingHtg => waiterNames
      .fold(0.0, (s, w) => s + balanceHtgFor(w).clamp(0.0, double.infinity));
  double get totalOutstandingUsd => waiterNames
      .fold(0.0, (s, w) => s + balanceUsdFor(w).clamp(0.0, double.infinity));
}

// ─── Notifier ─────────────────────────────────────────────────────────────────

class TipNotifier extends StateNotifier<TipState> {
  TipNotifier() : super(_buildSeedState());

  int _counter = 100;

  void addTip({
    required String waiterName,
    required double amountHtg,
    required double amountUsd,
    String? linkedTable,
    String reason = 'Pourboire de table',
  }) {
    _counter++;
    state = TipState(entries: [
      ...state.entries,
      TipEntry(
        id: 'tip_$_counter',
        waiterName: waiterName,
        amountHtg: amountHtg,
        amountUsd: amountUsd,
        type: TipEntryType.tip,
        linkedTable: linkedTable,
        reason: reason,
        timestamp: DateTime.now(),
      ),
    ]);
  }

  void addAdjustment({
    required String waiterName,
    required double amountHtg,
    required double amountUsd,
    required bool isSubtraction,
    required String reason,
  }) {
    _counter++;
    state = TipState(entries: [
      ...state.entries,
      TipEntry(
        id: 'tip_$_counter',
        waiterName: waiterName,
        amountHtg: isSubtraction ? -amountHtg : amountHtg,
        amountUsd: isSubtraction ? -amountUsd : amountUsd,
        type: TipEntryType.adjustment,
        reason: reason,
        timestamp: DateTime.now(),
      ),
    ]);
  }

  void payOut({required String waiterName, String recordedBy = 'Gérant'}) {
    final balHtg = state.balanceHtgFor(waiterName);
    final balUsd = state.balanceUsdFor(waiterName);
    if (balHtg <= 0 && balUsd <= 0) return;
    _counter++;
    state = TipState(entries: [
      ...state.entries,
      TipEntry(
        id: 'tip_$_counter',
        waiterName: waiterName,
        amountHtg: balHtg.clamp(0.0, double.infinity),
        amountUsd: balUsd.clamp(0.0, double.infinity),
        type: TipEntryType.payout,
        reason: 'Tip payout by $recordedBy',
        timestamp: DateTime.now(),
      ),
    ]);
  }
}

// ─── Provider ─────────────────────────────────────────────────────────────────

final tipProvider =
    StateNotifierProvider<TipNotifier, TipState>((ref) => TipNotifier());

// ─── Seed data ────────────────────────────────────────────────────────────────

TipState _buildSeedState() {
  final now = DateTime.now();

  // Helper: date at N days back, specific hour:minute
  DateTime d(int daysBack, int hour, int minute) {
    final base = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: daysBack));
    return base.add(Duration(hours: hour, minutes: minute));
  }

  return TipState(entries: [
    // ══════════════════════════════════════════════════════════════════
    // TODAY
    // ══════════════════════════════════════════════════════════════════

    // Marie-Carmel — today
    TipEntry(id: 'ts_1', waiterName: 'Marie-Carmel', amountHtg: 200, amountUsd: 2.00, type: TipEntryType.tip, linkedTable: 'Table 4', reason: 'Pourboire de table', timestamp: d(0, 12, 18)),
    TipEntry(id: 'ts_2', waiterName: 'Marie-Carmel', amountHtg: 250, amountUsd: 2.50, type: TipEntryType.tip, linkedTable: 'Table 2', reason: 'Pourboire de table', timestamp: d(0, 11, 52)),
    TipEntry(id: 'ts_3', waiterName: 'Marie-Carmel', amountHtg: 200, amountUsd: 2.00, type: TipEntryType.tip, linkedTable: 'Table 7', reason: 'Client très satisfait — pourboire supplémentaire', timestamp: d(0, 12, 30)),

    // Claudine — today
    TipEntry(id: 'ts_4', waiterName: 'Claudine', amountHtg: 500, amountUsd: 5.00, type: TipEntryType.tip, linkedTable: 'Table 4', reason: 'Pourboire de table', timestamp: d(0, 11, 25)),
    TipEntry(id: 'ts_5', waiterName: 'Claudine', amountHtg: 200, amountUsd: 2.00, type: TipEntryType.tip, linkedTable: 'Table 6', reason: 'Pourboire de table', timestamp: d(0, 10, 30)),
    TipEntry(id: 'ts_6', waiterName: 'Claudine', amountHtg: -200, amountUsd: -2.00, type: TipEntryType.adjustment, reason: 'Correction — pourboire partagé avec Joseph', timestamp: d(0, 12, 35)),

    // Pierre — today
    TipEntry(id: 'ts_7', waiterName: 'Pierre', amountHtg: 250, amountUsd: 2.50, type: TipEntryType.tip, linkedTable: 'Terrasse B', reason: 'Pourboire de table', timestamp: d(0, 11, 05)),
    TipEntry(id: 'ts_8', waiterName: 'Pierre', amountHtg: 200, amountUsd: 2.00, type: TipEntryType.tip, linkedTable: 'Terrasse A', reason: 'Pourboire de table', timestamp: d(0, 12, 45)),

    // Joseph — today
    TipEntry(id: 'ts_9', waiterName: 'Joseph', amountHtg: 300, amountUsd: 3.00, type: TipEntryType.tip, linkedTable: 'Table 3', reason: 'Pourboire de table', timestamp: d(0, 10, 50)),
    TipEntry(id: 'ts_10', waiterName: 'Joseph', amountHtg: 200, amountUsd: 2.00, type: TipEntryType.adjustment, reason: 'Pourboire partagé de Claudine — Table 6', timestamp: d(0, 12, 36)),

    // ══════════════════════════════════════════════════════════════════
    // YESTERDAY
    // ══════════════════════════════════════════════════════════════════

    TipEntry(id: 'ts_11', waiterName: 'Marie-Carmel', amountHtg: 350, amountUsd: 3.50, type: TipEntryType.tip, linkedTable: 'Table 5', reason: 'Pourboire de table', timestamp: d(1, 19, 40)),
    TipEntry(id: 'ts_12', waiterName: 'Marie-Carmel', amountHtg: 1200, amountUsd: 12.00, type: TipEntryType.payout, reason: 'Tip payout by Manager', timestamp: d(1, 20, 00)),
    TipEntry(id: 'ts_13', waiterName: 'Claudine', amountHtg: 400, amountUsd: 4.00, type: TipEntryType.tip, linkedTable: 'Table 1', reason: 'Pourboire de table', timestamp: d(1, 18, 15)),
    TipEntry(id: 'ts_14', waiterName: 'Pierre', amountHtg: 300, amountUsd: 3.00, type: TipEntryType.tip, linkedTable: 'Terrasse A', reason: 'Pourboire de table', timestamp: d(1, 19, 05)),
    TipEntry(id: 'ts_15', waiterName: 'Joseph', amountHtg: 150, amountUsd: 1.50, type: TipEntryType.tip, linkedTable: 'Table 8', reason: 'Pourboire de table', timestamp: d(1, 20, 30)),

    // ══════════════════════════════════════════════════════════════════
    // 3 DAYS AGO
    // ══════════════════════════════════════════════════════════════════

    TipEntry(id: 'ts_16', waiterName: 'Claudine', amountHtg: 600, amountUsd: 6.00, type: TipEntryType.tip, linkedTable: 'Table 3', reason: 'Pourboire de table', timestamp: d(3, 12, 10)),
    TipEntry(id: 'ts_17', waiterName: 'Marie-Carmel', amountHtg: 250, amountUsd: 2.50, type: TipEntryType.tip, linkedTable: 'Table 9', reason: 'Pourboire de table', timestamp: d(3, 13, 45)),
    TipEntry(id: 'ts_18', waiterName: 'Pierre', amountHtg: -100, amountUsd: -1.00, type: TipEntryType.adjustment, reason: 'Correction d\'une erreur de pourboire', timestamp: d(3, 14, 00)),
    TipEntry(id: 'ts_19', waiterName: 'Joseph', amountHtg: 500, amountUsd: 5.00, type: TipEntryType.tip, linkedTable: 'VIP Lounge', reason: 'Pourboire table VIP', timestamp: d(3, 20, 15)),

    // ══════════════════════════════════════════════════════════════════
    // 5 DAYS AGO
    // ══════════════════════════════════════════════════════════════════

    TipEntry(id: 'ts_20', waiterName: 'Marie-Carmel', amountHtg: 300, amountUsd: 3.00, type: TipEntryType.tip, linkedTable: 'Table 2', reason: 'Pourboire de table', timestamp: d(5, 11, 30)),
    TipEntry(id: 'ts_21', waiterName: 'Claudine', amountHtg: 950, amountUsd: 9.50, type: TipEntryType.payout, reason: 'Tip payout by Manager', timestamp: d(5, 12, 00)),
    TipEntry(id: 'ts_22', waiterName: 'Joseph', amountHtg: 200, amountUsd: 2.00, type: TipEntryType.tip, linkedTable: 'Table 5', reason: 'Pourboire de table', timestamp: d(5, 19, 20)),
    TipEntry(id: 'ts_23', waiterName: 'Pierre', amountHtg: 350, amountUsd: 3.50, type: TipEntryType.tip, linkedTable: 'Terrasse B', reason: 'Pourboire de table', timestamp: d(5, 20, 10)),

    // ══════════════════════════════════════════════════════════════════
    // 8 DAYS AGO  (outside 7-day default → visible after "Charger plus")
    // ══════════════════════════════════════════════════════════════════

    TipEntry(id: 'ts_24', waiterName: 'Marie-Carmel', amountHtg: 400, amountUsd: 4.00, type: TipEntryType.tip, linkedTable: 'Table 6', reason: 'Pourboire de table', timestamp: d(8, 12, 00)),
    TipEntry(id: 'ts_25', waiterName: 'Claudine', amountHtg: 300, amountUsd: 3.00, type: TipEntryType.tip, linkedTable: 'Table 1', reason: 'Pourboire de table', timestamp: d(8, 18, 45)),
    TipEntry(id: 'ts_26', waiterName: 'Joseph', amountHtg: 700, amountUsd: 7.00, type: TipEntryType.payout, reason: 'Tip payout by Manager', timestamp: d(8, 19, 00)),
    TipEntry(id: 'ts_27', waiterName: 'Pierre', amountHtg: 250, amountUsd: 2.50, type: TipEntryType.tip, linkedTable: 'Terrasse A', reason: 'Pourboire de table', timestamp: d(8, 13, 20)),

    // ══════════════════════════════════════════════════════════════════
    // 13 DAYS AGO  (visible after 2× "Charger plus")
    // ══════════════════════════════════════════════════════════════════

    TipEntry(id: 'ts_28', waiterName: 'Marie-Carmel', amountHtg: 500, amountUsd: 5.00, type: TipEntryType.tip, linkedTable: 'Table 3', reason: 'Pourboire de table', timestamp: d(13, 12, 30)),
    TipEntry(id: 'ts_29', waiterName: 'Claudine', amountHtg: 200, amountUsd: 2.00, type: TipEntryType.tip, linkedTable: 'Table 7', reason: 'Pourboire de table', timestamp: d(13, 19, 50)),
    TipEntry(id: 'ts_30', waiterName: 'Joseph', amountHtg: 150, amountUsd: 1.50, type: TipEntryType.tip, linkedTable: 'Table 2', reason: 'Pourboire de table', timestamp: d(13, 20, 05)),
  ]);
}
