import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/order_add_items_policy.dart';
import '../utils/order_bill_estimate.dart';

class MockTable {
  final int id;
  final String name;
  final int capacity;
  final String status; // available, occupied, bill_requested, reserved
  final String? occupiedSince;
  final String? guestCount;
  final int? activeOrderId;

  const MockTable({
    required this.id,
    required this.name,
    required this.capacity,
    required this.status,
    this.occupiedSince,
    this.guestCount,
    this.activeOrderId,
  });

  MockTable copyWith({
    int? id,
    String? name,
    int? capacity,
    String? status,
    Object? occupiedSince = _sentinel,
    Object? guestCount = _sentinel,
    Object? activeOrderId = _sentinel,
  }) {
    return MockTable(
      id: id ?? this.id,
      name: name ?? this.name,
      capacity: capacity ?? this.capacity,
      status: status ?? this.status,
      occupiedSince: occupiedSince == _sentinel ? this.occupiedSince : occupiedSince as String?,
      guestCount: guestCount == _sentinel ? this.guestCount : guestCount as String?,
      activeOrderId: activeOrderId == _sentinel ? this.activeOrderId : activeOrderId as int?,
    );
  }
}

class MockMenuItem {
  final int id;
  final String name;
  final String category;
  final double priceHtg;
  final double priceUsd;
  /// Manual availability (kitchen / floor). When `false`, item cannot be sold
  /// even if inventory still shows stock (used for all categories).
  final bool available;
  final String? description;
  /// For [category] == `'Drinks'`, links to [MockInventoryItem.id] for stock checks.
  final int? inventoryItemId;

  const MockMenuItem({
    required this.id,
    required this.name,
    required this.category,
    required this.priceHtg,
    required this.priceUsd,
    this.available = true,
    this.description,
    this.inventoryItemId,
  });

  MockMenuItem copyWith({
    int? id,
    String? name,
    String? category,
    double? priceHtg,
    double? priceUsd,
    bool? available,
    Object? description = _sentinel,
    Object? inventoryItemId = _sentinel,
  }) {
    return MockMenuItem(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      priceHtg: priceHtg ?? this.priceHtg,
      priceUsd: priceUsd ?? this.priceUsd,
      available: available ?? this.available,
      description: description == _sentinel ? this.description : description as String?,
      inventoryItemId: inventoryItemId == _sentinel
          ? this.inventoryItemId
          : inventoryItemId as int?,
    );
  }
}

/// A single kitchen dispatch batch. Batch 1 = original order; 2+ = add-ons.
class MockKitchenBatch {
  final int batchNumber;
  final List<MockOrderItem> items;
  final String status; // pending, in_progress, ready, complete, delivered
  final DateTime placedAt;
  /// Set when status becomes complete/delivered (used for completed-kitchen history & reverse rules).
  final DateTime? kitchenCompletedAt;

  bool get isAddon => batchNumber > 1;

  MockKitchenBatch({
    required this.batchNumber,
    required this.items,
    required this.status,
    required this.placedAt,
    this.kitchenCompletedAt,
  });

  MockKitchenBatch copyWith({
    int? batchNumber,
    List<MockOrderItem>? items,
    String? status,
    DateTime? placedAt,
    Object? kitchenCompletedAt = _sentinel,
  }) =>
      MockKitchenBatch(
        batchNumber: batchNumber ?? this.batchNumber,
        items: items ?? this.items,
        status: status ?? this.status,
        placedAt: placedAt ?? this.placedAt,
        kitchenCompletedAt: kitchenCompletedAt == _sentinel
            ? this.kitchenCompletedAt
            : kitchenCompletedAt as DateTime?,
      );
}

class MockOrder {
  final int id;
  final int tableId;
  final String tableName;
  final List<MockOrderItem> items;
  final DateTime placedAt;
  /// Kitchen/lifecycle status: pending, in_progress, ready, complete, delivered.
  /// 'preparing' is a legacy alias for 'in_progress' — normalised at render time.
  final String status;
  final String waiter;
  /// Order type: dine_in, takeout, delivery, reservation
  final String orderType;
  final bool isPaid;
  final String? customerName;
  final String? customerPhone;
  final String? deliveryAddress;
  /// When [orderType] == reservation — guest/party context from activation.
  final String? reservationGuestName;
  final int? reservationPartySize;
  final String? reservationNotes;
  /// Kitchen dispatch batches. Populated on first place-order; add-ons append.
  final List<MockKitchenBatch> kitchenBatches;
  /// True after a payment link has been sent for this order.
  final bool paymentLinkSent;
  /// True when kitchen should wait for remote payment before preparing.
  final bool kitchenHeldForPayment;
  /// Recipient info for the sent payment link.
  final String? paymentLinkRecipient;
  /// Channel used: whatsApp, email, sms.
  final String? paymentLinkChannel;
  /// When the link was sent.
  final DateTime? paymentLinkSentAt;
  /// Gateway / customer payment captured; staff must still confirm [isPaid] when a link was sent.
  final bool paymentLinkRemotePaid;
  /// Prepaid spending cap (HTG) for dine-in / reservation payment links; null = no cap.
  final double? prepaidCapHtg;
  /// Staff closed a prepaid table visit — removes order from active list.
  final bool visitCompleted;
  /// Store credit applied to this bill (HTG), for receipt / audit.
  final double customerCreditAppliedHtg;

  // ── Merge fields ────────────────────────────────────────────────────────────
  /// Snapshot of the absorbed order (table that was merged into this one).
  final MergedTableSnapshot? mergedSnapshot;

  MockOrder({
    required this.id,
    required this.tableId,
    required this.tableName,
    required this.items,
    required this.placedAt,
    required this.status,
    required this.waiter,
    this.orderType = 'dine_in',
    this.isPaid = false,
    this.customerName,
    this.customerPhone,
    this.deliveryAddress,
    this.reservationGuestName,
    this.reservationPartySize,
    this.reservationNotes,
    this.paymentLinkSent = false,
    this.kitchenHeldForPayment = false,
    this.paymentLinkRecipient,
    this.paymentLinkChannel,
    this.paymentLinkSentAt,
    this.paymentLinkRemotePaid = false,
    this.prepaidCapHtg,
    this.visitCompleted = false,
    this.customerCreditAppliedHtg = 0,
    this.mergedSnapshot,
    List<MockKitchenBatch>? kitchenBatches,
  }) : kitchenBatches = kitchenBatches ??
            [
              MockKitchenBatch(
                batchNumber: 1,
                items: items,
                status: status,
                placedAt: placedAt,
              )
            ];

  double get totalHtg => items.fold(0, (sum, i) => sum + (i.priceHtg * i.quantity));
  double get totalUsd => items.fold(0, (sum, i) => sum + (i.priceUsd * i.quantity));

  /// All items on this order. `items` is always kept up-to-date as the
  /// authoritative flat list — drinks are merged here directly, food items
  /// are also appended here when a new kitchen batch is created.
  List<MockOrderItem> get allItems => items;

  double get allItemsTotalHtg =>
      items.fold(0, (s, i) => s + i.priceHtg * i.quantity);

