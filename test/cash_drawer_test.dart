import 'package:flutter_test/flutter_test.dart';
import 'package:retail_pos/core/models/cash_control.dart';

void main() {
  test('drawer keeps HTG and USD apart and stores card in USD', () {
    final notifier = CashSessionNotifier(retail: true);
    notifier.openSession(
      openedBy: 'Gérant',
      openingBalanceHtg: 12,
      openingBalanceUsd: 52,
    );

    final state = notifier.state;
    expect(state.tenderNetUsd(PaymentTender.card), 164);
    expect(state.tenderNetHtg(PaymentTender.card), 0);
    expect(state.tenderNetHtg(PaymentTender.moncash), 9450);
    expect(state.tenderNetUsd(PaymentTender.moncash), 0);

    // Cash HTG in the drawer: 12800 + 400 tips + 5600 + 18750 − 1200 − 15000.
    expect(state.drawerCashInHtg, 37550);
    expect(state.drawerCashOutHtg, 16200);
    expect(state.drawerExpectedHtg, 12 + 37550 - 16200);
    // Cash USD: 62 + 2 tips. Card dollars are not in the drawer.
    expect(state.drawerCashInUsd, 64);
    expect(state.drawerCashOutUsd, 0);
    expect(state.drawerExpectedUsd, 116);
    expect(state.drawerExpectedUsd, isNot(state.drawerExpectedHtg));
  });

  test('fin de service leaves the session open', () {
    final notifier = CashSessionNotifier(retail: true);
    notifier.openSession(
      openedBy: 'Roseline',
      openingBalanceHtg: 12,
      openingBalanceUsd: 52,
    );

    final handoff = notifier.recordShiftHandoff(
      closedByName: 'Roseline',
      receivedByName: 'Jean-Marc',
      countedHtg: 21000,
      countedUsd: 116,
      note: 'Relève',
    );

    expect(handoff, isNotNull);
    expect(notifier.state.activeSession?.status, CashSessionStatus.open);
    expect(notifier.state.shiftHandoffs, hasLength(1));
    expect(handoff!.receivedByName, 'Jean-Marc');
    expect(handoff.expectedHtg, notifier.state.drawerExpectedHtg);
    expect(handoff.deltaUsd, 0);
  });

  test('clôture stores the counted drawer, not a conversion', () {
    final notifier = CashSessionNotifier(retail: true);
    notifier.openSession(
      openedBy: 'Gérant',
      openingBalanceHtg: 12,
      openingBalanceUsd: 52,
    );
    final expectedHtg = notifier.state.drawerExpectedHtg;
    final expectedUsd = notifier.state.drawerExpectedUsd;

    notifier.closeSession(
      countedHtg: expectedHtg - 50,
      countedUsd: expectedUsd + 5,
      closedBy: 'Gérant',
      note: 'Fin de journée',
    );

    final summary = notifier.state.sessionHistory.first;
    expect(notifier.state.activeSession?.status, CashSessionStatus.closed);
    expect(summary.expectedHtg, expectedHtg);
    expect(summary.expectedUsd, expectedUsd);
    expect(summary.finalBalanceHtg, expectedHtg - 50);
    expect(summary.finalBalanceUsd, expectedUsd + 5);
    expect(summary.overShortHtg, -50);
    expect(summary.overShortUsd, 5);
    expect(summary.isBalanced, isFalse);
  });
}
