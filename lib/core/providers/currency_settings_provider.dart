import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/supported_countries.dart';
import '../models/currency_settings.dart';

class CurrencySettingsNotifier extends StateNotifier<CurrencySettings> {
  CurrencySettingsNotifier() : super(CurrencySettings.haitiDefault);

  void applyFromRegistration({
    required String countryCode,
    required BusinessCurrencyMode mode,
    double? usdToLocalRate,
  }) {
    final c = countryByCode(countryCode);
    if (c == null) {
      state = CurrencySettings.haitiDefault.copyWith(mode: mode);
      return;
    }
    final rate = c.currencyCode == 'USD'
        ? 1.0
        : (usdToLocalRate ?? state.usdToLocalRate);
    state = CurrencySettings(
      countryCode: c.code,
      countryName: c.name,
      localCurrencyCode: c.currencyCode,
      localCurrencyName: c.currencyName,
      usdToLocalRate: rate,
      mode: mode,
    );
  }

  void setFromSettings({
    required String countryCode,
    required BusinessCurrencyMode mode,
    required double usdToLocalRate,
  }) {
    final c = countryByCode(countryCode);
    if (c == null) return;
    final rate = c.currencyCode == 'USD' ? 1.0 : usdToLocalRate;
    state = CurrencySettings(
      countryCode: c.code,
      countryName: c.name,
      localCurrencyCode: c.currencyCode,
      localCurrencyName: c.currencyName,
      usdToLocalRate: rate,
      mode: mode,
    );
  }
}

final currencySettingsProvider =
    StateNotifierProvider<CurrencySettingsNotifier, CurrencySettings>(
  (ref) => CurrencySettingsNotifier(),
);