  MockOrder copyWith({
    int? id,
    int? tableId,
    String? tableName,
    List<MockOrderItem>? items,
    DateTime? placedAt,
    String? status,
    String? waiter,
    String? orderType,
    bool? isPaid,
    Object? customerName = _sentinel,
    Object? customerPhone = _sentinel,
    Object? deliveryAddress = _sentinel,
    Object? reservationGuestName = _sentinel,
    Object? reservationPartySize = _sentinel,
    Object? reservationNotes = _sentinel,
    List<MockKitchenBatch>? kitchenBatches,
    bool? paymentLinkSent,
    bool? kitchenHeldForPayment,
    Object? paymentLinkRecipient = _sentinel,
    Object? paymentLinkChannel = _sentinel,
    Object? paymentLinkSentAt = _sentinel,
    bool? paymentLinkRemotePaid,
    Object? prepaidCapHtg = _sentinel,
    bool? visitCompleted,
    double? customerCreditAppliedHtg,
    Object? mergedSnapshot = _sentinel,
  }) =>
      MockOrder(
        id: id ?? this.id,
        tableId: tableId ?? this.tableId,
        tableName: tableName ?? this.tableName,
        items: items ?? this.items,
        placedAt: placedAt ?? this.placedAt,
        status: status ?? this.status,
        waiter: waiter ?? this.waiter,
        orderType: orderType ?? this.orderType,
        isPaid: isPaid ?? this.isPaid,
        customerName: customerName == _sentinel ? this.customerName : customerName as String?,
        customerPhone: customerPhone == _sentinel ? this.customerPhone : customerPhone as String?,
        deliveryAddress: deliveryAddress == _sentinel ? this.deliveryAddress : deliveryAddress as String?,
        reservationGuestName: reservationGuestName == _sentinel
            ? this.reservationGuestName
            : reservationGuestName as String?,
        reservationPartySize: reservationPartySize == _sentinel
            ? this.reservationPartySize
            : reservationPartySize as int?,
        reservationNotes: reservationNotes == _sentinel
            ? this.reservationNotes
            : reservationNotes as String?,
        kitchenBatches: kitchenBatches ?? this.kitchenBatches,
        paymentLinkSent: paymentLinkSent ?? this.paymentLinkSent,
        kitchenHeldForPayment: kitchenHeldForPayment ?? this.kitchenHeldForPayment,
        paymentLinkRecipient: paymentLinkRecipient == _sentinel
            ? this.paymentLinkRecipient
            : paymentLinkRecipient as String?,
        paymentLinkChannel: paymentLinkChannel == _sentinel
            ? this.paymentLinkChannel
            : paymentLinkChannel as String?,
        paymentLinkSentAt: paymentLinkSentAt == _sentinel
            ? this.paymentLinkSentAt
            : paymentLinkSentAt as DateTime?,
        paymentLinkRemotePaid:
            paymentLinkRemotePaid ?? this.paymentLinkRemotePaid,
        prepaidCapHtg: prepaidCapHtg == _sentinel
            ? this.prepaidCapHtg
            : prepaidCapHtg as double?,
        visitCompleted: visitCompleted ?? this.visitCompleted,
        customerCreditAppliedHtg:
            customerCreditAppliedHtg ?? this.customerCreditAppliedHtg,
        mergedSnapshot: mergedSnapshot == _sentinel
            ? this.mergedSnapshot
            : mergedSnapshot as MergedTableSnapshot?,
      );

  /// True when this order absorbed another table via merge.
  bool get hasMerge => mergedSnapshot != null;
}

extension MockOrderAddItemsPolicy on MockOrder {
  bool get allowsAddingItems => orderAllowsAddingItems(
        isPaid: isPaid,
        visitCompleted: visitCompleted,
        orderType: orderType,
        prepaidCapHtg: prepaidCapHtg,
      );
}

class MockOrderItem {
  final String name;
  final int quantity;
  final double priceHtg;
  final double priceUsd;
  final String? note;
  /// Menu category (e.g. 'Drinks', 'Mains'). Used to decide whether the item
  /// goes to a kitchen batch (food) or is merged directly (drinks).
  final String category;
  /// Custom catering / off-menu line (not from catalog).
  final bool isCustom;
  /// When [isCustom]: if true, item appears on kitchen tickets.
  final bool sendToKitchen;
  /// When [isCustom]: pending | ready | served (managed in order UI).
  final String customStatus;

  const MockOrderItem({
    required this.name,
    required this.quantity,
    required this.priceHtg,
    required this.priceUsd,
    this.note,
    this.category = 'Mains',
    this.isCustom = false,
    this.sendToKitchen = false,
    this.customStatus = 'pending',
  });

  bool get isDrink => category == 'Drinks';

  MockOrderItem copyWith({
    String? name,
    int? quantity,
    double? priceHtg,
    double? priceUsd,
    Object? note = _sentinel,
    String? category,
    bool? isCustom,
    bool? sendToKitchen,
    String? customStatus,
  }) =>
      MockOrderItem(
        name: name ?? this.name,
        quantity: quantity ?? this.quantity,
        priceHtg: priceHtg ?? this.priceHtg,
        priceUsd: priceUsd ?? this.priceUsd,
        note: note == _sentinel ? this.note : note as String?,
        category: category ?? this.category,
        isCustom: isCustom ?? this.isCustom,
        sendToKitchen: sendToKitchen ?? this.sendToKitchen,
        customStatus: customStatus ?? this.customStatus,
      );
}

/// Food or Drink — items are separated into tabs, never mixed.
enum InventoryItemType { food, drink }

class MockInventoryItem {
  final int id;
  final String name;
  final String unit;
  final double quantity;
  final double minThreshold;
  final String category;
  final InventoryItemType type;

  const MockInventoryItem({
    required this.id,
    required this.name,
    required this.unit,
    required this.quantity,
    required this.minThreshold,
    required this.category,
    required this.type,
  });

  bool get isLowStock => quantity <= minThreshold;

  MockInventoryItem copyWith({
    int? id,
    String? name,
    String? unit,
    double? quantity,
    double? minThreshold,
    String? category,
    InventoryItemType? type,
  }) {
    return MockInventoryItem(
      id: id ?? this.id,
      name: name ?? this.name,
      unit: unit ?? this.unit,
      quantity: quantity ?? this.quantity,
      minThreshold: minThreshold ?? this.minThreshold,
      category: category ?? this.category,
      type: type ?? this.type,
    );
  }
}

/// Transaction type for inventory ledger (add/use/adjust).
enum InventoryTransactionType { add, use, adjust }

class MockInventoryTransaction {
  final int id;
  final int itemId;
  final DateTime date;
  final InventoryTransactionType type;
  final double quantity;
  final String? note;

  const MockInventoryTransaction({
    required this.id,
    required this.itemId,
    required this.date,
    required this.type,
    required this.quantity,
    this.note,
  });
}

/// Daily summary for ledger view: total add, total use, balance for that day.
class InventoryDaySummary {
  final DateTime date;
  final double totalAdd;
  final double totalUse;
  final double balance;

  const InventoryDaySummary({
    required this.date,
    required this.totalAdd,
    required this.totalUse,
    required this.balance,
  });
}

/// Predefined unit options for inventory items.
const inventoryUnitOptions = [
  'KG',
  'LB',
  'L',
  'Bottle',
  'Sachet',
  'pcs',
  'unit',
  'pack',
  'box',
  'can',
];

// ──────────────── MOCK DATA ────────────────

final _mockTablesSeed = [
  MockTable(id: 1, name: 'Table 1', capacity: 2, status: 'available'),
  MockTable(id: 2, name: 'Table 2', capacity: 4, status: 'occupied', occupiedSince: '12:30', guestCount: '3', activeOrderId: 101),
  MockTable(id: 3, name: 'Table 3', capacity: 4, status: 'occupied', occupiedSince: '11:45', guestCount: '4', activeOrderId: 102),
  MockTable(id: 4, name: 'Table 4', capacity: 6, status: 'bill_requested', occupiedSince: '11:00', guestCount: '6', activeOrderId: 103),
  MockTable(id: 5, name: 'Table 5', capacity: 2, status: 'available'),
  MockTable(id: 6, name: 'Terrace A', capacity: 4, status: 'reserved'),
  MockTable(id: 7, name: 'Terrace B', capacity: 4, status: 'occupied', occupiedSince: '13:15', guestCount: '2', activeOrderId: 104),
  MockTable(id: 8, name: 'VIP Room', capacity: 8, status: 'available'),
  MockTable(id: 9, name: 'Table 6', capacity: 4, status: 'occupied', occupiedSince: '12:00', guestCount: '4', activeOrderId: 105),
  MockTable(id: 10, name: 'Table 7', capacity: 6, status: 'available'),
  MockTable(id: 11, name: 'Bar 1', capacity: 2, status: 'occupied', occupiedSince: '13:45', guestCount: '1', activeOrderId: 106),
  MockTable(id: 12, name: 'Bar 2', capacity: 2, status: 'available'),
];

