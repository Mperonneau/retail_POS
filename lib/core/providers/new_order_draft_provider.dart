import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Draft context for composing a new order before it exists in the system.
/// Cleared after submit, bill & pay, or cancel.
class NewOrderDraft {
  /// dine_in | takeout | delivery | room_service (hotel only)
  final String orderType;
  final int? tableId;
  /// Display name e.g. "Table 3"
  final String tableName;
  final String? customerName;
  final String? deliveryAddress;
  /// Required when [orderType] == delivery
  final String? customerPhone;
  final String? roomNumber;

  const NewOrderDraft({
    required this.orderType,
    this.tableId,
    this.tableName = '',
    this.customerName,
    this.deliveryAddress,
    this.customerPhone,
    this.roomNumber,
  });

  NewOrderDraft copyWith({
    String? orderType,
    int? tableId,
    String? tableName,
    Object? customerName = _s,
    Object? deliveryAddress = _s,
    Object? customerPhone = _s,
    Object? roomNumber = _s,
  }) {
    return NewOrderDraft(
      orderType: orderType ?? this.orderType,
      tableId: tableId ?? this.tableId,
      tableName: tableName ?? this.tableName,
      customerName: customerName == _s ? this.customerName : customerName as String?,
      deliveryAddress: deliveryAddress == _s ? this.deliveryAddress : deliveryAddress as String?,
      customerPhone: customerPhone == _s ? this.customerPhone : customerPhone as String?,
      roomNumber: roomNumber == _s ? this.roomNumber : roomNumber as String?,
    );
  }

  static const _s = Object();
}

final newOrderDraftProvider =
    StateProvider<NewOrderDraft?>((ref) => null);
