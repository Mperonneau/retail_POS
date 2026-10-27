import 'package:intl/intl.dart';

/// Prices lead with US dollars; gourdes follow. MonCash bills stay in HTG.
class Money {
  Money._();

  static final _usd = NumberFormat.currency(locale: 'en_US', symbol: r'$', decimalDigits: 2);
  static final _htg = NumberFormat.currency(locale: 'fr_HT', symbol: 'HTG ', decimalDigits: 0);
  static final _htgExact = NumberFormat.currency(locale: 'fr_HT', symbol: 'HTG ', decimalDigits: 2);

  static int usdCents(double htg, double rate) =>
      htg <= 0 || rate <= 0 ? 0 : (htg / rate * 100).round();

  static String usdFromHtg(double htg, double rate) => usd(usdCents(htg, rate));

  static String usd(int cents) => 'US ${_usd.format(cents / 100)}';

  static String htg(double amount) =>
      amount == amount.roundToDouble() ? _htg.format(amount) : _htgExact.format(amount);
}