final _mockMenuSeed = [
  // Starters
  MockMenuItem(id: 1, name: 'Accra (Malanga Fritters)', category: 'Starters', priceHtg: 350, priceUsd: 3.50, description: 'Crispy taro fritters with pikliz dipping sauce'),
  MockMenuItem(id: 2, name: 'Bouillon de Crabe', category: 'Starters', priceHtg: 650, priceUsd: 6.50, description: 'Crab soup with root vegetables'),
  MockMenuItem(id: 3, name: 'Salade de Chou', category: 'Starters', priceHtg: 250, priceUsd: 2.50),
  // Mains
  MockMenuItem(id: 4, name: 'Griot avec Riz Collé', category: 'Mains', priceHtg: 1200, priceUsd: 12.00, description: 'Fried pork with peas & rice and pikliz'),
  MockMenuItem(id: 5, name: 'Poulet en Sauce', category: 'Mains', priceHtg: 950, priceUsd: 9.50, description: 'Chicken in Haitian creole sauce'),
  MockMenuItem(id: 6, name: 'Lanbi (Conch)', category: 'Mains', priceHtg: 1800, priceUsd: 18.00, description: 'Stewed conch with vegetables'),
  MockMenuItem(id: 7, name: 'Poisson Gros Sel', category: 'Mains', priceHtg: 1400, priceUsd: 14.00, description: 'Whole fried fish with coarse salt'),
  MockMenuItem(id: 8, name: 'Tassot de Cabrit', category: 'Mains', priceHtg: 1600, priceUsd: 16.00, description: 'Fried goat with banane pesée'),
  // Sides
  MockMenuItem(id: 9, name: 'Bannann Peze (Fried Plantain)', category: 'Sides', priceHtg: 200, priceUsd: 2.00),
  MockMenuItem(id: 10, name: 'Riz Collé ak Pwa', category: 'Sides', priceHtg: 250, priceUsd: 2.50),
  MockMenuItem(id: 11, name: 'Mayi Moulen', category: 'Sides', priceHtg: 200, priceUsd: 2.00, available: false),
  MockMenuItem(id: 12, name: 'Pikliz', category: 'Sides', priceHtg: 100, priceUsd: 1.00),
  // Drinks (inventoryItemId required for POS stock rules)
  MockMenuItem(id: 13, name: 'Prestige Beer', category: 'Drinks', priceHtg: 300, priceUsd: 3.00, inventoryItemId: 7),
  MockMenuItem(id: 14, name: 'Rhum Barbancourt', category: 'Drinks', priceHtg: 450, priceUsd: 4.50, inventoryItemId: 8),
  MockMenuItem(id: 15, name: 'Akasan (Corn Drink)', category: 'Drinks', priceHtg: 150, priceUsd: 1.50, inventoryItemId: 11),
  MockMenuItem(id: 16, name: 'Jus de Corossol', category: 'Drinks', priceHtg: 200, priceUsd: 2.00, inventoryItemId: 12),
  MockMenuItem(id: 17, name: 'Café Haïtien', category: 'Drinks', priceHtg: 180, priceUsd: 1.80, inventoryItemId: 13),
  MockMenuItem(id: 18, name: 'Eau Minérale', category: 'Drinks', priceHtg: 100, priceUsd: 1.00, inventoryItemId: 14),
  // Desserts
  MockMenuItem(id: 19, name: 'Dous Makos', category: 'Desserts', priceHtg: 250, priceUsd: 2.50, description: 'Haitian fudge with coconut'),
  MockMenuItem(id: 20, name: 'Pain Patate', category: 'Desserts', priceHtg: 200, priceUsd: 2.00, description: 'Sweet potato pudding'),
  // Specials
  MockMenuItem(id: 21, name: "Special du Jour: Lambi en Sauce", category: 'Specials', priceHtg: 2200, priceUsd: 22.00, description: "Chef's daily special — fresh conch"),
];

final _now = DateTime.now();

