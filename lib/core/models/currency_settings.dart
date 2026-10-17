import 'package:flutter/foundation.dart';

/// How the business prices and accepts money.
enum BusinessCurrencyMode {
  /// Prices and cash in local currency only.
  localOnly,

  /// Prices and cash in USD only (e.g. dollarized economy).
  usdOnly,

  /// Local is primary; USD still used for cards / reference / optional cash.
  both,
}

@immutable
class CurrencySettings {
  /// ISO 3166-1 alpha-2 (e.g. HT, US).
  final String countryCode;

  /// Display name for the country.
  final String countryName;

  /// ISO 4217 (e.g. HTG, USD).
  final String localCurrencyCode;

  final String localCurrencyName;

  /// Local currency units per **1 USD** (e.g. ~135 HTG per $1).
  /// If local currency **is** USD, use `1.0`.
  final double usdToLocalRate;

  final BusinessCurrencyMode mode;

  const CurrencySettings({
    required this.countryCode,
    required this.countryName,
    required this.localCurrencyCode,
    required this.localCurrencyName,
    required this.usdToLocalRate,
    required this.mode,
  });

  /// Default mock: Haiti + HTG (matches previous app behavior).
  static const CurrencySettings haitiDefault = CurrencySettings(
    countryCode: 'HT',
    countryName: 'Haïti',
    localCurrencyCode: 'HTG',
    localCurrencyName: 'Gourde haïtienne',
    usdToLocalRate: 135.0,
    mode: BusinessCurrencyMode.both,
  );

  bool get isLocalUsd => localCurrencyCode == 'USD';

  /// Whether to show a USD equivalent line for a local amount.
  bool get showUsdEquivalence {
    if (isLocalUsd) return false;
    return mode != BusinessCurrencyMode.usdOnly;
  }

  CurrencySettings copyWith({
    String? countryCode,
    String? countryName,
    String? localCurrencyCode,
    String? localCurrencyName,
    double? usdToLocalRate,
    BusinessCurrencyMode? mode,
  }) {
    return CurrencySettings(
      countryCode: countryCode ?? this.countryCode,
      countryName: countryName ?? this.countryName,
      localCurrencyCode: localCurrencyCode ?? this.localCurrencyCode,
      localCurrencyName: localCurrencyName ?? this.localCurrencyName,
      usdToLocalRate: usdToLocalRate ?? this.usdToLocalRate,
      mode: mode ?? this.mode,
    );
  }
}
