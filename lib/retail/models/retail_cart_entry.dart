import '../../core/mock/mock_retail_data.dart';
import 'product_option.dart';
import 'sale_measure.dart';

/// Line item for retail POS / checkout (shared with [RetailCheckoutWizard]).
class RetailCartEntry {
  final MockProduct product;
  int quantity;
  final List<ProductOptionChoice> options;
  final MeasureChoice measure;

  RetailCartEntry({
    required this.product,
    this.quantity = 1,
    this.options = const [],
    this.measure = const MeasureChoice.plain(),
  });

  static String lineKeyFor(
    int productId,
    List<ProductOptionChoice> options, [
    MeasureChoice measure = const MeasureChoice.plain(),
  ]) {
    final ids = options.map((o) => o.id).toList()..sort();
    return '$productId|${measure.key}|${ids.join(',')}';
  }

  String get lineKey => lineKeyFor(product.id, options, measure);

  String get detailLabel {
    final parts = <String>[
      if (product.labelFor(measure).isNotEmpty) product.labelFor(measure),
      ...options.map((o) => o.name),
    ];
    return parts.join(', ');
  }

  String get lineLabel {
    if (detailLabel.isEmpty) return product.name;
    return '${product.name} · $detailLabel';
  }

  /// Discounted catalogue price for this choice, plus option extras.
  double get unitPriceHtg {
    final extra = options.fold<double>(0, (sum, o) => sum + o.priceDeltaHtg);
    return product.priceFor(measure) + extra;
  }

  /// Inches or units this line takes from stock.
  int get stockUnits => product.unitsEach(measure) * quantity;
}
