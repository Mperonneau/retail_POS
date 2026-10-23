import 'customer.dart';
import 'retail_order.dart';

/// Total the cashier confirmed for a check sale.
double checkSaleTotal(RetailOrder order) {
  if (order.amountPaidHtg != null || order.balanceDueHtg != null) {
    return (order.amountPaidHtg ?? 0) + (order.balanceDueHtg ?? 0);
  }
  final face = order.checkPayment?.amountHtg;
  if (face != null && face > 0.009) return face;
  return order.totalHtg;
}

/// Remainder reserved on a client while their check has not cleared.
double reservedCheckCredit({
  required Iterable<RetailOrder> orders,
  required String customerId,
  String? exceptOrderId,
}) {
  var sum = 0.0;
  for (final order in orders) {
    if (order.id == exceptOrderId) continue;
    final check = order.checkPayment;
    if (check == null || check.cleared || check.refused || check.creditPosted) {
      continue;
    }
    if (check.creditCustomerId != customerId) continue;
    sum += order.unpaidBalanceHtg;
  }
  return sum;
}

/// Why this remainder cannot be reserved or posted. Null means it can.
String? checkCreditBlockReason({
  required Customer? customer,
  required double remainder,
  required Iterable<RetailOrder> orders,
  required double postedBalance,
  String? exceptOrderId,
}) {
  if (remainder <= 0.009) return null;
  if (customer == null) return 'Choisissez le client qui portera le solde.';
  if (customer.isCreditBlocked) return '${customer.name} est bloqué.';
  final limit = customer.creditLimitHtg;
  if (limit == null) return null;
  final reserved = reservedCheckCredit(
    orders: orders,
    customerId: customer.id,
    exceptOrderId: exceptOrderId,
  );
  if (postedBalance + reserved + remainder > limit + 0.009) {
    return 'La limite de crédit sera dépassée.';
  }
  return null;
}
