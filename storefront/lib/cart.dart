import 'package:flutter/foundation.dart';

import 'api.dart';

class CartLine {
  CartLine({required this.product, required this.choices, required this.quantity});

  final Product product;
  final List<OptionChoice> choices;
  int quantity;

  String get key => '${product.id}|${(choices.map((c) => c.id).toList()..sort()).join(',')}';

  double get unitHtg => product.priceHtg + choices.fold<double>(0, (s, c) => s + c.deltaHtg);

  double get totalHtg => unitHtg * quantity;

  String get optionsLabel => choices.map((c) => c.name).join(', ');
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

  /// False when the stock limit would be passed.
  bool add(Product product, List<OptionChoice> choices, int quantity) {
    if (quantityOf(product.id) + quantity > product.maxQuantity) return false;
    final line = CartLine(product: product, choices: choices, quantity: quantity);
    final existing = lines.where((l) => l.key == line.key).firstOrNull;
    if (existing != null) {
      existing.quantity += quantity;
    } else {
      lines.add(line);
    }
    notifyListeners();
    return true;
  }

  bool increment(CartLine line) {
    if (quantityOf(line.product.id) + 1 > line.product.maxQuantity) return false;
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
          },
      ];
}

/// Cart shared by the shop, the top bar and the cart page.
final appCart = Cart();
