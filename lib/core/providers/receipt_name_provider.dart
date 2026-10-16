import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Optional name for the receipt, set from billing and used when printing/sending receipt.
final receiptNameProvider = StateProvider<String>((ref) => '');