final _mockActiveOrdersSeed = [
  MockOrder(
    id: 101,
    tableId: 2,
    tableName: 'Table 2',
    items: const [
      MockOrderItem(name: 'Griot avec Riz Collé', quantity: 2, priceHtg: 1200, priceUsd: 12.00, category: 'Mains'),
      MockOrderItem(name: 'Prestige Beer', quantity: 3, priceHtg: 300, priceUsd: 3.00, category: 'Drinks'),
    ],
    placedAt: DateTime(_now.year, _now.month, _now.day, _now.hour, _now.minute - 8),
    status: 'in_progress',
    waiter: 'Marie-Carmel',
    orderType: 'dine_in',
  ),
  MockOrder(
    id: 102,
    tableId: 3,
    tableName: 'Table 3',
    items: const [
      MockOrderItem(name: 'Lanbi (Conch)', quantity: 1, priceHtg: 1800, priceUsd: 18.00, note: 'Extra spicy please', category: 'Mains'),
      MockOrderItem(name: 'Bannann Peze', quantity: 2, priceHtg: 200, priceUsd: 2.00, category: 'Sides'),
      MockOrderItem(name: 'Jus de Corossol', quantity: 2, priceHtg: 200, priceUsd: 2.00, category: 'Drinks'),
    ],
    placedAt: DateTime(_now.year, _now.month, _now.day, _now.hour, _now.minute - 22),
    status: 'in_progress',
    waiter: 'Joseph',
    orderType: 'dine_in',
  ),
  MockOrder(
    id: 103,
    tableId: 4,
    tableName: 'Table 4',
    items: const [
      MockOrderItem(name: 'Tassot de Cabrit', quantity: 3, priceHtg: 1600, priceUsd: 16.00, category: 'Mains'),
      MockOrderItem(name: 'Poisson Gros Sel', quantity: 2, priceHtg: 1400, priceUsd: 14.00, category: 'Mains'),
      MockOrderItem(name: 'Rhum Barbancourt', quantity: 4, priceHtg: 450, priceUsd: 4.50, category: 'Drinks'),
      MockOrderItem(name: 'Prestige Beer', quantity: 6, priceHtg: 300, priceUsd: 3.00, category: 'Drinks'),
    ],
    placedAt: DateTime(_now.year, _now.month, _now.day, _now.hour, _now.minute - 35),
    status: 'ready',
    waiter: 'Claudine',
    orderType: 'dine_in',
  ),
  MockOrder(
    id: 104,
    tableId: 7,
    tableName: 'Terrace B',
    items: const [
      MockOrderItem(name: 'Accra', quantity: 1, priceHtg: 350, priceUsd: 3.50, category: 'Starters'),
      MockOrderItem(name: 'Poulet en Sauce', quantity: 2, priceHtg: 950, priceUsd: 9.50, category: 'Mains'),
      MockOrderItem(name: 'Café Haïtien', quantity: 2, priceHtg: 180, priceUsd: 1.80, category: 'Drinks'),
    ],
    placedAt: DateTime(_now.year, _now.month, _now.day, _now.hour, _now.minute - 5),
    status: 'pending',
    waiter: 'Pierre',
    orderType: 'takeout',
    customerName: 'Jean-Paul Dupont',
    customerPhone: '+509 4312-8890',
  ),
  MockOrder(
    id: 105,
    tableId: 0,
    tableName: '',
    items: const [
      MockOrderItem(name: 'Griot avec Riz Collé', quantity: 1, priceHtg: 1200, priceUsd: 12.00, category: 'Mains'),
      MockOrderItem(name: 'Jus de Corossol', quantity: 1, priceHtg: 200, priceUsd: 2.00, category: 'Drinks'),
    ],
    placedAt: DateTime(_now.year, _now.month, _now.day, _now.hour, _now.minute - 12),
    status: 'in_progress',
    waiter: 'Marie-Carmel',
    orderType: 'delivery',
    customerName: 'Claudette Pierre',
    customerPhone: '+509 3789-4412',
    deliveryAddress: '45 Rue des Miracles, Pétion-Ville',
  ),
  // Completed kitchen history samples (today vs older day, for reverse rules).
  MockOrder(
    id: 106,
    tableId: 1,
    tableName: 'Table 1',
    items: const [
      MockOrderItem(name: 'Poulet en Sauce', quantity: 1, priceHtg: 950, priceUsd: 9.50, category: 'Mains'),
      MockOrderItem(name: 'Café Haïtien', quantity: 1, priceHtg: 180, priceUsd: 1.80, category: 'Drinks'),
    ],
    placedAt: DateTime(_now.year, _now.month, _now.day, 8, 15),
    status: 'complete',
    waiter: 'Marie-Carmel',
    orderType: 'dine_in',
    isPaid: true, // closed — kept for kitchen history / completed list only
    kitchenBatches: [
      MockKitchenBatch(
        batchNumber: 1,
        items: const [
          MockOrderItem(name: 'Poulet en Sauce', quantity: 1, priceHtg: 950, priceUsd: 9.50, category: 'Mains'),
        ],
        status: 'complete',
        placedAt: DateTime(_now.year, _now.month, _now.day, 8, 15),
        kitchenCompletedAt: DateTime.now().subtract(const Duration(hours: 2)),
      ),
    ],
  ),
  MockOrder(
    id: 107,
    tableId: 5,
    tableName: 'Table 5',
    items: const [
      MockOrderItem(name: 'Tassot de Cabrit', quantity: 1, priceHtg: 1600, priceUsd: 16.00, category: 'Mains'),
      MockOrderItem(name: 'Prestige Beer', quantity: 1, priceHtg: 300, priceUsd: 3.00, category: 'Drinks'),
    ],
    placedAt: DateTime(_now.year, _now.month, _now.day, 7, 0),
    status: 'complete',
    waiter: 'Joseph',
    orderType: 'dine_in',
    isPaid: true,
    kitchenBatches: [
      MockKitchenBatch(
        batchNumber: 1,
        items: const [
          MockOrderItem(name: 'Tassot de Cabrit', quantity: 1, priceHtg: 1600, priceUsd: 16.00, category: 'Mains'),
        ],
        status: 'complete',
        placedAt: DateTime(_now.year, _now.month, _now.day, 7, 0),
        kitchenCompletedAt: DateTime.now().subtract(const Duration(hours: 4, minutes: 10)),
      ),
    ],
  ),
  MockOrder(
    id: 108,
    tableId: 6,
    tableName: 'Table 6',
    items: const [
      MockOrderItem(name: 'Accra', quantity: 2, priceHtg: 350, priceUsd: 3.50, category: 'Starters'),
    ],
    placedAt: () { final y = DateTime.now().subtract(const Duration(days: 1)); return DateTime(y.year, y.month, y.day, 19, 30); }(),
    status: 'delivered',
    waiter: 'Claudine',
    orderType: 'takeout',
    customerName: 'Yesterday Guest',
    kitchenBatches: [
      MockKitchenBatch(
        batchNumber: 1,
        items: const [
          MockOrderItem(name: 'Accra', quantity: 2, priceHtg: 350, priceUsd: 3.50, category: 'Starters'),
        ],
        status: 'delivered',
        placedAt: () { final y = DateTime.now().subtract(const Duration(days: 1)); return DateTime(y.year, y.month, y.day, 19, 30); }(),
        kitchenCompletedAt: () { final y = DateTime.now().subtract(const Duration(days: 1)); return DateTime(y.year, y.month, y.day, 19, 45); }(),
      ),
    ],
  ),
  MockOrder(
    id: 109, tableId: 8, tableName: 'Table 8',
    items: const [MockOrderItem(name: 'Lanbi (Conch)', quantity: 2, priceHtg: 1800, priceUsd: 18.00, category: 'Mains')],
    placedAt: DateTime(_now.year, _now.month, _now.day, _now.hour, _now.minute - 55),
    status: 'complete', waiter: 'Pierre', orderType: 'dine_in',
    isPaid: true,
    kitchenBatches: [MockKitchenBatch(batchNumber: 1,
      items: const [MockOrderItem(name: 'Lanbi (Conch)', quantity: 2, priceHtg: 1800, priceUsd: 18.00, category: 'Mains')],
      status: 'complete',
      placedAt: DateTime(_now.year, _now.month, _now.day, _now.hour, _now.minute - 55),
      kitchenCompletedAt: DateTime.now().subtract(const Duration(minutes: 45)))],
  ),
  MockOrder(
    id: 110, tableId: 9, tableName: 'Terrace A',
    items: const [
      MockOrderItem(name: 'Diri Djondjon', quantity: 1, priceHtg: 300, priceUsd: 3.00, category: 'Sides'),
      MockOrderItem(name: 'Griot avec Riz Collé', quantity: 1, priceHtg: 1200, priceUsd: 12.00, category: 'Mains'),
    ],
    placedAt: DateTime(_now.year, _now.month, _now.day, _now.hour, _now.minute - 70),
    status: 'complete', waiter: 'Joseph', orderType: 'delivery',
    customerName: 'Nadia Jean-Louis',
    customerPhone: '+509 3488-1122',
    kitchenBatches: [MockKitchenBatch(batchNumber: 1,
      items: const [
        MockOrderItem(name: 'Diri Djondjon', quantity: 1, priceHtg: 300, priceUsd: 3.00, category: 'Sides'),
        MockOrderItem(name: 'Griot avec Riz Collé', quantity: 1, priceHtg: 1200, priceUsd: 12.00, category: 'Mains'),
      ],
      status: 'complete',
      placedAt: DateTime(_now.year, _now.month, _now.day, _now.hour, _now.minute - 70),
      kitchenCompletedAt: DateTime.now().subtract(const Duration(hours: 1)))],
  ),
  MockOrder(
    id: 111, tableId: 2, tableName: 'Table 2',
    items: const [MockOrderItem(name: 'Bannann Peze', quantity: 3, priceHtg: 200, priceUsd: 2.00, category: 'Sides')],
    placedAt: DateTime(_now.year, _now.month, _now.day, _now.hour, _now.minute - 90),
    status: 'complete', waiter: 'Marie-Carmel', orderType: 'dine_in',
    isPaid: true,
    kitchenBatches: [MockKitchenBatch(batchNumber: 1,
      items: const [MockOrderItem(name: 'Bannann Peze', quantity: 3, priceHtg: 200, priceUsd: 2.00, category: 'Sides')],
      status: 'complete',
      placedAt: DateTime(_now.year, _now.month, _now.day, _now.hour, _now.minute - 90),
      kitchenCompletedAt: DateTime.now().subtract(const Duration(hours: 1, minutes: 20)))],
  ),
  MockOrder(
    id: 112, tableId: 3, tableName: 'Table 3',
    items: const [
      MockOrderItem(name: 'Tassot de Cabrit', quantity: 2, priceHtg: 1600, priceUsd: 16.00, category: 'Mains'),
      MockOrderItem(name: 'Salade de Chou', quantity: 2, priceHtg: 250, priceUsd: 2.50, category: 'Starters'),
    ],
    placedAt: DateTime(_now.year, _now.month, _now.day, _now.hour, _now.minute - 110),
    status: 'delivered', waiter: 'Claudine', orderType: 'dine_in',
    isPaid: true,
    kitchenBatches: [MockKitchenBatch(batchNumber: 1,
      items: const [
        MockOrderItem(name: 'Tassot de Cabrit', quantity: 2, priceHtg: 1600, priceUsd: 16.00, category: 'Mains'),
        MockOrderItem(name: 'Salade de Chou', quantity: 2, priceHtg: 250, priceUsd: 2.50, category: 'Starters'),
      ],
      status: 'delivered',
      placedAt: DateTime(_now.year, _now.month, _now.day, _now.hour, _now.minute - 110),
      kitchenCompletedAt: DateTime.now().subtract(const Duration(hours: 1, minutes: 45)))],
  ),
  MockOrder(
    id: 113, tableId: 4, tableName: 'Table 4',
    items: const [MockOrderItem(name: 'Poisson Gros Sel', quantity: 1, priceHtg: 1400, priceUsd: 14.00, category: 'Mains')],
    placedAt: DateTime(_now.year, _now.month, _now.day, _now.hour, _now.minute - 130),
    status: 'complete', waiter: 'Pierre', orderType: 'dine_in',
    isPaid: true,
    kitchenBatches: [MockKitchenBatch(batchNumber: 1,
      items: const [MockOrderItem(name: 'Poisson Gros Sel', quantity: 1, priceHtg: 1400, priceUsd: 14.00, category: 'Mains')],
      status: 'complete',
      placedAt: DateTime(_now.year, _now.month, _now.day, _now.hour, _now.minute - 130),
      kitchenCompletedAt: DateTime.now().subtract(const Duration(hours: 2, minutes: 5)))],
  ),
  MockOrder(
    id: 114, tableId: 7, tableName: 'Terrace B',
    items: const [MockOrderItem(name: 'Dous Makos', quantity: 2, priceHtg: 250, priceUsd: 2.50, category: 'Desserts')],
    placedAt: DateTime(_now.year, _now.month, _now.day, _now.hour, _now.minute - 160),
    status: 'complete', waiter: 'Joseph', orderType: 'takeout',
    customerName: 'Fabrice Moreau',
    kitchenBatches: [MockKitchenBatch(batchNumber: 1,
      items: const [MockOrderItem(name: 'Dous Makos', quantity: 2, priceHtg: 250, priceUsd: 2.50, category: 'Desserts')],
      status: 'complete',
      placedAt: DateTime(_now.year, _now.month, _now.day, _now.hour, _now.minute - 160),
      kitchenCompletedAt: DateTime.now().subtract(const Duration(hours: 2, minutes: 35)))],
  ),
  MockOrder(
    id: 115, tableId: 1, tableName: 'Table 1',
    items: const [
      MockOrderItem(name: 'Pain Patate', quantity: 3, priceHtg: 200, priceUsd: 2.00, category: 'Desserts'),
      MockOrderItem(name: 'Accra', quantity: 1, priceHtg: 350, priceUsd: 3.50, category: 'Starters'),
    ],
    placedAt: DateTime(_now.year, _now.month, _now.day, _now.hour, _now.minute - 185),
    status: 'complete', waiter: 'Marie-Carmel', orderType: 'reservation',
    isPaid: true,
    reservationGuestName: 'Famille Toussaint',
    reservationPartySize: 4,
    kitchenBatches: [MockKitchenBatch(batchNumber: 1,
      items: const [
        MockOrderItem(name: 'Pain Patate', quantity: 3, priceHtg: 200, priceUsd: 2.00, category: 'Desserts'),
        MockOrderItem(name: 'Accra', quantity: 1, priceHtg: 350, priceUsd: 3.50, category: 'Starters'),
      ],
      status: 'complete',
      placedAt: DateTime(_now.year, _now.month, _now.day, _now.hour, _now.minute - 185),
      kitchenCompletedAt: DateTime.now().subtract(const Duration(hours: 3, minutes: 10)))],
  ),
  MockOrder(
    id: 116, tableId: 5, tableName: 'Table 5',
    items: const [MockOrderItem(name: "Special du Jour: Lambi en Sauce", quantity: 1, priceHtg: 2200, priceUsd: 22.00, category: 'Specials')],
    placedAt: DateTime(_now.year, _now.month, _now.day, _now.hour, _now.minute - 210),
    status: 'complete', waiter: 'Claudine', orderType: 'dine_in',
    isPaid: true,
    kitchenBatches: [MockKitchenBatch(batchNumber: 1,
      items: const [MockOrderItem(name: "Special du Jour: Lambi en Sauce", quantity: 1, priceHtg: 2200, priceUsd: 22.00, category: 'Specials')],
      status: 'complete',
      placedAt: DateTime(_now.year, _now.month, _now.day, _now.hour, _now.minute - 210),
      kitchenCompletedAt: DateTime.now().subtract(const Duration(hours: 3, minutes: 30)))],
  ),
  MockOrder(
    id: 117, tableId: 9, tableName: 'Table 9',
    items: const [MockOrderItem(name: 'Grillades de Porc', quantity: 2, priceHtg: 1300, priceUsd: 13.00, category: 'Mains')],
    placedAt: DateTime(_now.year, _now.month, _now.day, _now.hour, _now.minute - 230),
    status: 'complete', waiter: 'Joseph', orderType: 'dine_in',
    isPaid: true,
    kitchenBatches: [MockKitchenBatch(batchNumber: 1,
      items: const [MockOrderItem(name: 'Grillades de Porc', quantity: 2, priceHtg: 1300, priceUsd: 13.00, category: 'Mains')],
      status: 'complete',
      placedAt: DateTime(_now.year, _now.month, _now.day, _now.hour, _now.minute - 230),
      kitchenCompletedAt: DateTime.now().subtract(const Duration(hours: 3, minutes: 55)))],
  ),
  MockOrder(
    id: 118, tableId: 10, tableName: 'Table 10',
    items: const [MockOrderItem(name: 'Riz Collé aux Pois', quantity: 3, priceHtg: 400, priceUsd: 4.00, category: 'Mains')],
    placedAt: DateTime(_now.year, _now.month, _now.day, _now.hour, _now.minute - 250),
    status: 'delivered', waiter: 'Pierre', orderType: 'takeout',
    customerName: 'Chantal Beaubrun',
    kitchenBatches: [MockKitchenBatch(batchNumber: 1,
      items: const [MockOrderItem(name: 'Riz Collé aux Pois', quantity: 3, priceHtg: 400, priceUsd: 4.00, category: 'Mains')],
      status: 'delivered',
      placedAt: DateTime(_now.year, _now.month, _now.day, _now.hour, _now.minute - 250),
      kitchenCompletedAt: DateTime.now().subtract(const Duration(hours: 4, minutes: 10)))],
  ),
  MockOrder(
    id: 119, tableId: 3, tableName: 'Table 3',
    items: const [MockOrderItem(name: 'Bouillon de Boeuf', quantity: 1, priceHtg: 900, priceUsd: 9.00, category: 'Mains')],
    placedAt: DateTime(_now.year, _now.month, _now.day, _now.hour, _now.minute - 270),
    status: 'complete', waiter: 'Marie-Carmel', orderType: 'reservation',
    reservationGuestName: 'Marc-André Dolce',
    kitchenBatches: [MockKitchenBatch(batchNumber: 1,
      items: const [MockOrderItem(name: 'Bouillon de Boeuf', quantity: 1, priceHtg: 900, priceUsd: 9.00, category: 'Mains')],
      status: 'complete',
      placedAt: DateTime(_now.year, _now.month, _now.day, _now.hour, _now.minute - 270),
      kitchenCompletedAt: DateTime.now().subtract(const Duration(hours: 4, minutes: 30)))],
  ),
  MockOrder(
    id: 120, tableId: 6, tableName: 'Terrace A',
    items: const [
      MockOrderItem(name: 'Poulet Rôti', quantity: 1, priceHtg: 1100, priceUsd: 11.00, category: 'Mains'),
      MockOrderItem(name: 'Salade de Chou', quantity: 1, priceHtg: 250, priceUsd: 2.50, category: 'Starters'),
    ],
    placedAt: DateTime(_now.year, _now.month, _now.day, _now.hour, _now.minute - 295),
    status: 'complete', waiter: 'Claudine', orderType: 'dine_in',
    isPaid: true,
    kitchenBatches: [MockKitchenBatch(batchNumber: 1,
      items: const [
        MockOrderItem(name: 'Poulet Rôti', quantity: 1, priceHtg: 1100, priceUsd: 11.00, category: 'Mains'),
        MockOrderItem(name: 'Salade de Chou', quantity: 1, priceHtg: 250, priceUsd: 2.50, category: 'Starters'),
      ],
      status: 'complete',
      placedAt: DateTime(_now.year, _now.month, _now.day, _now.hour, _now.minute - 295),
      kitchenCompletedAt: DateTime.now().subtract(const Duration(hours: 4, minutes: 55)))],
  ),
  MockOrder(
    id: 121, tableId: 8, tableName: 'Terrace B',
    items: const [MockOrderItem(name: 'Maïs Moulin', quantity: 2, priceHtg: 350, priceUsd: 3.50, category: 'Mains')],
    placedAt: DateTime(_now.year, _now.month, _now.day, _now.hour, _now.minute - 310),
    status: 'delivered', waiter: 'Joseph', orderType: 'delivery',
    customerName: 'Roseline Estimé',
    customerPhone: '+509 4455-6677',
    kitchenBatches: [MockKitchenBatch(batchNumber: 1,
      items: const [MockOrderItem(name: 'Maïs Moulin', quantity: 2, priceHtg: 350, priceUsd: 3.50, category: 'Mains')],
      status: 'delivered',
      placedAt: DateTime(_now.year, _now.month, _now.day, _now.hour, _now.minute - 310),
      kitchenCompletedAt: DateTime.now().subtract(const Duration(hours: 5, minutes: 10)))],
  ),
  MockOrder(
    id: 122, tableId: 2, tableName: 'Table 2',
    items: const [MockOrderItem(name: 'Tassot de Dinde', quantity: 1, priceHtg: 1500, priceUsd: 15.00, category: 'Mains')],
    placedAt: DateTime(_now.year, _now.month, _now.day, _now.hour, _now.minute - 330),
    status: 'complete', waiter: 'Pierre', orderType: 'dine_in',
    isPaid: true,
    kitchenBatches: [MockKitchenBatch(batchNumber: 1,
      items: const [MockOrderItem(name: 'Tassot de Dinde', quantity: 1, priceHtg: 1500, priceUsd: 15.00, category: 'Mains')],
      status: 'complete',
      placedAt: DateTime(_now.year, _now.month, _now.day, _now.hour, _now.minute - 330),
      kitchenCompletedAt: DateTime.now().subtract(const Duration(hours: 5, minutes: 30)))],
  ),
];

