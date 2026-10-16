import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_notification_provider.dart';
import 'mock_hotel_data.dart';
import 'mock_restaurant_data.dart';

const Object _rs = Object();

// ── Custom item on reservation (pre-order) ────────────────────────────────────

class MockDiningReservationCustomItem {
  final int id;
  final String name;
  final int quantity;
  final double priceHtg;
  /// Optional line note (prep details, allergies, etc.).
  final String? note;
  /// When true the item is treated as food; when false as drink (not sent to kitchen).
  final bool isFood;
  /// pending | ready | served
  final String status;

  const MockDiningReservationCustomItem({
    required this.id,
    required this.name,
    required this.quantity,
    required this.priceHtg,
    this.note,
    this.isFood = true,
    this.status = 'pending',
  });

  MockDiningReservationCustomItem copyWith({
    int? id,
    String? name,
    int? quantity,
    double? priceHtg,
    Object? note = _rs,
    bool? isFood,
    String? status,
  }) =>
      MockDiningReservationCustomItem(
        id: id ?? this.id,
        name: name ?? this.name,
        quantity: quantity ?? this.quantity,
        priceHtg: priceHtg ?? this.priceHtg,
        note: note == _rs ? this.note : note as String?,
        isFood: isFood ?? this.isFood,
        status: status ?? this.status,
      );

  MockOrderItem toMockOrderItem() => MockOrderItem(
        name: name,
        quantity: quantity,
        priceHtg: priceHtg,
        priceUsd: 0,
        note: note,
        category: isFood ? 'Specials' : 'Drinks',
        isCustom: true,
        sendToKitchen: false,
        customStatus: status,
      );

  MockHotelOrderItem toMockHotelOrderItem() => MockHotelOrderItem(
        name: name,
        quantity: quantity,
        priceHtg: priceHtg,
        priceUsd: 0,
        note: note,
        category: isFood ? 'Specials' : 'Drinks',
        isCustom: true,
        sendToKitchen: false,
        customStatus: status,
      );
}

// ── Pre-order line: catalog snapshot OR custom ──────────────────────────────

class MockDiningReservationPreOrderItem {
  final MockOrderItem? catalogItem;
  final MockDiningReservationCustomItem? customItem;
  /// True once this line was included in a kitchen dispatch from the pre-order sheet.
  final bool kitchenSent;

  MockDiningReservationPreOrderItem.catalog(MockOrderItem item,
      {this.kitchenSent = false})
      : catalogItem = item,
        customItem = null;

  MockDiningReservationPreOrderItem.custom(MockDiningReservationCustomItem item,
      {this.kitchenSent = false})
      : catalogItem = null,
        customItem = item;

  bool get isCustom => customItem != null;
  int get quantity => isCustom ? customItem!.quantity : catalogItem!.quantity;
  double get unitPriceHtg =>
      isCustom ? customItem!.priceHtg : catalogItem!.priceHtg;
  double get lineTotalHtg => quantity * unitPriceHtg;

  MockDiningReservationPreOrderItem copyWith({
    MockOrderItem? catalogItem,
    MockDiningReservationCustomItem? customItem,
    bool? kitchenSent,
  }) {
    if (isCustom) {
      return MockDiningReservationPreOrderItem.custom(
        customItem ?? this.customItem!,
        kitchenSent: kitchenSent ?? this.kitchenSent,
      );
    }
    return MockDiningReservationPreOrderItem.catalog(
      catalogItem ?? this.catalogItem!,
      kitchenSent: kitchenSent ?? this.kitchenSent,
    );
  }
}

// ── Reservation ─────────────────────────────────────────────────────────────

class MockDiningReservation {
  final int id;
  final String guestName;
  final String phone;
  final int adults;
  final int children;
  final DateTime reservationAt;
  final String? purpose;
  final String? specialNotes;
  /// pending | confirmed | active | cancelled
  final String status;
  final int? assignedTableId;
  final String? assignedTableName;
  final List<MockDiningReservationPreOrderItem> preOrderItems;
  final int? linkedOrderId;
  final DateTime createdAt;
  final String? linkedRoomNumber;

  MockDiningReservation({
    required this.id,
    required this.guestName,
    required this.phone,
    required this.adults,
    required this.children,
    required this.reservationAt,
    this.purpose,
    this.specialNotes,
    this.status = 'pending',
    this.assignedTableId,
    this.assignedTableName,
    this.preOrderItems = const [],
    this.linkedOrderId,
    DateTime? createdAt,
    this.linkedRoomNumber,
  }) : createdAt = createdAt ?? DateTime.now();

  int get partySize => adults + children;
  double get preOrderSubtotalHtg =>
      preOrderItems.fold(0.0, (sum, item) => sum + item.lineTotalHtg);

