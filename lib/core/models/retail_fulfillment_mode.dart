/// How a retail order is fulfilled (POS / quotes checkout).
enum RetailFulfillmentMode {
  /// Customer shops and pays in the store (default).
  inStore,

  /// Paid or reserved; customer collects later at the store.
  pickup,

  /// Ship or deliver to an address.
  delivery,
}

extension RetailFulfillmentModeLabel on RetailFulfillmentMode {
  String get label => switch (this) {
        RetailFulfillmentMode.inStore => 'In store',
        RetailFulfillmentMode.pickup => 'Pickup',
        RetailFulfillmentMode.delivery => 'Delivery',
      };
}
