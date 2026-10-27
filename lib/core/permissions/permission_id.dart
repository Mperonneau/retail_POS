import '../providers/auth_provider.dart';

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

  /// Put a sale balance on a client's credit account.
  clientCreditGrant,
}

String permissionLabel(PermissionId id, {ActiveModule? module}) {
  final retail = module == ActiveModule.retail;
  switch (id) {
    case PermissionId.settingsAccess:
      return 'Accéder aux paramètres';
    case PermissionId.reportsView:
      return 'Voir les rapports';
    case PermissionId.catalogManage:
      return retail
          ? 'Gérer les produits et le stock'
          : 'Gérer le catalogue et le stock';
    case PermissionId.transactionsOperate:
      return retail
          ? 'Vendre (caisse, commandes, devis)'
          : 'Encaisser (commandes, salle, chambres)';
    case PermissionId.financialCash:
      return 'Caisse et paiements';
    case PermissionId.clientCreditGrant:
      return 'Accorder un crédit à un client';
  }
}