  MockDiningReservation copyWith({
    int? id,
    String? guestName,
    String? phone,
    int? adults,
    int? children,
    DateTime? reservationAt,
    Object? purpose = _rs,
    Object? specialNotes = _rs,
    String? status,
    Object? assignedTableId = _rs,
    Object? assignedTableName = _rs,
    List<MockDiningReservationPreOrderItem>? preOrderItems,
    Object? linkedOrderId = _rs,
    DateTime? createdAt,
    Object? linkedRoomNumber = _rs,
  }) =>
      MockDiningReservation(
        id: id ?? this.id,
        guestName: guestName ?? this.guestName,
        phone: phone ?? this.phone,
        adults: adults ?? this.adults,
        children: children ?? this.children,
        reservationAt: reservationAt ?? this.reservationAt,
        purpose: purpose == _rs ? this.purpose : purpose as String?,
        specialNotes:
            specialNotes == _rs ? this.specialNotes : specialNotes as String?,
        status: status ?? this.status,
        assignedTableId: assignedTableId == _rs
            ? this.assignedTableId
            : assignedTableId as int?,
        assignedTableName: assignedTableName == _rs
            ? this.assignedTableName
            : assignedTableName as String?,
        preOrderItems: preOrderItems ?? this.preOrderItems,
        linkedOrderId: linkedOrderId == _rs
            ? this.linkedOrderId
            : linkedOrderId as int?,
        createdAt: createdAt ?? this.createdAt,
        linkedRoomNumber: linkedRoomNumber == _rs
            ? this.linkedRoomNumber
            : linkedRoomNumber as String?,
      );
}

// ── Order builders (activation) ─────────────────────────────────────────────

List<MockOrderItem> restaurantLineItemsFromPreOrder(
    List<MockDiningReservationPreOrderItem> pre) {
  final out = <MockOrderItem>[];
  for (final p in pre) {
    if (p.catalogItem != null) out.add(p.catalogItem!);
    if (p.customItem != null) out.add(p.customItem!.toMockOrderItem());
  }
  return out;
}

List<MockOrderItem> restaurantKitchenItemsFromLines(List<MockOrderItem> lines) =>
    lines.where((i) => !i.isDrink).toList();

MockOrder buildRestaurantOrderFromReservation({
  required MockDiningReservation r,
  required int tableId,
  required String tableName,
  required String waiter,
}) {
  final lines = restaurantLineItemsFromPreOrder(r.preOrderItems);
  final kitchen = restaurantKitchenItemsFromLines(lines);
  final now = DateTime.now();
  final kitchenStatus = kitchen.isEmpty ? 'complete' : 'pending';
  final orderStatus = kitchen.isEmpty ? 'in_progress' : 'pending';
  return MockOrder(
    id: 0,
    tableId: tableId,
    tableName: tableName,
    items: lines,
    placedAt: now,
    status: orderStatus,
    waiter: waiter,
    orderType: 'reservation',
    customerName: r.guestName,
    customerPhone: r.phone,
    reservationGuestName: r.guestName,
    reservationPartySize: r.partySize,
    reservationNotes: r.specialNotes,
    kitchenBatches: [
      MockKitchenBatch(
        batchNumber: 1,
        items: kitchen,
        status: kitchenStatus,
        placedAt: now,
      ),
    ],
  );
}

MockHotelOrderItem hotelOrderItemFromRestaurantItem(MockOrderItem i) =>
    MockHotelOrderItem(
      name: i.name,
      quantity: i.quantity,
      priceHtg: i.priceHtg,
      priceUsd: i.priceUsd,
      note: i.note,
      category: i.category,
      isCustom: i.isCustom,
      sendToKitchen: i.sendToKitchen,
      customStatus: i.customStatus,
    );

List<MockHotelOrderItem> hotelLineItemsFromPreOrder(
    List<MockDiningReservationPreOrderItem> pre) {
  final lines = restaurantLineItemsFromPreOrder(pre);
  return lines.map(hotelOrderItemFromRestaurantItem).toList();
}

List<MockHotelOrderItem> hotelKitchenItemsFromLines(
    List<MockHotelOrderItem> lines) =>
    lines.where((i) => !i.isDrink).toList();

