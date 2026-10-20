import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Request id from a vitrine receipt link, once the cashier scans its QR code.
final pendingReceiptScanProvider = StateProvider<String?>((ref) => null);

final _requestInLink = RegExp(r'(?:^|/)r/([A-Za-z0-9_-]{8,})(?:[/?#]|$)');

/// The public receipt URL is what the QR encodes. Anything else stays a product code.
String? storefrontRequestIdFromScan(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  return _requestInLink.firstMatch(text)?.group(1);
}
