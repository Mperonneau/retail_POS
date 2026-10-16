import 'dart:math' as math;

/// Matches default bill math in [OrderBillDrawer] (10% service + 10% tax on subtotal).
/// Used for prepaid cap checks before adding items.
double estimatedBillTotalHtgFromSubtotal(
  double subtotalHtg, {
  bool includeServiceCharge = true,
  double servicePercent = 10,
  double taxPercent = 10,
  double discountPercent = 0,
}) {
  final discount = subtotalHtg * (discountPercent / 100);
  final afterDiscount = math.max(0.0, subtotalHtg - discount);
  final service =
      includeServiceCharge ? afterDiscount * (servicePercent / 100) : 0.0;
  final tax = afterDiscount * (taxPercent / 100);
  return afterDiscount + service + tax;
}

/// Room left under [prepaidCapHtg] after applying the same estimated bill rules
/// as [estimatedBillTotalHtgFromSubtotal] to [itemsSubtotalHtg].
double prepaidHeadroomHtgFromSubtotal({
  required double prepaidCapHtg,
  required double itemsSubtotalHtg,
  bool includeServiceCharge = true,
  double servicePercent = 10,
  double taxPercent = 10,
  double discountPercent = 0,
}) {
  final est = estimatedBillTotalHtgFromSubtotal(
    itemsSubtotalHtg,
    includeServiceCharge: includeServiceCharge,
    servicePercent: servicePercent,
    taxPercent: taxPercent,
    discountPercent: discountPercent,
  );
  return math.max(0.0, prepaidCapHtg - est);
}
