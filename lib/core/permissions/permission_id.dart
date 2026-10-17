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
      return 'Accéder aux paramètres';
    case PermissionId.reportsView:
      return 'Voir les rapports';
    case PermissionId.catalogManage:
      return 'Gérer le catalogue et le stock';
    case PermissionId.transactionsOperate:
      return 'Encaisser (commandes, salle, chambres)';
    case PermissionId.financialCash:
      return 'Caisse et paiements';
  }
}
