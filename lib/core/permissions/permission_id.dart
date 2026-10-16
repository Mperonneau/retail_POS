/// Sample permission keys (expand later per module).
enum PermissionId {
  /// Open Settings (all tabs).
  settingsAccess,

  /// View module reports.
  reportsView,

  /// Menu / products / suppliers / inventory management.
  catalogManage,

  /// Tables, orders, POS, hotel rooms, check-in, etc.
  transactionsOperate,

  /// Cash drawer, reconciliation, payment-heavy screens.
  financialCash,
}

String permissionLabel(PermissionId id) {
  switch (id) {
    case PermissionId.settingsAccess:
      return 'Access Settings';
    case PermissionId.reportsView:
      return 'View reports';
    case PermissionId.catalogManage:
      return 'Manage catalog & stock';
    case PermissionId.transactionsOperate:
      return 'Operate transactions (orders, floor, rooms)';
    case PermissionId.financialCash:
      return 'Cash & payments';
  }
}