/// Kept for backward compatibility — the Kitchen Display still reads this.
final mockActiveOrders = _mockActiveOrdersSeed;

final _mockInventorySeed = [
  MockInventoryItem(id: 1, name: 'Riz (Rice)', unit: 'KG', quantity: 45, minThreshold: 10, category: 'Dry Goods', type: InventoryItemType.food),
  MockInventoryItem(id: 2, name: 'Pois Noirs (Black Beans)', unit: 'KG', quantity: 8, minThreshold: 10, category: 'Dry Goods', type: InventoryItemType.food),
  MockInventoryItem(id: 3, name: 'Poulet (Chicken)', unit: 'KG', quantity: 12, minThreshold: 8, category: 'Meat', type: InventoryItemType.food),
  MockInventoryItem(id: 4, name: 'Cabrit (Goat)', unit: 'KG', quantity: 3, minThreshold: 5, category: 'Meat', type: InventoryItemType.food),
  MockInventoryItem(id: 5, name: 'Lanbi (Conch)', unit: 'pcs', quantity: 20, minThreshold: 10, category: 'Seafood', type: InventoryItemType.food),
  MockInventoryItem(id: 6, name: 'Banane Plantain', unit: 'pcs', quantity: 40, minThreshold: 20, category: 'Produce', type: InventoryItemType.food),
  MockInventoryItem(id: 7, name: 'Prestige Beer', unit: 'Bottle', quantity: 48, minThreshold: 24, category: 'Beverages', type: InventoryItemType.drink),
  MockInventoryItem(id: 8, name: 'Rhum Barbancourt', unit: 'Bottle', quantity: 4, minThreshold: 6, category: 'Beverages', type: InventoryItemType.drink),
  MockInventoryItem(id: 9, name: 'Huile (Cooking Oil)', unit: 'L', quantity: 15, minThreshold: 5, category: 'Pantry', type: InventoryItemType.food),
  MockInventoryItem(id: 10, name: 'Sel (Salt)', unit: 'KG', quantity: 2, minThreshold: 3, category: 'Pantry', type: InventoryItemType.food),
  MockInventoryItem(id: 11, name: 'Akasan (Corn Drink)', unit: 'L', quantity: 8, minThreshold: 4, category: 'Beverages', type: InventoryItemType.drink),
  MockInventoryItem(id: 12, name: 'Jus de Corossol', unit: 'L', quantity: 6, minThreshold: 3, category: 'Beverages', type: InventoryItemType.drink),
  MockInventoryItem(id: 13, name: 'Café Haïtien', unit: 'Serving', quantity: 80, minThreshold: 20, category: 'Beverages', type: InventoryItemType.drink),
  MockInventoryItem(id: 14, name: 'Eau Minérale', unit: 'Bottle', quantity: 72, minThreshold: 24, category: 'Beverages', type: InventoryItemType.drink),
];

