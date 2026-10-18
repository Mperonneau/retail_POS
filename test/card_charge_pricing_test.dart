import 'package:flutter_test/flutter_test.dart';
import 'package:retail_pos/core/payments/card_charge_pricing.dart';

void main() {
  test('payer covers 1.5% + \$1 and the grossed-up Stripe fee', () {
    final priced = CardChargePricing.fromOrderUsdCents(1000);
    expect(priced.platformFeeUsdCents, 115);
    expect(priced.stripeFeeUsdCents, 65);
    expect(priced.totalUsdCents, 1180);
    expect(
      priced.orderUsdCents +
          priced.platformFeeUsdCents +
          priced.stripeFeeUsdCents,
      priced.totalUsdCents,
    );
  });

  test('HTG converts with the shop rate before the fee', () {
    expect(CardChargePricing.htgToUsdCents(1350, 135), 1000);
    expect(CardChargePricing.htgToUsdCents(0, 135), 0);
  });
}
