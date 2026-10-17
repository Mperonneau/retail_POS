import 'package:flutter/material.dart';

/// What a change saved on this device will do once it reaches the server.
enum PendingOperationKind {
  sale,
  orderStatus,
  product,
  supplier,
  quote,
  stock,
  customer,
  customerAccount,
}

extension PendingOperationKindExt on PendingOperationKind {
  String get label => switch (this) {
        PendingOperationKind.sale => 'Vente',
        PendingOperationKind.orderStatus => 'Commande',
        PendingOperationKind.product => 'Produit',
        PendingOperationKind.supplier => 'Fournisseur',
        PendingOperationKind.quote => 'Devis',
        PendingOperationKind.stock => 'Stock',
        PendingOperationKind.customer => 'Client',
        PendingOperationKind.customerAccount => 'Compte client',
      };

  IconData get icon => switch (this) {
        PendingOperationKind.sale => Icons.receipt_long_outlined,
        PendingOperationKind.orderStatus => Icons.manage_search_outlined,
        PendingOperationKind.product => Icons.inventory_outlined,
        PendingOperationKind.supplier => Icons.local_shipping_outlined,
        PendingOperationKind.quote => Icons.request_quote_outlined,
        PendingOperationKind.stock => Icons.warehouse_outlined,
        PendingOperationKind.customer => Icons.people_outline,
        PendingOperationKind.customerAccount => Icons.account_balance_wallet_outlined,
      };
}

class PendingOperation {
  const PendingOperation({
    required this.id,
    required this.kind,
    required this.title,
    this.detail = '',
    this.orderId,
    this.amountHtg,
    required this.createdAt,
  });

  final String id;
  final PendingOperationKind kind;

  /// What changed, e.g. "Produit ajouté · Riz Blanc 25kg".
  final String title;
  final String detail;

  /// Set for sales and order updates so the queue can open the order.
  final String? orderId;
  final double? amountHtg;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'title': title,
        'detail': detail,
        'orderId': orderId,
        'amountHtg': amountHtg,
        'createdAt': createdAt.toIso8601String(),
      };

  static PendingOperation? fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString() ?? '';
    final kind = PendingOperationKind.values
        .where((k) => k.name == json['kind'])
        .firstOrNull;
    if (id.isEmpty || kind == null) return null;
    return PendingOperation(
      id: id,
      kind: kind,
      title: json['title']?.toString() ?? kind.label,
      detail: json['detail']?.toString() ?? '',
      orderId: json['orderId']?.toString(),
      amountHtg: (json['amountHtg'] as num?)?.toDouble(),
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}

/// Notifiers call this after a change; the device session keeps it only offline.
typedef PendingJournal = void Function(
  PendingOperationKind kind,
  String title, {
  String detail,
  String? orderId,
  double? amountHtg,
});