MockHotelRestaurantOrder buildHotelRestaurantOrderFromReservation({
  required MockDiningReservation r,
  required String tableName,
  required String waiter,
}) {
  final lines = hotelLineItemsFromPreOrder(r.preOrderItems);
  final kitchen = hotelKitchenItemsFromLines(lines);
  final now = DateTime.now();
  final kitchenStatus = kitchen.isEmpty ? 'complete' : 'pending';
  final orderStatus = kitchen.isEmpty ? 'in_progress' : 'pending';
  return MockHotelRestaurantOrder(
    id: 0,
    roomNumber: r.linkedRoomNumber,
    guestName: r.guestName,
    tableName: tableName,
    items: lines,
    placedAt: now,
    status: orderStatus,
    waiter: waiter,
    orderType: 'reservation',
    customerPhone: r.phone,
    reservationGuestName: r.guestName,
    reservationPartySize: r.partySize,
    reservationNotes: r.specialNotes,
    kitchenBatches: [
      MockHotelKitchenBatch(
        batchNumber: 1,
        items: kitchen,
        status: kitchenStatus,
        placedAt: now,
      ),
    ],
  );
}

// ── Seed data ─────────────────────────────────────────────────────────────────

DateTime _tomorrowAt(int h, int m) {
  final t = DateTime.now().add(const Duration(days: 1));
  return DateTime(t.year, t.month, t.day, h, m);
}

final _restaurantReservationsSeed = <MockDiningReservation>[
  MockDiningReservation(
    id: 1,
    guestName: 'Jean Baptiste',
    phone: '+509 34 12 45 67',
    adults: 4,
    children: 2,
    reservationAt: _tomorrowAt(19, 30),
    purpose: 'Birthday dinner',
    specialNotes: 'Window seat if possible',
    status: 'confirmed',
    preOrderItems: [
      MockDiningReservationPreOrderItem.catalog(
        const MockOrderItem(
          name: 'Griot avec Riz Collé',
          quantity: 3,
          priceHtg: 1200,
          priceUsd: 12,
          category: 'Mains',
        ),
      ),
    ],
  ),
  MockDiningReservation(
    id: 2,
    guestName: 'Marie Lourdes',
    phone: '+509 48 90 11 22',
    adults: 2,
    children: 0,
    reservationAt: _tomorrowAt(12, 0),
    status: 'pending',
    preOrderItems: [],
  ),
];

final _hotelRestaurantReservationsSeed = <MockDiningReservation>[
  MockDiningReservation(
    id: 1,
    guestName: 'Hotel Guest — Dupont',
    phone: '+509 22 33 44 55',
    adults: 2,
    children: 1,
    reservationAt: _tomorrowAt(20, 0),
    purpose: 'Anniversary',
    status: 'confirmed',
    linkedRoomNumber: '102',
    preOrderItems: [
      MockDiningReservationPreOrderItem.custom(
        MockDiningReservationCustomItem(
          id: 1,
          name: 'Party platter (10 pers.)',
          quantity: 1,
          priceHtg: 8500,
          isFood: true,
        ),
      ),
    ],
  ),
];

// ── Notifiers ─────────────────────────────────────────────────────────────────

class DiningReservationsNotifier extends StateNotifier<List<MockDiningReservation>> {
  DiningReservationsNotifier(super.initial);

  int get _nextId => state.isEmpty
      ? 1
      : state.map((r) => r.id).reduce((a, b) => a > b ? a : b) + 1;

  void add(MockDiningReservation r) => state = [...state, r.copyWith(id: _nextId)];

  void update(MockDiningReservation r) =>
      state = [for (final x in state) x.id == r.id ? r : x];

  void confirm(int id) => state = [
        for (final x in state)
          if (x.id == id)
            x.status == 'pending' ? x.copyWith(status: 'confirmed') : x
          else
            x,
      ];

  void cancel(int id) => state = [
        for (final x in state)
          if (x.id == id)
            (x.status != 'active' && x.status != 'cancelled')
                ? x.copyWith(status: 'cancelled')
                : x
          else
            x,
      ];

  void updatePreOrderItems(int id, List<MockDiningReservationPreOrderItem> items) =>
      state = [
        for (final x in state) x.id == id ? x.copyWith(preOrderItems: items) : x,
      ];

  void updateCustomItemStatus(int reservationId, int customItemId, String newStatus) {
    state = [
      for (final r in state)
        if (r.id != reservationId)
          r
        else
          r.copyWith(
            preOrderItems: [
              for (final p in r.preOrderItems)
                if (p.customItem?.id != customItemId)
                  p
                else
                  MockDiningReservationPreOrderItem.custom(
                    p.customItem!.copyWith(status: newStatus),
                    kitchenSent: p.kitchenSent,
                  ),
            ],
          ),
    ];
  }

