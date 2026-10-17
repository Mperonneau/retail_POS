import '../mock/mock_restaurant_data.dart';

/// Beverage category label used in the demo catalog and menu admin.
const String menuDrinksCategory = 'Boissons';

enum MenuItemUnavailabilityReason {
  none,
  manuallyOutOfStock,
  inventoryNotLinked,
  inventoryDepleted,
  inventoryInsufficient,
}

/// Result of whether a menu line can be added to an order (quantity bump of [delta]).
class MenuItemOrderability {
  final bool isOrderable;
  final MenuItemUnavailabilityReason reason;
  /// On-hand units when blocked by inventory (for messaging).
  final double? inventoryOnHand;

  const MenuItemOrderability._({
    required this.isOrderable,
    required this.reason,
    this.inventoryOnHand,
  });

  const MenuItemOrderability.orderable()
      : isOrderable = true,
        reason = MenuItemUnavailabilityReason.none,
        inventoryOnHand = null;

  /// Food: manual flag only. Drinks: manual first, then inventory vs cart qty.
  factory MenuItemOrderability.evaluate({
    required MockMenuItem item,
    required List<MockInventoryItem> inventory,
    required int quantityAlreadyInCart,
    int delta = 1,
  }) {
    if (!item.available) {
      return const MenuItemOrderability._(
        isOrderable: false,
        reason: MenuItemUnavailabilityReason.manuallyOutOfStock,
      );
    }

    if (item.category != menuDrinksCategory) {
      return const MenuItemOrderability.orderable();
    }

    final id = item.inventoryItemId;
    if (id == null) {
      return const MenuItemOrderability._(
        isOrderable: false,
        reason: MenuItemUnavailabilityReason.inventoryNotLinked,
      );
    }

    MockInventoryItem? inv;
    for (final i in inventory) {
      if (i.id == id) {
        inv = i;
        break;
      }
    }
    if (inv == null) {
      return const MenuItemOrderability._(
        isOrderable: false,
        reason: MenuItemUnavailabilityReason.inventoryNotLinked,
      );
    }

    if (inv.quantity <= 0) {
      return MenuItemOrderability._(
        isOrderable: false,
        reason: MenuItemUnavailabilityReason.inventoryDepleted,
        inventoryOnHand: inv.quantity,
      );
    }

    final needed = quantityAlreadyInCart + delta;
    if (inv.quantity < needed) {
      return MenuItemOrderability._(
        isOrderable: false,
        reason: MenuItemUnavailabilityReason.inventoryInsufficient,
        inventoryOnHand: inv.quantity,
      );
    }

    return const MenuItemOrderability.orderable();
  }

  /// Short copy for staff-facing modal dialogs (POS users are employees).
  String staffDialogMessage() {
    switch (reason) {
      case MenuItemUnavailabilityReason.none:
        return '';
      case MenuItemUnavailabilityReason.manuallyOutOfStock:
        return 'This item is marked as out of stock. If you believe this is a mistake, contact an admin.';
      case MenuItemUnavailabilityReason.inventoryNotLinked:
        return 'Cette boisson n\'est pas liée au stock. Contactez un admin.';
      case MenuItemUnavailabilityReason.inventoryDepleted:
        return 'No stock left in inventory for this item. Contact an admin or update inventory.';
      case MenuItemUnavailabilityReason.inventoryInsufficient:
        final n = inventoryOnHand ?? 0;
        return 'Stock insuffisant pour cette quantité (seulement ${_formatStockQty(n)} disponible). Réduisez la quantité ou contactez un admin.';
    }
  }

  /// Short label for tiles / chips (no item name).
  String get shortStatusLabel {
    switch (reason) {
      case MenuItemUnavailabilityReason.none:
        return '';
      case MenuItemUnavailabilityReason.manuallyOutOfStock:
        return 'Rupture de stock';
      case MenuItemUnavailabilityReason.inventoryNotLinked:
        return 'Non lié';
      case MenuItemUnavailabilityReason.inventoryDepleted:
        return 'Rupture de stock';
      case MenuItemUnavailabilityReason.inventoryInsufficient:
        return 'Stock insuffisant';
    }
  }
}

String _formatStockQty(double n) {
  if (n <= 0) return '0';
  final r = n.round();
  if ((n - r).abs() < 1e-6) return r.toString();
  return n.toStringAsFixed(1);
}
