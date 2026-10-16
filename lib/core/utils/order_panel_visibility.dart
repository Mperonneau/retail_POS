import '../mock/mock_hotel_data.dart';
import '../mock/mock_restaurant_data.dart';
import '../widgets/off_premise_order_status_dropdown.dart';

/// Whether an order appears on the active orders screen (restaurant module).
bool orderShowsOnActiveRestaurantOrder(MockOrder o) {
  if (o.orderType == 'takeout' || o.orderType == 'delivery') {
    return normalizeOffPremiseStatus(o.status) != 'complete';
  }
  if ((o.orderType == 'dine_in' || o.orderType == 'reservation') &&
      o.prepaidCapHtg != null) {
    return !o.visitCompleted;
  }
  return !o.isPaid;
}

/// Whether an order appears on the active orders screen (hotel restaurant module).
bool orderShowsOnActiveHotelRestaurantOrder(MockHotelRestaurantOrder o) {
  if (o.orderType == 'takeout' || o.orderType == 'delivery') {
    return normalizeOffPremiseStatus(o.status) != 'complete';
  }
  if ((o.orderType == 'dine_in' || o.orderType == 'reservation') &&
      o.prepaidCapHtg != null) {
    return !o.visitCompleted;
  }
  return !o.isPaid;
}
