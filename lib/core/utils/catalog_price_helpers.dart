import 'package:flutter/widgets.dart';

import '../models/currency_settings.dart';
import 'currency_formatter.dart';

/// Single-field catalog pricing (rooms, menu, products) from [CurrencySettings].
class CatalogPriceLogic {
  CatalogPriceLogic._();

  /// User enters USD when local currency is USD, or when mode is [BusinessCurrencyMode.usdOnly].
  static bool entryCurrencyIsUsd(CurrencySettings s) =>
      s.isLocalUsd || s.mode == BusinessCurrencyMode.usdOnly;

  /// Primary label for the price field.
  static String priceFieldLabel(CurrencySettings s) {
    if (entryCurrencyIsUsd(s)) return 'Prix (USD)';
    return 'Prix (${s.localCurrencyCode})';
  }

  static String priceFieldPrefix(CurrencySettings s) {
    if (entryCurrencyIsUsd(s)) return r'$ ';
    return '${s.localCurrencyCode} ';
  }

  /// Label for the overnight room-rate field — currency code always visible.
  static String overnightRateLabel(CurrencySettings s) =>
      entryCurrencyIsUsd(s)
          ? 'Per night (USD)'
          : 'Per night (${s.localCurrencyCode})';

  /// Label for the hourly room-rate field — currency code always visible.
  static String hourlyRateLabel(CurrencySettings s) =>
      entryCurrencyIsUsd(s)
          ? 'Per hour (USD)'
          : 'Per hour (${s.localCurrencyCode})';

  /// Seed the single price field when editing an existing row.
  static String initialPriceFieldText(
    CurrencySettings s,
    double priceHtg,
    double priceUsd,
  ) {
    if (s.isLocalUsd) {
      return priceHtg.toStringAsFixed(2);
    }
    if (s.mode == BusinessCurrencyMode.usdOnly) {
      if (priceUsd > 0) return priceUsd.toStringAsFixed(2);
      return CurrencyMath.localToUsd(s, priceHtg).toStringAsFixed(2);
    }
    if (priceHtg % 1 == 0) return priceHtg.toStringAsFixed(0);
    return priceHtg.toStringAsFixed(2);
  }

  /// Persists mock models: local amount in [priceHtg], parallel [priceUsd] for legacy totals.
  static ({double priceHtg, double priceUsd}) commitParsed(
    CurrencySettings s,
    double parsed,
  ) {
    if (s.isLocalUsd) {
      return (priceHtg: parsed, priceUsd: parsed);
    }
    if (s.mode == BusinessCurrencyMode.usdOnly) {
      final usd = parsed;
      final local = CurrencyMath.usdToLocal(s, usd);
      return (priceHtg: local, priceUsd: usd);
    }
    final local = parsed;
    final usd = CurrencyMath.localToUsd(s, local);
    return (priceHtg: local, priceUsd: usd);
  }

  /// Non-saved hint line (opposite currency), or null.
  static String? priceHintText(
    BuildContext context,
    CurrencySettings s,
    String rawText,
  ) {
    final v = double.tryParse(rawText.trim());
    if (v == null || v <= 0) return null;

    if (entryCurrencyIsUsd(s)) {
      if (s.isLocalUsd) return null;
      final local = CurrencyMath.usdToLocal(s, v);
      return '≈ ${CurrencyFormatter.formatLocalFromSettings(s, local)}';
    }
    if (!s.showUsdEquivalence) return null;
    return CurrencyFormatter.usdEquivalentOrNull(context, v);
  }
}