// ──────────────── STATE NOTIFIERS ────────────────

class TablesNotifier extends StateNotifier<List<MockTable>> {
  TablesNotifier() : super(_mockTablesSeed);
  int get _nextId => state.isEmpty ? 1 : state.map((t) => t.id).reduce((a, b) => a > b ? a : b) + 1;
  void add(MockTable t) => state = [...state, t.copyWith(id: _nextId)];
  void update(MockTable t) => state = [for (final r in state) r.id == t.id ? t : r];
  void remove(int id) => state = state.where((t) => t.id != id).toList();
}

class MenuNotifier extends StateNotifier<List<MockMenuItem>> {
  MenuNotifier() : super(_mockMenuSeed);
  int get _nextId => state.isEmpty ? 1 : state.map((m) => m.id).reduce((a, b) => a > b ? a : b) + 1;
  void add(MockMenuItem m) => state = [...state, m.copyWith(id: _nextId)];
  void update(MockMenuItem m) => state = [for (final r in state) r.id == m.id ? m : r];
  void remove(int id) => state = state.where((m) => m.id != id).toList();
}

/// Seed transactions for demo ledger (add/use per day).
List<MockInventoryTransaction> _mockTransactionsSeed() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final twoDaysAgo = today.subtract(const Duration(days: 2));
  return [
    MockInventoryTransaction(id: 1, itemId: 1, date: today, type: InventoryTransactionType.add, quantity: 10),
    MockInventoryTransaction(id: 2, itemId: 1, date: today, type: InventoryTransactionType.use, quantity: 5),
    MockInventoryTransaction(id: 3, itemId: 7, date: today, type: InventoryTransactionType.add, quantity: 24),
    MockInventoryTransaction(id: 4, itemId: 7, date: today, type: InventoryTransactionType.use, quantity: 12),
    MockInventoryTransaction(id: 5, itemId: 1, date: yesterday, type: InventoryTransactionType.add, quantity: 20),
    MockInventoryTransaction(id: 6, itemId: 1, date: yesterday, type: InventoryTransactionType.use, quantity: 8),
    MockInventoryTransaction(id: 7, itemId: 8, date: yesterday, type: InventoryTransactionType.use, quantity: 2),
    MockInventoryTransaction(id: 8, itemId: 3, date: twoDaysAgo, type: InventoryTransactionType.add, quantity: 15),
    MockInventoryTransaction(id: 9, itemId: 3, date: twoDaysAgo, type: InventoryTransactionType.use, quantity: 3),
  ];
}

class RestaurantInventoryNotifier extends StateNotifier<List<MockInventoryItem>> {
  RestaurantInventoryNotifier() : super(_mockInventorySeed);

  List<MockInventoryTransaction> _transactions = _mockTransactionsSeed();
  int get _nextItemId => state.isEmpty ? 1 : state.map((i) => i.id).reduce((a, b) => a > b ? a : b) + 1;
  int get _nextTxId => _transactions.isEmpty ? 1 : _transactions.map((t) => t.id).reduce((a, b) => a > b ? a : b) + 1;

  void add(MockInventoryItem item) => state = [...state, item.copyWith(id: _nextItemId)];
  void update(MockInventoryItem item) => state = [for (final r in state) r.id == item.id ? item : r];
  void remove(int id) {
    state = state.where((i) => i.id != id).toList();
    _transactions = _transactions.where((t) => t.itemId != id).toList();
  }

  /// Record a transaction and update item quantity.
  /// For [InventoryTransactionType.adjust], [quantity] is signed: positive = add, negative = subtract.
  void addTransaction(int itemId, InventoryTransactionType type, double quantity, {String? note}) {
    final item = state.firstWhere((i) => i.id == itemId);
    double newQty = item.quantity;
    if (type == InventoryTransactionType.add) {
      newQty += quantity;
    } else if (type == InventoryTransactionType.use) {
      newQty -= quantity;
    } else {
      // adjust: quantity is signed
      newQty += quantity;
    }
    newQty = newQty.clamp(0.0, double.infinity);
    _transactions = [
      ..._transactions,
      MockInventoryTransaction(
        id: _nextTxId,
        itemId: itemId,
        date: DateTime.now(),
        type: type,
        quantity: quantity,
        note: note,
      ),
    ];
    _transactions.sort((a, b) => b.date.compareTo(a.date));
    state = [for (final r in state) r.id == itemId ? r.copyWith(quantity: newQty) : r];
  }

