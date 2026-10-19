import 'package:flutter_test/flutter_test.dart';
import 'package:retail_pos/core/payments/card_charge_pricing.dart';
import 'package:retail_pos/core/payments/payments_client.dart';

void main() {
  test('payer covers 1.5% + \$1 and the grossed-up Stripe fee', () {
    final priced = CardChargePricing.fromOrderUsdCents(1000);
    expect(priced.platformFeeUsdCents, 115);
    expect(priced.stripeFeeUsdCents, 65);
    expect(priced.combinedFeeUsdCents, 180);
    expect(priced.totalUsdCents, 1180);
    expect(
      priced.orderUsdCents +
          priced.platformFeeUsdCents +
          priced.stripeFeeUsdCents,
      priced.totalUsdCents,
    );
  });

  test('the register knows the payments service without a build flag', () {
    expect(
      PaymentsClient.apiBase,
      'https://retail-pos-payments.onrender.com',
    );
    final client = PaymentsClient();
    expect(client.isConfigured, isTrue);
    client.close();
  });

  test('HTG converts with the shop rate before the fee', () {
    expect(CardChargePricing.htgToUsdCents(1350, 135), 1000);
    expect(CardChargePricing.htgToUsdCents(0, 135), 0);
  });
}
