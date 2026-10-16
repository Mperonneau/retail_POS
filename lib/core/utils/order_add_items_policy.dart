/// Whether staff may add line items to an open bill.
///
/// Dine-in / reservation tabs with a **prepaid amount** stay editable until the
/// visit is marked complete (cap is still enforced in [addBatch]).
bool orderAllowsAddingItems({
  required bool isPaid,
  required bool visitCompleted,
  required String orderType,
  required double? prepaidCapHtg,
}) {
  if (visitCompleted) return false;
  final prepaidVisitOpen = prepaidCapHtg != null &&
      prepaidCapHtg > 0 &&
      (orderType == 'dine_in' || orderType == 'reservation');
  if (prepaidVisitOpen) return true;
  return !isPaid;
}