  /// Get daily summaries for an item (aggregated per day, like bank ledger).
  List<InventoryDaySummary> getDailySummaries(int itemId) {
    final matches = state.where((i) => i.id == itemId);
    if (matches.isEmpty) return [];
    final item = matches.first;
    final txs = _transactions.where((t) => t.itemId == itemId).toList();
    final byDate = <DateTime, ({double add, double use})>{};
    for (final t in txs) {
      final d = DateTime(t.date.year, t.date.month, t.date.day);
      byDate[d] ??= (add: 0, use: 0);
      if (t.type == InventoryTransactionType.add) {
        byDate[d] = (add: byDate[d]!.add + t.quantity, use: byDate[d]!.use);
      } else if (t.type == InventoryTransactionType.use) {
        byDate[d] = (add: byDate[d]!.add, use: byDate[d]!.use + t.quantity);
      } else {
        // adjust: signed quantity
        if (t.quantity >= 0) {
          byDate[d] = (add: byDate[d]!.add + t.quantity, use: byDate[d]!.use);
        } else {
          byDate[d] = (add: byDate[d]!.add, use: byDate[d]!.use + t.quantity.abs());
        }
      }
    }
    final sorted = byDate.keys.toList()..sort((a, b) => b.compareTo(a));
    double runningBalance = item.quantity;
    final result = <InventoryDaySummary>[];
    for (final d in sorted) {
      final add = byDate[d]!.add;
      final use = byDate[d]!.use;
      runningBalance = runningBalance + add - use;
      result.add(InventoryDaySummary(date: d, totalAdd: add, totalUse: use, balance: runningBalance));
    }
    return result;
  }

  List<MockInventoryTransaction> getTransactionsForItem(int itemId) =>
      _transactions.where((t) => t.itemId == itemId).toList();
}

// ──────────────── RESTAURANT ORDERS NOTIFIER ────────────────

class RestaurantOrdersNotifier extends StateNotifier<List<MockOrder>> {
  RestaurantOrdersNotifier()
      : super(List.from(_mockActiveOrdersSeed));

  int get _nextId =>
      state.isEmpty ? 200 : state.map((o) => o.id).reduce((a, b) => a > b ? a : b) + 1;

  void add(MockOrder o) => state = [o.copyWith(id: _nextId), ...state];

  void updateStatus(int id, String status) {
    state = [
      for (final o in state)
        if (o.id == id)
          o.copyWith(
            status: status,
            kitchenBatches: o.kitchenBatches.isNotEmpty
                ? [
                    o.kitchenBatches.first.copyWith(status: status),
                    ...o.kitchenBatches.skip(1),
                  ]
                : o.kitchenBatches,
          )
        else
          o,
    ];
  }

  void updateBatchStatus(int orderId, int batchNumber, String status) {
    state = [
      for (final o in state)
        if (o.id == orderId)
          o.copyWith(
            kitchenBatches: [
              for (final b in o.kitchenBatches)
                if (b.batchNumber == batchNumber)
                  _batchWithNewStatus(b, status)
                else
                  b,
            ],
          )
        else
          o,
    ];
  }

  static MockKitchenBatch _batchWithNewStatus(MockKitchenBatch b, String newStatus) {
    final norm = newStatus == 'preparing' ? 'in_progress' : newStatus;
    final terminal = norm == 'complete' || norm == 'delivered';
    return b.copyWith(
      status: newStatus,
      kitchenCompletedAt: terminal
          ? (b.kitchenCompletedAt ?? DateTime.now())
          : null,
    );
  }

  /// Append items to an existing order.
  ///
  /// Drinks (category == 'Drinks') are merged directly into the order's flat
  /// item list — no kitchen ticket needed. All other items (food) go into a
  /// new add-on kitchen batch so the kitchen can track preparation.
  ///
  /// Returns `false` if [prepaidCapHtg] would be exceeded (state unchanged).
  bool addBatch(int orderId, List<MockOrderItem> newItems) {
    final foodItems = newItems.where((i) => !i.isDrink).toList();
    final drinkItems = newItems.where((i) => i.isDrink).toList();

    var success = true;
    state = [
      for (final o in state)
        if (o.id == orderId)
          (() {
            var updatedItems = List<MockOrderItem>.from(o.items);
            for (final drink in drinkItems) {
              final idx =
                  updatedItems.indexWhere((i) => i.name == drink.name);
              if (idx >= 0) {
                final existing = updatedItems[idx];
                updatedItems[idx] = MockOrderItem(
                  name: existing.name,
                  quantity: existing.quantity + drink.quantity,
                  priceHtg: existing.priceHtg,
                  priceUsd: existing.priceUsd,
                  note: existing.note,
                  category: existing.category,
                  isCustom: existing.isCustom,
                  sendToKitchen: existing.sendToKitchen,
                  customStatus: existing.customStatus,
                );
              } else {
                updatedItems.add(drink);
              }
            }

            final updatedBatches = List<MockKitchenBatch>.from(
                o.kitchenBatches);
            if (foodItems.isNotEmpty) {
              updatedBatches.add(MockKitchenBatch(
                batchNumber: updatedBatches.length + 1,
                items: foodItems,
                status: 'pending',
                placedAt: DateTime.now(),
              ));
              updatedItems = [...updatedItems, ...foodItems];
            }

            final subtotal =
                updatedItems.fold(0.0, (s, i) => s + i.priceHtg * i.quantity);
            final cap = o.prepaidCapHtg;
            if (cap != null) {
              final bill =
                  estimatedBillTotalHtgFromSubtotal(subtotal);
              if (bill > cap + 0.009) {
                success = false;
                return o;
              }
            }

            return o.copyWith(
              items: updatedItems,
              kitchenBatches: updatedBatches,
            );
          })()
        else
          o,
    ];
    return success;
  }

  void markPaid(int id) {
    state = [
      for (final o in state)
        if (o.id == id) o.copyWith(isPaid: true) else o,
    ];
  }

  void markPaymentLinkSent(
    int id, {
    required String recipient,
    required String channel,
    double? prepaidCapHtg,
  }) {
    state = [
      for (final o in state)
        if (o.id == id)
          o.copyWith(
            paymentLinkSent: true,
            paymentLinkRecipient: recipient,
            paymentLinkChannel: channel,
            paymentLinkSentAt: DateTime.now(),
            prepaidCapHtg: prepaidCapHtg ?? o.prepaidCapHtg,
          )
        else
          o,
    ];
  }

  void holdKitchenForPayment(int id) {
    state = [
      for (final o in state)
        if (o.id == id) o.copyWith(kitchenHeldForPayment: true) else o,
    ];
  }

  /// Simulates payment-link webhook: funds received but staff still confirms [isPaid]
  /// when [paymentLinkSent] is true (all order types).
  void confirmPaymentAndRelease(int id) {
    state = [
      for (final o in state)
        if (o.id == id)
          o.paymentLinkSent
              ? o.copyWith(
                  paymentLinkRemotePaid: true,
                  kitchenHeldForPayment: false,
                )
              : o.copyWith(isPaid: true, kitchenHeldForPayment: false)
        else
          o,
    ];
  }

  void setStaffPaymentConfirmed(int id, bool paid) {
    state = [
      for (final o in state)
        if (o.id == id)
          o.copyWith(
            isPaid: paid,
            kitchenHeldForPayment:
                paid ? false : o.kitchenHeldForPayment,
          )
        else
          o,
    ];
  }

  void setVisitCompleted(int id, {bool completed = true}) {
    state = [
      for (final o in state)
        if (o.id == id) o.copyWith(visitCompleted: completed) else o,
    ];
  }

  void applyCustomerCredit(int id, double amountHtg) {
    if (amountHtg <= 0) return;
    state = [
      for (final o in state)
        if (o.id == id)
          o.copyWith(
            customerCreditAppliedHtg: o.customerCreditAppliedHtg + amountHtg,
          )
        else
          o,
    ];
  }

  /// Permanently cancel an order (remove from list).
  void cancelOrder(int id) => state = state.where((o) => o.id != id).toList();

