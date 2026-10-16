import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/currency_settings.dart';
import '../providers/currency_settings_provider.dart';

class CurrencyFormatter {
  CurrencyFormatter._();

  static final NumberFormat _amountOnlyFormat =
      NumberFormat('#,##0.00', 'fr_HT');

  /// Amount without currency symbol — for line-item columns where the currency
  /// is already shown in the summary section.
  static String amountOnly(double amount) =>
      _amountOnlyFormat.format(amount);

  static final NumberFormat _usdFormat = NumberFormat.currency(
    locale: 'en_US',
    symbol: r'$',
    decimalDigits: 2,
  );

  static final NumberFormat _compactFormat =
      NumberFormat.compact(locale: 'en_US');

  /// Reads [currencySettingsProvider] from [context] (requires [ProviderScope]).
  static CurrencySettings _settings(BuildContext context) =>
      ProviderScope.containerOf(context).read(currencySettingsProvider);

  /// Primary business currency (local) — use in UI instead of hardcoded HTG.
  static String local(BuildContext context, double amount) =>
      formatLocalFromSettings(_settings(context), amount);

  /// USD equivalent for a **local-currency** amount (uses settings rate).
  static String usdEquivalent(BuildContext context, double localAmount) {
    final s = _settings(context);
    if (!s.showUsdEquivalence || s.usdToLocalRate <= 0) {
      return '';
    }
    final usdVal = CurrencyMath.localToUsd(s, localAmount);
    return '≈ ${_usdFormat.format(usdVal)}';
  }

  /// Same as [usdEquivalent] but returns a non-empty string only when useful.
  static String? usdEquivalentOrNull(BuildContext context, double localAmount) {
    final line = usdEquivalent(context, localAmount);
    return line.isEmpty ? null : line;
  }

  /// One line: primary local amount + small USD hint when applicable.
  static Widget localWithUsdHint(
    BuildContext context,
    double localAmount, {
    TextStyle? primaryStyle,
    TextStyle? hintStyle,
  }) {
    final primary = local(context, localAmount);
    final hint = usdEquivalentOrNull(context, localAmount);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(primary, style: primaryStyle),
        if (hint != null)
          Text(hint, style: hintStyle),
      ],
    );
  }

  static String formatLocalFromSettings(CurrencySettings s, double amount) {
    final sym = _symbolFor(s.localCurrencyCode);
    final fmt = NumberFormat.currency(
      locale: _localeFor(s.localCurrencyCode),
      symbol: sym,
      decimalDigits: 2,
    );
    return fmt.format(amount);
  }

  /// Plain USD formatting (tourist/card/reference).
  static String usd(double amount) => _usdFormat.format(amount);

  static String compact(double amount) => _compactFormat.format(amount);

  /// Prefer [local] + [usdEquivalent]; kept for legacy call sites.
  static String both(double localAmount, double usdAmount) =>
      '${formatLocalFromSettings(CurrencySettings.haitiDefault, localAmount)} / ${usd(usdAmount)}';

  static String formatChange(double percentChange) {
    final sign = percentChange >= 0 ? '+' : '';
    return '$sign${percentChange.toStringAsFixed(1)}%';
  }

  static String _symbolFor(String code) {
    switch (code) {
      case 'HTG':
        return 'HTG ';
      case 'USD':
        return r'$';
      case 'DOP':
        return 'RD\$ ';
      case 'JMD':
        return 'J\$ ';
      case 'BSD':
        return r'B$ ';
      case 'BBD':
        return r'Bds$ ';
      case 'TTD':
        return r'TT$ ';
      default:
        return '$code ';
    }
  }

  static String _localeFor(String code) {
    switch (code) {
      case 'HTG':
        return 'fr_HT';
      case 'DOP':
        return 'es_DO';
      case 'JMD':
        return 'en_JM';
      default:
        return 'en_US';
    }
  }
}

/// Pure conversion helpers (no BuildContext).
class CurrencyMath {
  CurrencyMath._();

  static double localToUsd(CurrencySettings s, double localAmount) {
    if (s.isLocalUsd) return localAmount;
    if (s.usdToLocalRate <= 0) return 0;
    return localAmount / s.usdToLocalRate;
  }

  static double usdToLocal(CurrencySettings s, double usdAmount) {
    if (s.isLocalUsd) return usdAmount;
    return usdAmount * s.usdToLocalRate;
  }
}
