import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether tax is applied on bills. Managed in Settings → Tax & Fees.
final taxEnabledProvider = StateProvider<bool>((ref) => true);

/// Tax rate (percentage) applied on bills when enabled. Managed in Settings → Tax & Fees.
final taxPercentProvider = StateProvider<double>((ref) => 10);

/// Whether gratuity (service charge) is applied on bills. Managed in Settings.
final gratuityEnabledProvider = StateProvider<bool>((ref) => true);

/// Gratuity (service charge) percentage when enabled. Managed in Settings.
final gratuityPercentProvider = StateProvider<double>((ref) => 10);

/// Whether discount can be applied on bills. When false, discount option is hidden/disabled.
final discountAllowedProvider = StateProvider<bool>((ref) => true);

/// Code or password required to apply a discount on a bill. Managed in Settings.
/// Empty = no approval required (for backward compatibility or dev).
final discountApprovalCodeProvider = StateProvider<String>((ref) => 'admin');
