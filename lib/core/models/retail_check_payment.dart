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

  /// Person who compensated the check.
  final String? clearedBy;

  /// Face value. Null on checks saved before a short check was possible.
  final double? amountHtg;

  /// Client who will carry the remainder. Empty when the check covers the sale.
  final String? creditCustomerId;

  /// True once the remainder was posted on the client account.
  final bool creditPosted;

  /// True when the check was refused and will not be collected.
  final bool refused;

  const RetailCheckPayment({
    required this.number,
    required this.bank,
    required this.payerName,
    required this.date,
    required this.imageDataUrl,
    this.amountHtg,
    this.creditCustomerId,
    this.creditPosted = false,
    this.cleared = false,
    this.refused = false,
    this.clearedAt,
    this.clearedBy,
  });

  /// Status line, including who compensated the check when that name is known.
  String get clearanceLabel {
    if (refused) return 'Chèque refusé';
    if (!cleared) return 'En attente de compensation';
    final name = clearedBy?.trim() ?? '';
    if (name.isEmpty) return 'Chèque compensé';
    return 'Chèque compensé par : $name';
  }

  static const Object _keep = Object();

  RetailCheckPayment copyWith({
    String? number,
    String? bank,
    String? payerName,
    DateTime? date,
    String? imageDataUrl,
    Object? amountHtg = _keep,
    Object? creditCustomerId = _keep,
    bool? creditPosted,
    bool? cleared,
    bool? refused,
    Object? clearedAt = _keep,
    Object? clearedBy = _keep,
  }) {
    return RetailCheckPayment(
      number: number ?? this.number,
      bank: bank ?? this.bank,
      payerName: payerName ?? this.payerName,
      date: date ?? this.date,
      imageDataUrl: imageDataUrl ?? this.imageDataUrl,
      amountHtg: amountHtg == _keep ? this.amountHtg : amountHtg as double?,
      creditCustomerId: creditCustomerId == _keep
          ? this.creditCustomerId
          : creditCustomerId as String?,
      creditPosted: creditPosted ?? this.creditPosted,
      cleared: cleared ?? this.cleared,
      refused: refused ?? this.refused,
      clearedAt: clearedAt == _keep ? this.clearedAt : clearedAt as DateTime?,
      clearedBy: clearedBy == _keep ? this.clearedBy : clearedBy as String?,
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
    bool refused = false,
    bool creditPosted = false,
    double? amountHtg,
    String? creditCustomerId,
    DateTime? clearedAt,
    String? clearedBy,
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
      amountHtg: amountHtg,
      creditCustomerId: _cleanName(creditCustomerId),
      creditPosted: creditPosted,
      cleared: cleared,
      refused: refused,
      clearedAt: cleared ? (clearedAt ?? DateTime.now()) : null,
      clearedBy: cleared ? _cleanName(clearedBy) : null,
    );
  }

  static String? _cleanName(String? raw) {
    final name = raw?.trim() ?? '';
    return name.isEmpty ? null : name;
  }

  Map<String, dynamic> toJson() => {
    'number': number,
    'bank': bank,
    'payerName': payerName,
    'date': DateTime(date.year, date.month, date.day).toIso8601String(),
    'imageDataUrl': imageDataUrl,
    'amountHtg': amountHtg,
    'creditCustomerId': creditCustomerId,
    'creditPosted': creditPosted,
    'cleared': cleared,
    'refused': refused,
    'clearedAt': clearedAt?.toIso8601String(),
    'clearedBy': clearedBy,
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
    final amount = json['amountHtg'];
    return RetailCheckPayment(
      number: number,
      bank: bank,
      payerName: payerName,
      date: DateTime.tryParse('${json['date']}') ?? DateTime.now(),
      imageDataUrl: imageDataUrl,
      amountHtg: amount is num ? amount.toDouble() : double.tryParse('$amount'),
      creditCustomerId: _cleanName(json['creditCustomerId']?.toString()),
      creditPosted: json['creditPosted'] == true,
      cleared: cleared,
      refused: json['refused'] == true,
      clearedAt: DateTime.tryParse('${json['clearedAt']}'),
      clearedBy: _cleanName(json['clearedBy']?.toString()),
    );
  }
}
