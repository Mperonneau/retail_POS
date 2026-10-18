import '../../core/mock/mock_retail_data.dart';
import 'product_option.dart';

/// Line item for retail POS / checkout (shared with [RetailCheckoutWizard]).
class RetailCartEntry {
  final MockProduct product;
  int quantity;
  final List<ProductOptionChoice> options;

  RetailCartEntry({
    required this.product,
    this.quantity = 1,
    this.options = const [],
  });

  static String lineKeyFor(int productId, List<ProductOptionChoice> options) {
    final ids = options.map((o) => o.id).toList()..sort();
    return '$productId|${ids.join(',')}';
  }

  String get lineKey => lineKeyFor(product.id, options);

  String get lineLabel {
    if (options.isEmpty) return product.name;
    return '${product.name} · ${options.map((o) => o.name).join(', ')}';
  }

  /// Discounted catalog price plus the chosen option extras.
  double get unitPriceHtg {
    final extra = options.fold<double>(0, (sum, o) => sum + o.priceDeltaHtg);
    return product.sellingPriceHtg + extra;
  }
}
