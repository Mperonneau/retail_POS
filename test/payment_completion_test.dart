import 'package:flutter_test/flutter_test.dart';
import 'package:retail_pos/core/models/retail_fulfillment_mode.dart';
import 'package:retail_pos/core/models/retail_order.dart';

void main() {
  test('paid retrait is terminé; en magasin and livraison stay open', () {
    expect(
      statusAfterFullPayment(RetailFulfillmentMode.pickup),
      RetailOrderStatus.completed,
    );
    expect(
      statusAfterFullPayment(RetailFulfillmentMode.inStore),
      RetailOrderStatus.paid,
    );
    expect(
      statusAfterFullPayment(RetailFulfillmentMode.delivery),
      RetailOrderStatus.paid,
    );
  });
}
