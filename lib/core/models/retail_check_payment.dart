import 'dart:convert';
import 'dart:typed_data';

/// Check the cashier recorded while taking a sale.
class RetailCheckPayment {
  final String number;
  final String bank;
  final String payerName;
  final DateTime date;

  /// `data:image/...;base64,...` photo of the check.
  final String imageDataUrl;

  /// True once the bank has cleared the check, or the clerk cleared it at the register.
  final bool cleared;

  /// When [cleared] became true.
  final DateTime? clearedAt;

  const RetailCheckPayment({
    required this.number,
    required this.bank,
    required this.payerName,
    required this.date,
    required this.imageDataUrl,
    this.cleared = false,
    this.clearedAt,
  });

  RetailCheckPayment copyWith({
    bool? cleared,
    DateTime? clearedAt,
  }) {
    return RetailCheckPayment(
      number: number,
      bank: bank,
      payerName: payerName,
      date: date,
      imageDataUrl: imageDataUrl,
      cleared: cleared ?? this.cleared,
      clearedAt: clearedAt ?? this.clearedAt,
    );
  }

  bool get isComplete =>
      number.trim().isNotEmpty &&
      bank.trim().isNotEmpty &&
      payerName.trim().isNotEmpty &&
      imageBytes != null;

  Uint8List? get imageBytes {
    final raw = imageDataUrl.trim();
    if (raw.isEmpty) return null;
    final comma = raw.indexOf(',');
    final payload = comma >= 0 ? raw.substring(comma + 1) : raw;
    try {
      final bytes = base64Decode(payload);
      if (bytes.isEmpty) return null;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  static String dataUrlFor(Uint8List bytes, String mime) {
    final clean = mime.trim().isEmpty ? 'image/jpeg' : mime.trim();
    return 'data:$clean;base64,${base64Encode(bytes)}';
  }

  /// Null until the number, bank, payer, and a photo are all present.
  static RetailCheckPayment? compose({
    required String number,
    required String bank,
    required String payerName,
    required DateTime date,
    required Uint8List? photo,
    required String mime,
    bool cleared = false,
    DateTime? clearedAt,
  }) {
    final n = number.trim();
    final b = bank.trim();
    final payer = payerName.trim();
    if (n.isEmpty ||
        b.isEmpty ||
        payer.isEmpty ||
        photo == null ||
        photo.isEmpty) {
      return null;
    }
    return RetailCheckPayment(
      number: n,
      bank: b,
      payerName: payer,
      date: DateTime(date.year, date.month, date.day),
      imageDataUrl: dataUrlFor(photo, mime),
      cleared: cleared,
      clearedAt: cleared ? (clearedAt ?? DateTime.now()) : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'number': number,
    'bank': bank,
    'payerName': payerName,
    'date': DateTime(date.year, date.month, date.day).toIso8601String(),
    'imageDataUrl': imageDataUrl,
    'cleared': cleared,
    'clearedAt': clearedAt?.toIso8601String(),
  };

  static RetailCheckPayment? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final json = raw.map((key, value) => MapEntry(key.toString(), value));
    final number = json['number']?.toString().trim() ?? '';
    final bank = json['bank']?.toString().trim() ?? '';
    final payerName = json['payerName']?.toString().trim() ?? '';
    final imageDataUrl = json['imageDataUrl']?.toString() ?? '';
    if (number.isEmpty &&
        bank.isEmpty &&
        payerName.isEmpty &&
        imageDataUrl.trim().isEmpty) {
      return null;
    }
    // Checks saved before clearance existed were already treated as paid.
    final cleared = json.containsKey('cleared')
        ? json['cleared'] == true
        : true;
    return RetailCheckPayment(
      number: number,
      bank: bank,
      payerName: payerName,
      date: DateTime.tryParse('${json['date']}') ?? DateTime.now(),
      imageDataUrl: imageDataUrl,
      cleared: cleared,
      clearedAt: DateTime.tryParse('${json['clearedAt']}'),
    );
  }
}