  /// Merge [absorbedId] into [survivorId].
  ///
  /// - Items from the absorbed order are appended to the survivor.
  /// - A [MergedTableSnapshot] is stored on the survivor for staff review.
  /// - The absorbed order is removed from the active list.
  ///
  /// Returns `false` (and leaves state unchanged) if either order is blocked:
  /// - has a pending (unsettled) payment link, OR
  /// - has a prepaid cap set.
  bool mergeOrders(int survivorId, int absorbedId) {
    final survivor = state.firstWhere((o) => o.id == survivorId,
        orElse: () => throw ArgumentError('Survivor not found'));
    final absorbed = state.firstWhere((o) => o.id == absorbedId,
        orElse: () => throw ArgumentError('Absorbed not found'));

    // One-time merge only — survivor cannot absorb a second table.
    if (survivor.mergedSnapshot != null) return false;

    final survivorBlocked =
        (survivor.paymentLinkSent && !survivor.paymentLinkRemotePaid) ||
            survivor.prepaidCapHtg != null;
    final absorbedBlocked =
        (absorbed.paymentLinkSent && !absorbed.paymentLinkRemotePaid) ||
            absorbed.prepaidCapHtg != null;
    if (survivorBlocked || absorbedBlocked) return false;

    final snapshot = MergedTableSnapshot(
      orderId: absorbed.id,
      tableName: absorbed.tableName,
      mergedAt: DateTime.now(),
      items: List.unmodifiable(absorbed.items),
      totalHtg: absorbed.allItemsTotalHtg,
      waiter: absorbed.waiter,
      customerName: absorbed.customerName,
    );

    state = [
      for (final o in state)
        if (o.id == survivorId)
          o.copyWith(
            items: [...o.items, ...absorbed.items],
            mergedSnapshot: snapshot,
          )
        else if (o.id == absorbedId)
          null
        else
          o,
    ].whereType<MockOrder>().toList();

    return true;
  }

  /// Remove an item by name from both `items` and all kitchen batches.
  void removeItem(int orderId, String itemName) {
    state = [
      for (final o in state)
        if (o.id == orderId)
          o.copyWith(
            items: o.items.where((i) => i.name != itemName).toList(),
            kitchenBatches: o.kitchenBatches
                .map((b) => b.copyWith(
                      items: b.items.where((i) => i.name != itemName).toList(),
                    ))
                .where((b) => b.items.isNotEmpty)
                .toList(),
          )
        else
          o,
    ];
  }

  /// Decrease the quantity of an item by 1. Removes the item when it reaches 0.
  void decreaseItemQty(int orderId, String itemName) {
    state = [
      for (final o in state)
        if (o.id == orderId)
          (() {
            final updatedItems = o.items.map((i) {
              if (i.name != itemName) return i;
              return MockOrderItem(
                name: i.name,
                quantity: i.quantity - 1,
                priceHtg: i.priceHtg,
                priceUsd: i.priceUsd,
                note: i.note,
                category: i.category,
                isCustom: i.isCustom,
                sendToKitchen: i.sendToKitchen,
                customStatus: i.customStatus,
              );
            }).where((i) => i.quantity > 0).toList();

            final updatedBatches = o.kitchenBatches.map((b) {
              final bItems = b.items.map((i) {
                if (i.name != itemName) return i;
                return MockOrderItem(
                  name: i.name,
                  quantity: i.quantity - 1,
                  priceHtg: i.priceHtg,
                  priceUsd: i.priceUsd,
                  note: i.note,
                  category: i.category,
                  isCustom: i.isCustom,
                  sendToKitchen: i.sendToKitchen,
                  customStatus: i.customStatus,
                );
              }).where((i) => i.quantity > 0).toList();
              return b.copyWith(items: bItems);
            }).where((b) => b.items.isNotEmpty).toList();

            return o.copyWith(items: updatedItems, kitchenBatches: updatedBatches);
          })()
        else
          o,
    ];
  }

  void remove(int id) => state = state.where((o) => o.id != id).toList();

  /// Advance custom line status: pending → ready → served (order + kitchen batches).
  void advanceCustomItemStatus(int orderId, String itemName) {
    state = [
      for (final o in state)
        if (o.id != orderId)
          o
        else
          _withCustomItemStatus(o, itemName),
    ];
  }

  static String _nextCustomStatus(String current) {
    switch (current) {
      case 'pending':
        return 'ready';
      case 'ready':
        return 'served';
      default:
        return 'served';
    }
  }

  static MockOrder _withCustomItemStatus(MockOrder o, String itemName) {
    final idx = o.items.indexWhere((i) => i.name == itemName && i.isCustom);
    if (idx < 0) return o;
    final next = _nextCustomStatus(o.items[idx].customStatus);
    return o.copyWith(
      items: [
        for (final i in o.items)
          if (i.name == itemName && i.isCustom)
            i.copyWith(customStatus: next)
          else
            i,
      ],
      kitchenBatches: [
        for (final b in o.kitchenBatches)
          b.copyWith(
            items: [
              for (final i in b.items)
                if (i.name == itemName && i.isCustom)
                  i.copyWith(customStatus: next)
                else
                  i,
            ],
          ),
      ],
    );
  }
}

// ──────────────── PROVIDERS ────────────────

final mockTablesProvider = StateNotifierProvider<TablesNotifier, List<MockTable>>(
  (ref) => TablesNotifier(),
);

final mockMenuProvider = StateNotifierProvider<MenuNotifier, List<MockMenuItem>>(
  (ref) => MenuNotifier(),
);

/// Mutable restaurant orders — use this everywhere orders are read or modified.
final mockRestaurantOrdersProvider =
    StateNotifierProvider<RestaurantOrdersNotifier, List<MockOrder>>(
  (ref) => RestaurantOrdersNotifier(),
);

/// Backward-compatible alias (read-only view) used by KitchenDisplay.
final mockOrdersProvider = Provider<List<MockOrder>>(
  (ref) => ref.watch(mockRestaurantOrdersProvider),
);

/// Provider that holds the ID of the order currently being edited in add-items mode.
/// Null means the order screen is in new-order mode.
final activeEditOrderIdProvider = StateProvider<int?>((ref) => null);

// ──────────────── RECENT TRANSACTIONS ────────────────
// Represents today's completed/paid orders shown on the dashboard.
// Kept separate from active orders since paid orders carry extra billing info.

class MockTransaction {
  final String label;
  final String waiter;
  final double totalHtg;
  final String paymentMethod;
  final String time;

  const MockTransaction({
    required this.label,
    required this.waiter,
    required this.totalHtg,
    required this.paymentMethod,
    required this.time,
  });
}

const _mockTransactions = [
  MockTransaction(label: 'Table 4 — Dine In',   waiter: 'Claudine',    totalHtg: 12800, paymentMethod: 'MonCash', time: '13:42'),
  MockTransaction(label: 'Table 1 — Takeout',    waiter: 'Joseph',      totalHtg: 3200,  paymentMethod: 'Cash',    time: '13:05'),
  MockTransaction(label: 'Terrace A — Dine In',  waiter: 'Marie-Carmel',totalHtg: 5600,  paymentMethod: 'MonCash', time: '12:50'),
  MockTransaction(label: 'Bar 1 — Dine In',      waiter: 'Pierre',      totalHtg: 900,   paymentMethod: 'Cash',    time: '12:30'),
];

final mockRecentTransactionsProvider =
    Provider<List<MockTransaction>>((ref) => _mockTransactions);

final mockRestaurantInventoryProvider = StateNotifierProvider<RestaurantInventoryNotifier, List<MockInventoryItem>>(
  (ref) => RestaurantInventoryNotifier(),
);

// ── Table merge snapshot ──────────────────────────────────────────────────────

/// Immutable snapshot of the order that was absorbed when two tables merged.
/// Persisted on the surviving order so staff can review it from the Merge badge.
class MergedTableSnapshot {
  final int orderId;
  final String tableName;
  final DateTime mergedAt;
  final List<MockOrderItem> items;
  final double totalHtg;
  final String? waiter;
  final String? customerName;

  const MergedTableSnapshot({
    required this.orderId,
    required this.tableName,
    required this.mergedAt,
    required this.items,
    required this.totalHtg,
    this.waiter,
    this.customerName,
  });
}

// Sentinel for copyWith nullable fields
const Object _sentinel = Object();
