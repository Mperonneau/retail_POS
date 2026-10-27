import 'package:flutter/foundation.dart';

import 'package:retail_pos/retail/models/sale_measure.dart';

import 'api.dart';

class CartLine {
  CartLine({
    required this.product,
    required this.choices,
    required this.quantity,
    this.measure = const MeasureChoice.plain(),
  });

  final Product product;
  final List<OptionChoice> choices;
  final MeasureChoice measure;
  int quantity;

  String get key =>
      '${product.id}|${measure.key}|${(choices.map((c) => c.id).toList()..sort()).join(',')}';

  double get unitHtg {
    final base = measure.baseHtg(
      priceHtg: product.priceHtg,
      rollPriceHtg: product.rollPriceHtg,
      casePriceHtg: product.casePriceHtg,
    );
    return base + choices.fold<double>(0, (s, c) => s + c.deltaHtg);
  }

  double get totalHtg => unitHtg * quantity;

  int get unitsEach => measure.unitsEach(
    rollWidth: product.rollWidth,
    unitsPerCase: product.unitsPerCase,
  );

  int get stockUnits => unitsEach * quantity;

  String get optionsLabel {
    final parts = <String>[
      if (measure.label(unitsPerCase: product.unitsPerCase).isNotEmpty)
        measure.label(unitsPerCase: product.unitsPerCase),
      ...choices.map((c) => c.name),
    ];
    return parts.join(', ');
  }
}

/// One shared cart. Totals are indicative; the server reprices.
class Cart extends ChangeNotifier {
  final List<CartLine> lines = [];
  String? shopSlug;
  String shopName = '';
  double usdRate = 135;

  void bindShop(String slug, String name, double rate) {
    if (shopSlug != null && shopSlug != slug && lines.isNotEmpty) {
      lines.clear();
    }
    shopSlug = slug;
    shopName = name;
    usdRate = rate;
    notifyListeners();
  }

  int get count => lines.fold(0, (s, l) => s + l.quantity);

  double get totalHtg => lines.fold(0, (s, l) => s + l.totalHtg);

  bool get isEmpty => lines.isEmpty;

  int quantityOf(String productId) =>
      lines.where((l) => l.product.id == productId).fold(0, (s, l) => s + l.quantity);

  int stockUsed(String productId) => lines
      .where((l) => l.product.id == productId)
      .fold(0, (sum, line) => sum + line.stockUnits);

  /// False when the stock limit would be passed.
  bool add(
    Product product,
    List<OptionChoice> choices,
    int quantity, {
    MeasureChoice measure = const MeasureChoice.plain(),
  }) {
    final line = CartLine(
      product: product,
      choices: choices,
      quantity: quantity,
      measure: measure,
    );
    if (!_fits(line)) return false;
    final existing = lines.where((l) => l.key == line.key).firstOrNull;
    if (existing != null) {
      existing.quantity += quantity;
    } else {
      lines.add(line);
    }
    notifyListeners();
    return true;
  }

  bool _fits(CartLine incoming) {
    if (!incoming.product.trackStock) {
      return quantityOf(incoming.product.id) + incoming.quantity <=
          incoming.product.maxQuantity;
    }
    return stockUsed(incoming.product.id) + incoming.stockUnits <= incoming.product.stock;
  }

  bool increment(CartLine line) {
    final probe = CartLine(
      product: line.product,
      choices: line.choices,
      quantity: 1,
      measure: line.measure,
    );
    if (!_fits(probe)) return false;
    line.quantity += 1;
    notifyListeners();
    return true;
  }

  void decrement(CartLine line) {
    line.quantity -= 1;
    if (line.quantity <= 0) lines.remove(line);
    notifyListeners();
  }

  void remove(CartLine line) {
    lines.remove(line);
    notifyListeners();
  }

  void clear() {
    lines.clear();
    notifyListeners();
  }

  List<Map<String, dynamic>> toPayload() => [
        for (final l in lines)
          {
            'product_id': l.product.id,
            'quantity': l.quantity,
            'choices': [for (final c in l.choices) c.id],
            if (l.measure.wire.isNotEmpty) 'measure': l.measure.wire,
            if (l.measure.kind == MeasureKind.width) 'width': l.measure.width,
          },
      ];
}

/// Cart shared by the shop, the top bar and the cart page.
final appCart = Cart();
