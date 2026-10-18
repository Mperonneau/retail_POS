/// What the payer is charged on a Stripe Checkout (card or payment link).
///
/// The shop keeps the order amount in dollars. The payer covers:
/// - the shop fee: 1.5% of the order plus $1
/// - Stripe's card fee, estimated at 2.9% + $0.30 and grossed up so the
///   net after Stripe still equals the order plus the shop fee.
class CardChargePricing {
  const CardChargePricing({
    required this.orderUsdCents,
    required this.platformFeeUsdCents,
    required this.stripeFeeUsdCents,
    required this.totalUsdCents,
  });

  /// Shop fee: 1.5% (150 basis points).
  static const int platformPercentBp = 150;

  /// Shop fee: $1, in cents.
  static const int platformFixedUsdCents = 100;

  /// Stripe card estimate: 2.9%.
  static const int stripePercentBp = 290;

  /// Stripe card estimate: $0.30.
  static const int stripeFixedUsdCents = 30;

  final int orderUsdCents;
  final int platformFeeUsdCents;
  final int stripeFeeUsdCents;
  final int totalUsdCents;

  double get orderUsd => orderUsdCents / 100;
  double get platformFeeUsd => platformFeeUsdCents / 100;
  double get stripeFeeUsd => stripeFeeUsdCents / 100;
  double get totalUsd => totalUsdCents / 100;

  static CardChargePricing fromOrderUsdCents(int orderUsdCents) {
    final order = orderUsdCents < 0 ? 0 : orderUsdCents;
    final percent = (order * platformPercentBp + 5000) ~/ 10000;
    final platform = percent + platformFixedUsdCents;
    final desired = order + platform;
    final numerator = desired + stripeFixedUsdCents;
    const denomBp = 10000 - stripePercentBp;
    final total = (numerator * 10000 + denomBp - 1) ~/ denomBp;
    final stripeFee = total - desired;
    return CardChargePricing(
      orderUsdCents: order,
      platformFeeUsdCents: platform,
      stripeFeeUsdCents: stripeFee < 0 ? 0 : stripeFee,
      totalUsdCents: total,
    );
  }

  /// [localPerUsd] is how many local units buy one dollar (HTG per USD).
  static int htgToUsdCents(double amountLocal, double localPerUsd) {
    if (amountLocal <= 0 || localPerUsd <= 0) return 0;
    return (amountLocal / localPerUsd * 100).round();
  }
}