  /// Dispatches every unsent **food** pre-order line to the linked table order's kitchen.
  /// Drinks and lines already sent are skipped. Returns true if a batch was created.
  bool sendPreOrderFoodToKitchen({
    required int reservationId,
    required WidgetRef ref,
    required bool isHotel,
  }) {
    final r = state.firstWhere((x) => x.id == reservationId);
    final orderId = r.linkedOrderId;
    if (orderId == null || r.status != 'active') return false;

    final batchRestaurant = <MockOrderItem>[];
    final newPreOrder = <MockDiningReservationPreOrderItem>[];

    for (final p in r.preOrderItems) {
      if (p.kitchenSent) {
        newPreOrder.add(p);
        continue;
      }
      final line = p.catalogItem ?? p.customItem!.toMockOrderItem();
      if (line.isDrink) {
        newPreOrder.add(p);
        continue;
      }
      batchRestaurant.add(line);
      newPreOrder.add(p.copyWith(kitchenSent: true));
    }

    if (batchRestaurant.isEmpty) return false;

    if (isHotel) {
      final hotelItems =
          batchRestaurant.map((e) => hotelOrderItemFromRestaurantItem(e)).toList();
      final ok = ref
          .read(mockHotelRestaurantOrdersProvider.notifier)
          .addBatch(orderId, hotelItems);
      if (!ok) {
        ref.read(appNotificationProvider.notifier).show(
              'Cannot send these items: the estimated bill would exceed the prepaid cap.',
              kind: AppNotificationKind.warning,
            );
        return false;
      }
    } else {
      final ok = ref
          .read(mockRestaurantOrdersProvider.notifier)
          .addBatch(orderId, batchRestaurant);
      if (!ok) {
        ref.read(appNotificationProvider.notifier).show(
              'Cannot send these items: the estimated bill would exceed the prepaid cap.',
              kind: AppNotificationKind.warning,
            );
        return false;
      }
    }

    state = [
      for (final x in state)
        if (x.id == reservationId) x.copyWith(preOrderItems: newPreOrder) else x,
    ];
    return true;
  }

  /// Creates restaurant order, updates table, marks reservation active.
  void activateToRestaurantOrder({
    required int reservationId,
    required int tableId,
    required String tableName,
    required WidgetRef ref,
    String waiter = 'Staff',
  }) {
    final r = state.firstWhere((x) => x.id == reservationId);
    final placed = buildRestaurantOrderFromReservation(
      r: r,
      tableId: tableId,
      tableName: tableName,
      waiter: waiter,
    );
    ref.read(mockRestaurantOrdersProvider.notifier).add(placed);
    final newId = ref.read(mockRestaurantOrdersProvider).first.id;

    final tables = ref.read(mockTablesProvider);
    final table = tables.firstWhere((t) => t.id == tableId);
    ref.read(mockTablesProvider.notifier).update(
          table.copyWith(
            status: 'occupied',
            activeOrderId: newId,
            guestCount: '${r.partySize}',
            occupiedSince:
                '${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}',
          ),
        );

    state = [
      for (final x in state)
        if (x.id == reservationId)
          x.copyWith(
            status: 'active',
            linkedOrderId: newId,
            assignedTableId: tableId,
            assignedTableName: tableName,
          )
        else
          x,
    ];
  }

  /// Creates hotel restaurant order, updates table, marks reservation active.
  void activateToHotelRestaurantOrder({
    required int reservationId,
    required int tableId,
    required String tableName,
    required WidgetRef ref,
    String waiter = 'Staff',
  }) {
    final r = state.firstWhere((x) => x.id == reservationId);
    final placed = buildHotelRestaurantOrderFromReservation(
      r: r,
      tableName: tableName,
      waiter: waiter,
    );
    final newId = ref.read(mockHotelRestaurantOrdersProvider.notifier).add(placed);

    final tables = ref.read(mockTablesProvider);
    final table = tables.firstWhere((t) => t.id == tableId);
    ref.read(mockTablesProvider.notifier).update(
          table.copyWith(
            status: 'occupied',
            activeOrderId: newId,
            guestCount: '${r.partySize}',
            occupiedSince:
                '${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}',
          ),
        );

    state = [
      for (final x in state)
        if (x.id == reservationId)
          x.copyWith(
            status: 'active',
            linkedOrderId: newId,
            assignedTableId: tableId,
            assignedTableName: tableName,
          )
        else
          x,
    ];
  }
}

final mockRestaurantReservationsProvider =
    StateNotifierProvider<DiningReservationsNotifier, List<MockDiningReservation>>(
  (ref) => DiningReservationsNotifier(List.from(_restaurantReservationsSeed)),
);

final mockHotelRestaurantReservationsProvider =
    StateNotifierProvider<DiningReservationsNotifier, List<MockDiningReservation>>(
  (ref) => DiningReservationsNotifier(List.from(_hotelRestaurantReservationsSeed)),
);
