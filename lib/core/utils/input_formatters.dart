import 'package:flutter/services.dart';

/// Positive decimal entry for money fields: digits and at most one `.`.
///
/// Use [maxDecimalPlaces] to cap fractional digits (e.g. `2` for currency).
final class DecimalTextInputFormatter extends TextInputFormatter {
  final int? maxDecimalPlaces;

  const DecimalTextInputFormatter({this.maxDecimalPlaces});

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final t = newValue.text;
    if (t.isEmpty) return newValue;
    if (!RegExp(r'^\d*\.?\d*$').hasMatch(t)) {
      return oldValue;
    }
    if (maxDecimalPlaces != null) {
      final parts = t.split('.');
      if (parts.length == 2 && parts[1].length > maxDecimalPlaces!) {
        return oldValue;
      }
    }
    return newValue;
  }
}

/// Shared [TextInputFormatter] lists for consistent validation across modules.
abstract final class InputFormatters {
  /// Phone / MonCash-style numbers: digits and common separators only (no letters).
  static List<TextInputFormatter> get phone => [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s\-().]')),
        LengthLimitingTextInputFormatter(32),
      ];

  /// Whole numbers only (quantities, counts, IDs typed as numbers).
  static List<TextInputFormatter> get digitsOnly => [
        FilteringTextInputFormatter.digitsOnly,
      ];

  /// Money and decimal amounts (unlimited fractional digits unless you wrap with [DecimalTextInputFormatter] max).
  static List<TextInputFormatter> get decimalAmount => [
        DecimalTextInputFormatter(),
      ];

  /// Typical currency entry with up to two fractional digits.
  static List<TextInputFormatter> get decimalAmount2 => [
        DecimalTextInputFormatter(maxDecimalPlaces: 2),
      ];

  /// No whitespace in email fields.
  static List<TextInputFormatter> get email => [
        FilteringTextInputFormatter.deny(RegExp(r'\s')),
      ];

  /// Login field that accepts either email or phone (letters, digits, `@`, common punctuation).
  static List<TextInputFormatter> get loginIdentifier => [
        FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9@._+()\s\-]')),
        LengthLimitingTextInputFormatter(128),
      ];

  /// Card number entry: digits and spaces (groups of 4).
  static List<TextInputFormatter> get cardNumber => [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]')),
        LengthLimitingTextInputFormatter(23),
      ];

  /// Expiry `MM/YY`.
  static List<TextInputFormatter> get cardExpiry => [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9/]')),
        LengthLimitingTextInputFormatter(5),
      ];

  /// Card CVV (3–4 digits).
  static List<TextInputFormatter> get cardCvv => [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(4),
      ];
}
