class AppRoutes {
  AppRoutes._();

  // Auth
  static const String splash = '/';
  static const String login = '/login';
  static const String forgotPassword = '/forgot-password';
  static const String register = '/register';
  /// Staff PIN (Tier 2) — requires Tier 1 auth.
  static const String pin = '/pin';
  /// One-time code that authorizes this register.
  static const String pairDevice = '/pair-device';
  /// Codes another register can use to connect.
  static const String devices = '/devices';
  /// Sales saved on this device, waiting for a connection.
  static const String sync = '/sync';

  // Restaurant
  static const String restaurantDashboard = '/restaurant/dashboard';
  static const String restaurantTables = '/restaurant/tables';
  static const String restaurantReservations = '/restaurant/reservations';
  static const String restaurantMenu = '/restaurant/menu';
  static const String restaurantOrders = '/restaurant/orders';
  static const String restaurantOrder = '/restaurant/order';
  static const String restaurantKitchen = '/restaurant/kitchen';
  static const String restaurantKitchenCompleted = '/restaurant/kitchen/completed';
  static const String restaurantBilling = '/restaurant/billing';
  static const String restaurantPayment = '/restaurant/payment';
  static const String restaurantInventory = '/restaurant/inventory';
  static const String restaurantReports = '/restaurant/reports';
  static const String restaurantCashControl = '/restaurant/cash-control';
  static const String restaurantCashReconciliation = '/restaurant/cash-reconciliation';
  static const String restaurantCustomers = '/restaurant/customers';
  static const String restaurantCustomerDetail = '/restaurant/customers/detail';
  static const String restaurantCustomerForm = '/restaurant/customers/form';
  static const String restaurantCollections = '/restaurant/collections';

  // Hotel
  static const String hotelDashboard = '/hotel/dashboard';
  static const String hotelRooms = '/hotel/rooms';
  static const String hotelReservations = '/hotel/reservations';
  static const String hotelCheckIn = '/hotel/check-in';
  static const String hotelCheckOut = '/hotel/check-out';
  static const String hotelHousekeeping = '/hotel/housekeeping';
  static const String hotelRoomService = '/hotel/room-service';
  static const String hotelGuests = '/hotel/guests';
  static const String hotelReports = '/hotel/reports';
  /// Front desk: drawer + MonCash / card / check (hotel module).
  static const String hotelFrontDeskCashControl = '/hotel/cash-control';
  static const String hotelFrontDeskCashReconciliation =
      '/hotel/cash-reconciliation';
  static const String hotelCustomers = '/hotel/customers';
  static const String hotelCustomerDetail = '/hotel/customers/detail';
  static const String hotelCustomerForm = '/hotel/customers/form';

  // Hotel — Restaurant (integrated)
  static const String hotelRestaurantTables    = '/hotel/restaurant/tables';
  static const String hotelRestaurantReservations = '/hotel/restaurant/reservations';
  static const String hotelRestaurantMenu      = '/hotel/restaurant/menu';
  static const String hotelRestaurantOrders    = '/hotel/restaurant/orders';
  static const String hotelRestaurantOrder     = '/hotel/restaurant/order';
  static const String hotelRestaurantKitchen   = '/hotel/restaurant/kitchen';
  static const String hotelRestaurantKitchenCompleted =
      '/hotel/restaurant/kitchen/completed';
  static const String hotelRestaurantBilling   = '/hotel/restaurant/billing';
  static const String hotelRestaurantPayment   = '/hotel/restaurant/payment';
  static const String hotelRestaurantInventory = '/hotel/restaurant/inventory';
  static const String hotelRestaurantReports   = '/hotel/restaurant/reports';
  static const String hotelCashControl         = '/hotel/restaurant/cash-control';
  static const String hotelCashReconciliation  = '/hotel/restaurant/cash-reconciliation';
  static const String hotelRestaurantCustomers = '/hotel/restaurant/customers';
  static const String hotelRestaurantCustomerDetail = '/hotel/restaurant/customers/detail';
  static const String hotelRestaurantCustomerForm = '/hotel/restaurant/customers/form';
  static const String hotelCollections = '/hotel/restaurant/collections';

  // Retail
  static const String retailDashboard = '/retail/dashboard';
  static const String retailPos = '/retail/pos';
  static const String retailProducts = '/retail/products';
  static const String retailInventory = '/retail/inventory';
  static const String retailSuppliers = '/retail/suppliers';
  static const String retailPurchaseOrders = '/retail/purchase-orders';
  static const String retailCustomers = '/retail/customers';
  static const String retailCustomerDetail = '/retail/customers/detail';
  static const String retailCustomerForm = '/retail/customers/form';
  static const String retailCollections = '/retail/collections';
  static const String retailSalesHistory = '/retail/sales-history';
  static const String retailCashier = '/retail/cashier';
  static const String retailReports = '/retail/reports';
  static const String retailCashControl = '/retail/cash-control';
  static const String retailCashReconciliation = '/retail/cash-reconciliation';

  // Paylinks (all modules)
  static const String restaurantPayLinks = '/restaurant/paylinks';
  static const String hotelPayLinks = '/hotel/paylinks';
  static const String retailPayLinks = '/retail/paylinks';

  // Order History (all modules)
  static const String restaurantOrderHistory = '/restaurant/order-history';
  static const String hotelOrderHistory = '/hotel/order-history';
  static const String retailOrderHistory = '/retail/order-history';
  static const String retailQuotes = '/retail/quotes';

  // Timeclock (admin/manager) — one per module shell
  static const String restaurantTimeclock = '/restaurant/timeclock';
  static const String hotelTimeclock = '/hotel/timeclock';
  static const String retailTimeclock = '/retail/timeclock';

  // Shared — one path per shell so GoRouter does not match the wrong AppShell.
  static const String restaurantSettings = '/restaurant/settings';
  static const String hotelSettings = '/hotel/settings';
  static const String retailSettings = '/retail/settings';
  static const String reports = '/reports';
  static const String paymentFlow = '/payment';
}
