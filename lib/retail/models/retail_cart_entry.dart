import '../../core/mock/mock_retail_data.dart';

/// Line item for retail POS / checkout (shared with [RetailCheckoutWizard]).
class RetailCartEntry {
  final MockProduct product;
  int quantity;

  RetailCartEntry({required this.product, this.quantity = 1});
}
