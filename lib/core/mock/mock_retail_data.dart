import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/pending_operation.dart';
import '../models/retail_fulfillment_mode.dart';
import '../providers/device_session_provider.dart';
import '../../retail/models/product_option.dart';
import '../../retail/models/sale_measure.dart';

class MockProduct {
  final int id;
  final String name;
  final String category;
  final double priceHtg;
  final double priceUsd;
  final double costHtg;
  final int stockQuantity;
  final int minStock;
  final String? barcode;
  final bool active;
  final String description;

  /// Data URL kept for the future storefront. Not shown at the register.
  final String? photoDataUrl;

  /// Percent off [priceHtg]. 0 means no product discount.
  final int discountPercent;

  /// When false, sales do not decrement [stockQuantity].
  final bool trackStock;
  final String stockUnit;
  final List<ProductOptionGroup> options;

  /// Listed on the online vitrine when the product is also [active].
  final bool showOnStorefront;

  /// [priceHtg] is the piece price, the price per inch, or the unit price.
  final SaleMode saleMode;

  /// Price of one full roll. Stock for a roll is kept in inches.
  final double rollPriceHtg;
  final double rollPriceUsd;
  final int minWidth;
  final int rollWidth;

  /// When true, a custom length cannot pass [rollWidth].
  final bool limitLength;

  /// Price of one case. Stock for a case product is kept in units.
  final double casePriceHtg;
  final double casePriceUsd;
  final int unitsPerCase;

  const MockProduct({
    required this.id,
    required this.name,
    required this.category,
    required this.priceHtg,
    required this.priceUsd,
    required this.costHtg,
    required this.stockQuantity,
    required this.minStock,
    this.barcode,
    this.active = true,
    this.description = '',
    this.photoDataUrl,
    this.discountPercent = 0,
    this.trackStock = true,
    this.stockUnit = 'u',
    this.options = const [],
    this.showOnStorefront = true,
    this.saleMode = SaleMode.piece,
    this.rollPriceHtg = 0,
    this.rollPriceUsd = 0,
    this.minWidth = 0,
    this.rollWidth = 0,
    this.limitLength = false,
    this.casePriceHtg = 0,
    this.casePriceUsd = 0,
    this.unitsPerCase = 0,
  });

  bool get isLowStock => trackStock && stockQuantity <= minStock;

  double _discounted(double amount) {
    final pct = discountPercent.clamp(0, 100);
    if (pct == 0) return amount;
    return amount * (100 - pct) / 100;
  }

  /// Catalog price after the product discount. Option extras are added later.
  double get sellingPriceHtg => _discounted(priceHtg);

  double get sellingPriceUsd => _discounted(priceUsd);

  double get sellingRollPriceHtg => _discounted(rollPriceHtg);

  double get sellingCasePriceHtg => _discounted(casePriceHtg);

  /// Short cue on a product card. Empty for a flat price.
  String get saleHint => switch (saleMode) {
    SaleMode.piece => '',
    SaleMode.roll => 'Longueur entière ou une longueur',
    SaleMode.pack => 'Caisse ou unité',
  };

  /// Appended to the catalogue amount: " / po" or " / u.".
  String get priceUnitSuffix => switch (saleMode) {
    SaleMode.piece => '',
    SaleMode.roll => ' / po',
    SaleMode.pack => ' / u.',
  };

  /// Inches a custom length may not pass. Zero means a longer cut is allowed.
  int get lengthCap =>
      saleMode == SaleMode.roll && limitLength && rollWidth >= 1
      ? rollWidth
      : 0;

  int unitsEach(MeasureChoice choice) =>
      choice.unitsEach(rollWidth: rollWidth, unitsPerCase: unitsPerCase);

  double priceFor(MeasureChoice choice) => choice.baseHtg(
    priceHtg: sellingPriceHtg,
    rollPriceHtg: sellingRollPriceHtg,
    casePriceHtg: sellingCasePriceHtg,
  );

  String labelFor(MeasureChoice choice) =>
      choice.label(unitsPerCase: unitsPerCase);

  double get margin =>
      priceHtg == 0 ? 0 : ((priceHtg - costHtg) / priceHtg) * 100;

  MockProduct copyWith({
    int? id,
    String? name,
    String? category,
    double? priceHtg,
    double? priceUsd,
    double? costHtg,
    int? stockQuantity,
    int? minStock,
    Object? barcode = _sentinel,
    bool? active,
    String? description,
    Object? photoDataUrl = _sentinel,
    int? discountPercent,
    bool? trackStock,
    String? stockUnit,
    List<ProductOptionGroup>? options,
    bool? showOnStorefront,
    SaleMode? saleMode,
    double? rollPriceHtg,
    double? rollPriceUsd,
    int? minWidth,
    int? rollWidth,
    bool? limitLength,
    double? casePriceHtg,
    double? casePriceUsd,
    int? unitsPerCase,
  }) {
    return MockProduct(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      priceHtg: priceHtg ?? this.priceHtg,
      priceUsd: priceUsd ?? this.priceUsd,
      costHtg: costHtg ?? this.costHtg,
      stockQuantity: stockQuantity ?? this.stockQuantity,
      minStock: minStock ?? this.minStock,
      barcode: barcode == _sentinel ? this.barcode : barcode as String?,
      active: active ?? this.active,
      description: description ?? this.description,
      photoDataUrl: photoDataUrl == _sentinel
          ? this.photoDataUrl
          : photoDataUrl as String?,
      discountPercent: discountPercent ?? this.discountPercent,
      trackStock: trackStock ?? this.trackStock,
      stockUnit: stockUnit ?? this.stockUnit,
      options: options ?? this.options,
      showOnStorefront: showOnStorefront ?? this.showOnStorefront,
      saleMode: saleMode ?? this.saleMode,
      rollPriceHtg: rollPriceHtg ?? this.rollPriceHtg,
      rollPriceUsd: rollPriceUsd ?? this.rollPriceUsd,
      minWidth: minWidth ?? this.minWidth,
      rollWidth: rollWidth ?? this.rollWidth,
      limitLength: limitLength ?? this.limitLength,
      casePriceHtg: casePriceHtg ?? this.casePriceHtg,
      casePriceUsd: casePriceUsd ?? this.casePriceUsd,
      unitsPerCase: unitsPerCase ?? this.unitsPerCase,
    );
  }
}

class MockCustomer {
  final int id;
  final String name;
  final String phone;
  final double creditLimit;
  final double outstandingBalance;
  final int totalPurchases;
  final double totalSpentHtg;

  const MockCustomer({
    required this.id,
    required this.name,
    required this.phone,
    required this.creditLimit,
    required this.outstandingBalance,
    required this.totalPurchases,
    required this.totalSpentHtg,
  });
}

class MockSale {
  final int id;
  final DateTime date;
  final String cashier;
  final List<MockSaleItem> items;
  final String paymentMethod;
  final String? customerName;

  const MockSale({
    required this.id,
    required this.date,
    required this.cashier,
    required this.items,
    required this.paymentMethod,
    this.customerName,
  });

  double get totalHtg => items.fold(0, (s, i) => s + (i.priceHtg * i.quantity));
}

class MockSaleItem {
  final String name;
  final int quantity;
  final double priceHtg;

  const MockSaleItem({
    required this.name,
    required this.quantity,
    required this.priceHtg,
  });
}

class MockSupplierContact {
  final String id;
  final String name;
  final String title;
  final String phone;
  final String email;

  const MockSupplierContact({
    required this.id,
    required this.name,
    this.title = '',
    this.phone = '',
    this.email = '',
  });

  MockSupplierContact copyWith({
    String? id,
    String? name,
    String? title,
    String? phone,
    String? email,
  }) {
    return MockSupplierContact(
      id: id ?? this.id,
      name: name ?? this.name,
      title: title ?? this.title,
      phone: phone ?? this.phone,
      email: email ?? this.email,
    );
  }
}

class MockSupplier {
  final int id;
  final String name;
  final String phone;
  final String email;
  final String location;
  final String note;
  final List<String> categories;
  final List<MockSupplierContact> contacts;

  const MockSupplier({
    required this.id,
    required this.name,
    this.phone = '',
    this.email = '',
    this.location = '',
    this.note = '',
    this.categories = const [],
    this.contacts = const [],
  });

  MockSupplier copyWith({
    int? id,
    String? name,
    String? phone,
    String? email,
    String? location,
    String? note,
    List<String>? categories,
    List<MockSupplierContact>? contacts,
  }) {
    return MockSupplier(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      location: location ?? this.location,
      note: note ?? this.note,
      categories: categories ?? this.categories,
      contacts: contacts ?? this.contacts,
    );
  }
}

// ──────────────── MOCK DATA ────────────────

final _mockProductsSeed = [
  MockProduct(
    id: 1,
    name: 'Riz Blanc 25kg',
    category: 'Alimentation',
    priceHtg: 3200,
    priceUsd: 32,
    costHtg: 2400,
    stockQuantity: 18,
    minStock: 5,
  ),
  MockProduct(
    id: 2,
    name: 'Huile Végétale 1L',
    category: 'Alimentation',
    priceHtg: 600,
    priceUsd: 6,
    costHtg: 420,
    stockQuantity: 45,
    minStock: 20,
  ),
  MockProduct(
    id: 3,
    name: 'Sucre 5kg',
    category: 'Alimentation',
    priceHtg: 800,
    priceUsd: 8,
    costHtg: 600,
    stockQuantity: 8,
    minStock: 10,
  ),
  MockProduct(
    id: 4,
    name: 'Farine de Blé 5kg',
    category: 'Alimentation',
    priceHtg: 700,
    priceUsd: 7,
    costHtg: 520,
    stockQuantity: 12,
    minStock: 8,
  ),
  MockProduct(
    id: 5,
    name: 'Prestige Beer 330ml',
    category: 'Boissons',
    priceHtg: 180,
    priceUsd: 1.80,
    costHtg: 110,
    stockQuantity: 144,
    minStock: 48,
  ),
  MockProduct(
    id: 6,
    name: 'Coca-Cola 355ml',
    category: 'Boissons',
    priceHtg: 120,
    priceUsd: 1.20,
    costHtg: 75,
    stockQuantity: 3,
    minStock: 24,
  ),
  MockProduct(
    id: 7,
    name: 'Eau Culligan 18L',
    category: 'Boissons',
    priceHtg: 280,
    priceUsd: 2.80,
    costHtg: 180,
    stockQuantity: 20,
    minStock: 10,
  ),
  MockProduct(
    id: 8,
    name: 'Savon Dettol 100g',
    category: 'Ménage',
    priceHtg: 150,
    priceUsd: 1.50,
    costHtg: 90,
    stockQuantity: 60,
    minStock: 20,
  ),
  MockProduct(
    id: 9,
    name: 'Lessive Ariel 1kg',
    category: 'Ménage',
    priceHtg: 450,
    priceUsd: 4.50,
    costHtg: 320,
    stockQuantity: 22,
    minStock: 10,
  ),
  MockProduct(
    id: 10,
    name: 'Bougies (paquet 10)',
    category: 'Ménage',
    priceHtg: 200,
    priceUsd: 2,
    costHtg: 120,
    stockQuantity: 4,
    minStock: 15,
  ),
  MockProduct(
    id: 11,
    name: 'Ampoule LED 9W',
    category: 'Électronique',
    priceHtg: 350,
    priceUsd: 3.50,
    costHtg: 200,
    stockQuantity: 30,
    minStock: 10,
  ),
  MockProduct(
    id: 12,
    name: 'Chargeur USB-C',
    category: 'Électronique',
    priceHtg: 800,
    priceUsd: 8,
    costHtg: 500,
    stockQuantity: 15,
    minStock: 5,
  ),
  MockProduct(
    id: 13,
    name: 'Shampoo Pantene 400ml',
    category: 'Hygiène',
    priceHtg: 600,
    priceUsd: 6,
    costHtg: 420,
    stockQuantity: 18,
    minStock: 8,
  ),
  MockProduct(
    id: 14,
    name: 'Dentifrice Colgate 75ml',
    category: 'Hygiène',
    priceHtg: 180,
    priceUsd: 1.80,
    costHtg: 110,
    stockQuantity: 40,
    minStock: 15,
  ),
  MockProduct(
    id: 15,
    name: 'Cahier 100 pages',
    category: 'Papeterie',
    priceHtg: 150,
    priceUsd: 1.50,
    costHtg: 90,
    stockQuantity: 50,
    minStock: 20,
  ),
  MockProduct(
    id: 16,
    name: 'Allumettes (boîte)',
    category: 'Ménage',
    priceHtg: 35,
    priceUsd: 0.35,
    costHtg: 18,
    stockQuantity: 24,
    minStock: 12,
  ),
  MockProduct(
    id: 17,
    name: 'Balai en plastique',
    category: 'Ménage',
    priceHtg: 220,
    priceUsd: 2.20,
    costHtg: 140,
    stockQuantity: 14,
    minStock: 6,
  ),
  MockProduct(
    id: 18,
    name: 'Banane plantain (kg)',
    category: 'Alimentation',
    priceHtg: 95,
    priceUsd: 0.95,
    costHtg: 60,
    stockQuantity: 40,
    minStock: 15,
  ),
  MockProduct(
    id: 19,
    name: 'Bouteille gaz 12kg',
    category: 'Ménage',
    priceHtg: 4500,
    priceUsd: 45,
    costHtg: 3200,
    stockQuantity: 6,
    minStock: 3,
  ),
  MockProduct(
    id: 20,
    name: 'Brosse à dents',
    category: 'Hygiène',
    priceHtg: 85,
    priceUsd: 0.85,
    costHtg: 50,
    stockQuantity: 72,
    minStock: 24,
  ),
  MockProduct(
    id: 21,
    name: 'Câble HDMI 2m',
    category: 'Électronique',
    priceHtg: 650,
    priceUsd: 6.50,
    costHtg: 400,
    stockQuantity: 11,
    minStock: 4,
  ),
  MockProduct(
    id: 22,
    name: 'Cassonade 1kg',
    category: 'Alimentation',
    priceHtg: 320,
    priceUsd: 3.20,
    costHtg: 210,
    stockQuantity: 28,
    minStock: 10,
  ),
  MockProduct(
    id: 23,
    name: 'Coton hydrophile',
    category: 'Hygiène',
    priceHtg: 120,
    priceUsd: 1.20,
    costHtg: 75,
    stockQuantity: 33,
    minStock: 12,
  ),
  MockProduct(
    id: 24,
    name: 'Couche bébé (paquet)',
    category: 'Hygiène',
    priceHtg: 950,
    priceUsd: 9.50,
    costHtg: 700,
    stockQuantity: 9,
    minStock: 5,
  ),
  MockProduct(
    id: 25,
    name: 'Crackers salés',
    category: 'Alimentation',
    priceHtg: 180,
    priceUsd: 1.80,
    costHtg: 110,
    stockQuantity: 52,
    minStock: 20,
  ),
  MockProduct(
    id: 26,
    name: 'Détergent vaisselle 750ml',
    category: 'Ménage',
    priceHtg: 280,
    priceUsd: 2.80,
    costHtg: 180,
    stockQuantity: 20,
    minStock: 8,
  ),
  MockProduct(
    id: 27,
    name: 'Enveloppes (paquet 50)',
    category: 'Papeterie',
    priceHtg: 200,
    priceUsd: 2,
    costHtg: 120,
    stockQuantity: 16,
    minStock: 6,
  ),
  MockProduct(
    id: 28,
    name: 'Extension multiprise 6 prises',
    category: 'Électronique',
    priceHtg: 1200,
    priceUsd: 12,
    costHtg: 750,
    stockQuantity: 8,
    minStock: 3,
  ),
  MockProduct(
    id: 29,
    name: 'Gel douche 1L',
    category: 'Hygiène',
    priceHtg: 420,
    priceUsd: 4.20,
    costHtg: 280,
    stockQuantity: 19,
    minStock: 8,
  ),
  MockProduct(
    id: 30,
    name: 'Jus tropical 1L',
    category: 'Boissons',
    priceHtg: 150,
    priceUsd: 1.50,
    costHtg: 95,
    stockQuantity: 48,
    minStock: 18,
  ),
  MockProduct(
    id: 31,
    name: 'Lait en poudre 400g',
    category: 'Alimentation',
    priceHtg: 480,
    priceUsd: 4.80,
    costHtg: 320,
    stockQuantity: 15,
    minStock: 6,
  ),
  MockProduct(
    id: 32,
    name: 'Lait en poudre 800g',
    category: 'Alimentation',
    priceHtg: 880,
    priceUsd: 8.80,
    costHtg: 600,
    stockQuantity: 10,
    minStock: 4,
  ),
  MockProduct(
    id: 33,
    name: 'Lampe torche LED',
    category: 'Électronique',
    priceHtg: 450,
    priceUsd: 4.50,
    costHtg: 280,
    stockQuantity: 13,
    minStock: 5,
  ),
  MockProduct(
    id: 34,
    name: 'Règle 30cm',
    category: 'Papeterie',
    priceHtg: 75,
    priceUsd: 0.75,
    costHtg: 45,
    stockQuantity: 64,
    minStock: 20,
  ),
  MockProduct(
    id: 35,
    name: 'Stylo bleu (boîte 12)',
    category: 'Papeterie',
    priceHtg: 240,
    priceUsd: 2.40,
    costHtg: 150,
    stockQuantity: 22,
    minStock: 10,
  ),
  // Roll: priceHtg is per inch. The full roll has its own price. Stock is inches.
  MockProduct(
    id: 36,
    name: 'Rouleau de tissu coton',
    category: 'Quincaillerie',
    priceHtg: 15,
    priceUsd: 0.15,
    costHtg: 8,
    stockQuantity: 180,
    minStock: 60,
    description:
        'Vendu à la longueur entière (60 po) ou à la longueur choisie. '
        'Minimum 12 pouces. La longueur entière a son propre prix.',
    saleMode: SaleMode.roll,
    rollPriceHtg: 750,
    rollPriceUsd: 7.50,
    minWidth: 12,
    rollWidth: 60,
  ),
  MockProduct(
    id: 37,
    name: 'Rouleau de ruban adhésif',
    category: 'Quincaillerie',
    priceHtg: 8,
    priceUsd: 0.08,
    costHtg: 4,
    stockQuantity: 108,
    minStock: 36,
    description:
        'Vendu à la longueur entière (36 po) ou à la longueur choisie. '
        'Minimum 6 pouces.',
    saleMode: SaleMode.roll,
    rollPriceHtg: 250,
    rollPriceUsd: 2.50,
    minWidth: 6,
    rollWidth: 36,
  ),
  // Case: priceHtg is one unit. The case has its own price. Stock is units.
  MockProduct(
    id: 38,
    name: "Caisse d'eau 500 ml",
    category: 'Boissons',
    priceHtg: 40,
    priceUsd: 0.40,
    costHtg: 25,
    stockQuantity: 72,
    minStock: 24,
    description:
        'Une caisse contient 24 bouteilles à un prix de caisse. '
        "Une bouteille seule a son propre prix.",
    saleMode: SaleMode.pack,
    casePriceHtg: 800,
    casePriceUsd: 8,
    unitsPerCase: 24,
  ),
  MockProduct(
    id: 39,
    name: 'Caisse de savon 100 g',
    category: 'Ménage',
    priceHtg: 85,
    priceUsd: 0.85,
    costHtg: 50,
    stockQuantity: 48,
    minStock: 12,
    description:
        'Une caisse contient 12 savons à un prix de caisse. '
        "Un savon seul a son propre prix.",
    saleMode: SaleMode.pack,
    casePriceHtg: 900,
    casePriceUsd: 9,
    unitsPerCase: 12,
  ),
];

final mockCustomers = [
  MockCustomer(
    id: 1,
    name: 'Boutique Madame Pierre',
    phone: '+509 3456-7890',
    creditLimit: 50000,
    outstandingBalance: 12500,
    totalPurchases: 45,
    totalSpentHtg: 380000,
  ),
  MockCustomer(
    id: 2,
    name: 'Restaurant Ti Kay',
    phone: '+509 4123-5678',
    creditLimit: 30000,
    outstandingBalance: 8200,
    totalPurchases: 28,
    totalSpentHtg: 245000,
  ),
  MockCustomer(
    id: 3,
    name: 'Jean-Baptiste Michel',
    phone: '+509 3789-0123',
    creditLimit: 15000,
    outstandingBalance: 0,
    totalPurchases: 12,
    totalSpentHtg: 45000,
  ),
  MockCustomer(
    id: 4,
    name: 'École Nationale No.3',
    phone: '+509 2222-3333',
    creditLimit: 80000,
    outstandingBalance: 32000,
    totalPurchases: 60,
    totalSpentHtg: 720000,
  ),
  MockCustomer(
    id: 5,
    name: 'Hôtel Roi Christophe',
    phone: '+509 3600-0000',
    creditLimit: 200000,
    outstandingBalance: 45000,
    totalPurchases: 150,
    totalSpentHtg: 2800000,
  ),
];

final mockSales = [
  MockSale(
    id: 1,
    date: DateTime.now().subtract(const Duration(minutes: 10)),
    cashier: 'Roseline',
    items: const [
      MockSaleItem(name: 'Riz Blanc 25kg', quantity: 2, priceHtg: 3200),
      MockSaleItem(name: 'Huile Végétale 1L', quantity: 3, priceHtg: 600),
    ],
    paymentMethod: 'MonCash',
  ),
  MockSale(
    id: 2,
    date: DateTime.now().subtract(const Duration(minutes: 25)),
    cashier: 'Roseline',
    items: const [
      MockSaleItem(name: 'Prestige Beer 330ml', quantity: 12, priceHtg: 180),
      MockSaleItem(name: 'Coca-Cola 355ml', quantity: 6, priceHtg: 120),
    ],
    paymentMethod: 'Espèces',
    customerName: 'Restaurant Ti Kay',
  ),
  MockSale(
    id: 3,
    date: DateTime.now().subtract(const Duration(hours: 1)),
    cashier: 'Marcel',
    items: const [
      MockSaleItem(name: 'Savon Dettol 100g', quantity: 5, priceHtg: 150),
      MockSaleItem(name: 'Dentifrice Colgate', quantity: 2, priceHtg: 180),
      MockSaleItem(name: 'Shampoo Pantene', quantity: 1, priceHtg: 600),
    ],
    paymentMethod: 'Espèces',
  ),
  MockSale(
    id: 4,
    date: DateTime.now().subtract(const Duration(hours: 2)),
    cashier: 'Roseline',
    items: const [
      MockSaleItem(name: 'Ampoule LED 9W', quantity: 4, priceHtg: 350),
      MockSaleItem(name: 'Bougies (paquet 10)', quantity: 2, priceHtg: 200),
    ],
    paymentMethod: 'Stripe',
  ),
  MockSale(
    id: 5,
    date: DateTime.now().subtract(const Duration(hours: 3)),
    cashier: 'Marcel',
    items: const [
      MockSaleItem(name: 'Farine de Blé 5kg', quantity: 1, priceHtg: 700),
      MockSaleItem(name: 'Sucre 5kg', quantity: 1, priceHtg: 800),
      MockSaleItem(name: 'Huile Végétale 1L', quantity: 2, priceHtg: 600),
    ],
    paymentMethod: 'MonCash',
  ),
];

final _mockSuppliersSeed = [
  MockSupplier(
    id: 1,
    name: 'DINASA (Riz & Farine)',
    phone: '+509 2940-0000',
    email: 'commandes@dinasa.ht',
    location: 'Zone Industrielle, Port-au-Prince',
    note:
        'Principal fournisseur de riz et farine. Livraison le mardi et vendredi. Minimum de commande 5 sacs.',
    categories: ['Alimentation', 'Importation'],
    contacts: [
      MockSupplierContact(
        id: 'c1_1',
        name: 'Paul Dominique',
        title: 'Représentant commercial',
        phone: '+509 2940-0000',
        email: 'paul.d@dinasa.ht',
      ),
      MockSupplierContact(
        id: 'c1_2',
        name: 'Marie Céline',
        title: 'Comptabilité',
        phone: '+509 2940-0001',
        email: 'mceline@dinasa.ht',
      ),
    ],
  ),
  MockSupplier(
    id: 2,
    name: 'Brasserie Nationale (Prestige)',
    phone: '+509 2940-1234',
    email: 'ventes@brassnat.ht',
    location: 'Delmas 33, Route de l\'Aéroport',
    note: 'Commandes minimum 24 bouteilles par référence. Paiement à 30 jours.',
    categories: ['Boissons'],
    contacts: [
      MockSupplierContact(
        id: 'c2_1',
        name: 'Carole Simone',
        title: 'Directrice des ventes',
        phone: '+509 2940-1234',
        email: 'carole.s@brassnat.ht',
      ),
      MockSupplierContact(
        id: 'c2_2',
        name: 'Robert Estimé',
        title: 'Livreur',
        phone: '+509 3456-1111',
        email: '',
      ),
    ],
  ),
  MockSupplier(
    id: 3,
    name: 'Importex Haïti',
    phone: '+509 2811-5678',
    email: 'import@importex.ht',
    location: 'Croix-des-Bouquets, Boulevard Toussaint Louverture',
    note:
        'Grossiste général. Délai de livraison 3-5 jours ouvrables. Catalogue sur demande.',
    categories: ['Alimentation', 'Ménage', 'Hygiène'],
    contacts: [
      MockSupplierContact(
        id: 'c3_1',
        name: 'Henri Rémy',
        title: 'Gérant',
        phone: '+509 2811-5678',
        email: 'hremy@importex.ht',
      ),
      MockSupplierContact(
        id: 'c3_2',
        name: 'Sandra Fils-Aimé',
        title: 'Logistique',
        phone: '+509 2811-5679',
        email: 'sfilsaime@importex.ht',
      ),
    ],
  ),
  MockSupplier(
    id: 4,
    name: 'Caribbean Electric Supply',
    phone: '+509 3456-7890',
    email: 'info@caribelec.ht',
    location: 'Pétion-Ville, Rue Grégoire 45',
    note:
        'Ampoules, câbles et équipements électroniques. Garantie 3 mois sur produits défectueux.',
    categories: ['Électronique'],
    contacts: [
      MockSupplierContact(
        id: 'c4_1',
        name: 'Jean-Pierre Lafleur',
        title: 'Propriétaire',
        phone: '+509 3456-7890',
        email: 'jplafleur@caribelec.ht',
      ),
    ],
  ),
  MockSupplier(
    id: 5,
    name: 'Pharma Distribution Haïti',
    phone: '+509 2812-0000',
    email: 'commandes@pharmaht.ht',
    location: 'Turgeau, Rue Capois 12',
    note:
        'Hygiène et soins. Numéro de licence requis pour les commandes. Délai 48h.',
    categories: ['Hygiène', 'Santé'],
    contacts: [
      MockSupplierContact(
        id: 'c5_1',
        name: 'Dr. Claudette Morin',
        title: 'Directrice',
        phone: '+509 2812-0000',
        email: 'cmorin@pharmaht.ht',
      ),
      MockSupplierContact(
        id: 'c5_2',
        name: 'Réginald Casimir',
        title: 'Représentant',
        phone: '+509 3900-1212',
        email: '',
      ),
    ],
  ),
  MockSupplier(
    id: 6,
    name: 'Papeterie Nationale',
    phone: '+509 2234-5678',
    email: 'lydie@papnat.ht',
    location: 'Port-au-Prince, Rue du Centre',
    note:
        'Fournitures de bureau et scolaires. Remise 10% sur commandes supérieures à 50 unités.',
    categories: ['Papeterie', 'Fournitures'],
    contacts: [
      MockSupplierContact(
        id: 'c6_1',
        name: 'Lydie Barthélemy',
        title: 'Responsable commerciale',
        phone: '+509 2234-5678',
        email: 'lydie@papnat.ht',
      ),
    ],
  ),
  MockSupplier(
    id: 7,
    name: 'Agri-Haïti Distribution',
    phone: '+509 3789-0000',
    email: 'frantz@agrihaiti.ht',
    location: 'Kenscoff, Route Nationale 6',
    note:
        'Produits frais et alimentaires locaux. Livraison matinale uniquement (avant 9h).',
    categories: ['Alimentation', 'Produits locaux'],
    contacts: [
      MockSupplierContact(
        id: 'c7_1',
        name: 'Frantz Augustin',
        title: 'Gérant',
        phone: '+509 3789-0000',
        email: 'frantz@agrihaiti.ht',
      ),
      MockSupplierContact(
        id: 'c7_2',
        name: 'Marjorie Cicéron',
        title: 'Livraison',
        phone: '+509 3789-0001',
        email: '',
      ),
    ],
  ),
  MockSupplier(
    id: 8,
    name: 'Ménagère Plus',
    phone: '+509 3567-8901',
    email: 'gestion@menagereplus.ht',
    location: 'Delmas 19, Impasse Flamboyant',
    note:
        'Produits d\'entretien et ménage en gros. Commande minimum 10 000 HTG.',
    categories: ['Ménage', 'Entretien'],
    contacts: [
      MockSupplierContact(
        id: 'c8_1',
        name: 'Ginette Lerebours',
        title: 'Propriétaire',
        phone: '+509 3567-8901',
        email: 'gestion@menagereplus.ht',
      ),
    ],
  ),
  MockSupplier(
    id: 9,
    name: 'Tech Import Haïti',
    phone: '+509 3999-0101',
    email: 'sales@techimport.ht',
    location: 'Port-au-Prince, Boulevard Harry Truman',
    note:
        'Accessoires électroniques et informatique. Importation directe des États-Unis.',
    categories: ['Électronique', 'Importation'],
    contacts: [
      MockSupplierContact(
        id: 'c9_1',
        name: 'Christophe Duvivier',
        title: 'Directeur des ventes',
        phone: '+509 3999-0101',
        email: 'c.duvivier@techimport.ht',
      ),
      MockSupplierContact(
        id: 'c9_2',
        name: 'Nadia Pierre-Louis',
        title: 'Service client',
        phone: '+509 3999-0102',
        email: 'nadia@techimport.ht',
      ),
    ],
  ),
  MockSupplier(
    id: 10,
    name: 'Boissons Tropicales SA',
    phone: '+509 2944-7777',
    email: 'orders@boissonstropic.ht',
    location: 'Tabarre 41, Zone Franche',
    note:
        'Jus tropicaux, eaux et sodas locaux. Livraison hebdomadaire le lundi.',
    categories: ['Boissons', 'Produits locaux'],
    contacts: [
      MockSupplierContact(
        id: 'c10_1',
        name: 'Évelyne Saint-Fleur',
        title: 'Commerciale',
        phone: '+509 2944-7777',
        email: 'esaintfleur@boissonstropic.ht',
      ),
    ],
  ),
];

// ──────────────── STATE NOTIFIERS ────────────────

class ProductsNotifier extends StateNotifier<List<MockProduct>> {
  ProductsNotifier({this.journal}) : super(_mockProductsSeed);
  final PendingJournal? journal;
  int get _nextId => state.isEmpty
      ? 1
      : state.map((p) => p.id).reduce((a, b) => a > b ? a : b) + 1;
  void add(MockProduct p) {
    state = [...state, p.copyWith(id: _nextId)];
    journal?.call(PendingOperationKind.product, 'Produit ajouté · ${p.name}');
  }

  void update(MockProduct p) {
    replaceQuietly(p);
    journal?.call(PendingOperationKind.product, 'Produit modifié · ${p.name}');
  }

  /// Replaces the product without queuing it; stock movements queue themselves.
  void replaceQuietly(MockProduct p) =>
      state = [for (final r in state) r.id == p.id ? p : r];

  void remove(int id) {
    final name = state.where((p) => p.id == id).firstOrNull?.name;
    state = state.where((p) => p.id != id).toList();
    if (name != null) {
      journal?.call(PendingOperationKind.product, 'Produit supprimé · $name');
    }
  }

  /// Decrease stock after a successful sale (mock).
  void applySale(Map<int, int> productIdToQty) {
    state = [
      for (final p in state)
        if (productIdToQty.containsKey(p.id) && p.trackStock)
          p.copyWith(
            stockQuantity: (p.stockQuantity - productIdToQty[p.id]!).clamp(
              0,
              1 << 30,
            ),
          )
        else
          p,
    ];
  }
}

class SuppliersNotifier extends StateNotifier<List<MockSupplier>> {
  SuppliersNotifier({this.journal}) : super(_mockSuppliersSeed);
  final PendingJournal? journal;
  int get _nextId => state.isEmpty
      ? 1
      : state.map((s) => s.id).reduce((a, b) => a > b ? a : b) + 1;
  void add(MockSupplier s) {
    state = [...state, s.copyWith(id: _nextId)];
    journal?.call(
      PendingOperationKind.supplier,
      'Fournisseur ajouté · ${s.name}',
    );
  }

  void update(MockSupplier s) {
    state = [for (final r in state) r.id == s.id ? s : r];
    journal?.call(
      PendingOperationKind.supplier,
      'Fournisseur modifié · ${s.name}',
    );
  }

  void remove(int id) {
    final name = state.where((s) => s.id == id).firstOrNull?.name;
    state = state.where((s) => s.id != id).toList();
    if (name != null) {
      journal?.call(
        PendingOperationKind.supplier,
        'Fournisseur supprimé · $name',
      );
    }
  }
}

// ──────────────── Retail settings (delivery, etc.) ────────────────

class RetailSettings {
  final bool pickupEnabled;
  final bool deliveryEnabled;

  /// Both on by default; if both off, checkout hides fulfillment (treats as in store).
  const RetailSettings({
    this.pickupEnabled = true,
    this.deliveryEnabled = true,
  });

  RetailSettings copyWith({bool? pickupEnabled, bool? deliveryEnabled}) {
    return RetailSettings(
      pickupEnabled: pickupEnabled ?? this.pickupEnabled,
      deliveryEnabled: deliveryEnabled ?? this.deliveryEnabled,
    );
  }
}

class RetailSettingsNotifier extends StateNotifier<RetailSettings> {
  RetailSettingsNotifier()
    : super(const RetailSettings(pickupEnabled: true, deliveryEnabled: true));

  void setPickupEnabled(bool value) =>
      state = state.copyWith(pickupEnabled: value);

  void setDeliveryEnabled(bool value) =>
      state = state.copyWith(deliveryEnabled: value);

  void togglePickup() =>
      state = state.copyWith(pickupEnabled: !state.pickupEnabled);

  void toggleDelivery() =>
      state = state.copyWith(deliveryEnabled: !state.deliveryEnabled);
}

// ──────────────── Quotes ────────────────

enum MockRetailQuoteStatus { draft, converted, expired, cancelled }

extension MockRetailQuoteStatusX on MockRetailQuoteStatus {
  /// Open quotes (Active tab).
  bool get isActiveQuotesTab => this == MockRetailQuoteStatus.draft;

  /// Inactive tab only: expired or cancelled. Converted quotes become orders and
  /// are not listed on this page.
  bool get isInactiveQuotesTab =>
      this == MockRetailQuoteStatus.expired ||
      this == MockRetailQuoteStatus.cancelled;

  /// Inactive detail panel may offer “Reactivate” back to draft.
  bool get canReactivateToDraft =>
      this == MockRetailQuoteStatus.expired ||
      this == MockRetailQuoteStatus.cancelled;
}

/// A line item in a quote. Prices are snapshotted at creation time so that
/// later catalog price changes do not alter historical quotes.
class MockQuoteLine {
  final MockProduct product; // kept for catalog reference / display
  final int quantity;
  final double unitPriceHtg; // snapshot — NOT the live product price
  final double? unitPriceUsd; // snapshot
  final MeasureChoice measure;

  MockQuoteLine({
    required this.product,
    required this.quantity,
    double? unitPriceHtg,
    this.unitPriceUsd,
    this.measure = const MeasureChoice.plain(),
  }) : unitPriceHtg = unitPriceHtg ?? product.sellingPriceHtg;

  double get lineTotalHtg => unitPriceHtg * quantity;

  String get displayName {
    final extra = measure.label(unitsPerCase: product.unitsPerCase);
    if (extra.isEmpty || product.name.contains(extra)) return product.name;
    return '${product.name} · $extra';
  }
}

class MockRetailQuote {
  final String id;
  final String quoteNumber; // e.g. QTE-2026-0001
  final String checkoutId;
  final List<MockQuoteLine> lines;
  final String? clientName;
  final String? clientPhone;
  final String? clientEmail; // required for quotes (with clientPhone)
  final RetailFulfillmentMode fulfillmentMode;
  final String? deliveryLocation;
  final String? deliveryPhone;
  final double discountPercent;
  final MockRetailQuoteStatus status;
  final bool paymentLinkSent;

  /// True when the quote total has been paid (e.g. via link); hides send/resend link.
  final bool isPaid;
  final DateTime createdAt;

  const MockRetailQuote({
    required this.id,
    required this.quoteNumber,
    required this.checkoutId,
    required this.lines,
    this.clientName,
    this.clientPhone,
    this.clientEmail,
    this.fulfillmentMode = RetailFulfillmentMode.inStore,
    this.deliveryLocation,
    this.deliveryPhone,
    this.discountPercent = 0,
    this.status = MockRetailQuoteStatus.draft,
    this.paymentLinkSent = false,
    this.isPaid = false,
    required this.createdAt,
  });

  double subtotalHtg() => lines.fold(0.0, (s, l) => s + l.lineTotalHtg);

  double discountAmountHtg() => subtotalHtg() * (discountPercent / 100);

  double totalBeforeTaxHtg() => subtotalHtg() - discountAmountHtg();

  MockRetailQuote copyWith({
    String? id,
    String? quoteNumber,
    String? checkoutId,
    List<MockQuoteLine>? lines,
    Object? clientName = _sentinel,
    Object? clientPhone = _sentinel,
    Object? clientEmail = _sentinel,
    RetailFulfillmentMode? fulfillmentMode,
    Object? deliveryLocation = _sentinel,
    Object? deliveryPhone = _sentinel,
    double? discountPercent,
    MockRetailQuoteStatus? status,
    bool? paymentLinkSent,
    bool? isPaid,
    DateTime? createdAt,
  }) {
    return MockRetailQuote(
      id: id ?? this.id,
      quoteNumber: quoteNumber ?? this.quoteNumber,
      checkoutId: checkoutId ?? this.checkoutId,
      lines: lines ?? this.lines,
      clientName: clientName == _sentinel
          ? this.clientName
          : clientName as String?,
      clientPhone: clientPhone == _sentinel
          ? this.clientPhone
          : clientPhone as String?,
      clientEmail: clientEmail == _sentinel
          ? this.clientEmail
          : clientEmail as String?,
      fulfillmentMode: fulfillmentMode ?? this.fulfillmentMode,
      deliveryLocation: deliveryLocation == _sentinel
          ? this.deliveryLocation
          : deliveryLocation as String?,
      deliveryPhone: deliveryPhone == _sentinel
          ? this.deliveryPhone
          : deliveryPhone as String?,
      discountPercent: discountPercent ?? this.discountPercent,
      status: status ?? this.status,
      paymentLinkSent: paymentLinkSent ?? this.paymentLinkSent,
      isPaid: isPaid ?? this.isPaid,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

class QuotesNotifier extends StateNotifier<List<MockRetailQuote>> {
  QuotesNotifier({this.journal}) : super(_mockQuotesSeed);
  final PendingJournal? journal;

  void _log(String id, String action) {
    final number =
        state.where((q) => q.id == id).firstOrNull?.quoteNumber ?? 'Devis';
    journal?.call(PendingOperationKind.quote, '$number · $action');
  }

  static String newCheckoutId() =>
      'chk_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(999999)}';

  static String newQuoteNumber() {
    final now = DateTime.now();
    final seq = (now.millisecondsSinceEpoch ~/ 1000) % 10000;
    return 'QTE-${now.year}-${seq.toString().padLeft(4, '0')}';
  }

  void add(MockRetailQuote q) {
    state = [q, ...state];
    _log(q.id, 'créé');
  }

  void updateQuote(MockRetailQuote updated) {
    state = [
      for (final q in state)
        if (q.id == updated.id) updated else q,
    ];
    _log(updated.id, 'modifié');
  }

  void convertToOrder(String id) {
    state = [
      for (final q in state)
        if (q.id == id)
          q.copyWith(status: MockRetailQuoteStatus.converted)
        else
          q,
    ];
    _log(id, 'converti en commande');
  }

  void expire(String id) {
    state = [
      for (final q in state)
        if (q.id == id)
          q.copyWith(status: MockRetailQuoteStatus.expired)
        else
          q,
    ];
    _log(id, 'expiré');
  }

  void cancel(String id) {
    state = [
      for (final q in state)
        if (q.id == id)
          q.copyWith(status: MockRetailQuoteStatus.cancelled)
        else
          q,
    ];
    _log(id, 'annulé');
  }

  /// Restore an expired or cancelled quote to draft (Active quotes tab).
  void reactivateToDraft(String id) {
    state = [
      for (final q in state)
        if (q.id == id)
          q.copyWith(status: MockRetailQuoteStatus.draft, isPaid: false)
        else
          q,
    ];
    _log(id, 'remis en brouillon');
  }

  void markPaymentLinkSent(String id) {
    state = [
      for (final q in state)
        if (q.id == id) q.copyWith(paymentLinkSent: true) else q,
    ];
    _log(id, 'lien de paiement envoyé');
  }

  /// Call when the client has paid (e.g. payment-link webhook); hides send/resend in UI.
  void markQuotePaid(String id) {
    state = [
      for (final q in state)
        if (q.id == id) q.copyWith(isPaid: true) else q,
    ];
    _log(id, 'payé');
  }
}

// ──────────────── Seed quotes (active + inactive tabs / pagination) ─────────

final _mockQuotesSeed = <MockRetailQuote>[
  MockRetailQuote(
    id: 'qte_1',
    quoteNumber: 'QTE-2026-0001',
    checkoutId: 'chk_seed_1',
    lines: [
      MockQuoteLine(
        product: _mockProductsSeed[0],
        quantity: 2,
        unitPriceHtg: 3200,
        unitPriceUsd: 32,
      ),
      MockQuoteLine(
        product: _mockProductsSeed[4],
        quantity: 24,
        unitPriceHtg: 180,
        unitPriceUsd: 1.80,
      ),
    ],
    clientName: 'Restaurant Ti Kay',
    clientPhone: '+509 4123-5678',
    fulfillmentMode: RetailFulfillmentMode.delivery,
    deliveryLocation: 'Delmas 19',
    deliveryPhone: '+509 4123-5678',
    discountPercent: 5,
    status: MockRetailQuoteStatus.draft,
    paymentLinkSent: true,
    isPaid: true,
    createdAt: DateTime.now().subtract(const Duration(days: 1)),
  ),
  MockRetailQuote(
    id: 'qte_2',
    quoteNumber: 'QTE-2026-0002',
    checkoutId: 'chk_seed_2',
    lines: [
      MockQuoteLine(
        product: _mockProductsSeed[12],
        quantity: 4,
        unitPriceHtg: 600,
        unitPriceUsd: 6,
      ),
      MockQuoteLine(
        product: _mockProductsSeed[13],
        quantity: 6,
        unitPriceHtg: 180,
        unitPriceUsd: 1.80,
      ),
    ],
    clientName: 'Roseline Janvier',
    clientPhone: '+509 4567-8901',
    clientEmail: 'roseline.j@yahoo.fr',
    fulfillmentMode: RetailFulfillmentMode.pickup,
    discountPercent: 0,
    status: MockRetailQuoteStatus.converted,
    createdAt: DateTime.now().subtract(const Duration(days: 3)),
  ),
  MockRetailQuote(
    id: 'qte_3',
    quoteNumber: 'QTE-2026-0003',
    checkoutId: 'chk_seed_3',
    lines: [
      MockQuoteLine(
        product: _mockProductsSeed[10],
        quantity: 10,
        unitPriceHtg: 350,
        unitPriceUsd: 3.50,
      ),
      MockQuoteLine(
        product: _mockProductsSeed[11],
        quantity: 3,
        unitPriceHtg: 800,
        unitPriceUsd: 8,
      ),
    ],
    clientName: 'Jean Michel',
    clientPhone: '+1 (786) 555-0123',
    clientEmail: 'jmichel.hti@gmail.com',
    fulfillmentMode: RetailFulfillmentMode.pickup,
    discountPercent: 0,
    status: MockRetailQuoteStatus.converted,
    paymentLinkSent: true,
    createdAt: DateTime.now().subtract(const Duration(days: 1)),
  ),
  MockRetailQuote(
    id: 'qte_4',
    quoteNumber: 'QTE-2026-0004',
    checkoutId: 'chk_seed_4',
    lines: [
      MockQuoteLine(
        product: _mockProductsSeed[14],
        quantity: 30,
        unitPriceHtg: 150,
      ),
      MockQuoteLine(
        product: _mockProductsSeed[7],
        quantity: 10,
        unitPriceHtg: 150,
      ),
      MockQuoteLine(
        product: _mockProductsSeed[8],
        quantity: 5,
        unitPriceHtg: 450,
      ),
    ],
    clientName: 'École Nationale No.3',
    clientPhone: '+509 2222-3333',
    fulfillmentMode: RetailFulfillmentMode.delivery,
    deliveryLocation: 'Carrefour, Route des Rails',
    deliveryPhone: '+509 2222-3334',
    discountPercent: 15,
    status: MockRetailQuoteStatus.draft,
    createdAt: DateTime.now().subtract(const Duration(hours: 18)),
  ),
  MockRetailQuote(
    id: 'qte_5',
    quoteNumber: 'QTE-2026-0005',
    checkoutId: 'chk_seed_5',
    lines: [
      MockQuoteLine(
        product: _mockProductsSeed[12],
        quantity: 2,
        unitPriceHtg: 600,
      ),
      MockQuoteLine(
        product: _mockProductsSeed[13],
        quantity: 3,
        unitPriceHtg: 180,
      ),
      MockQuoteLine(
        product: _mockProductsSeed[7],
        quantity: 4,
        unitPriceHtg: 150,
      ),
    ],
    clientName: 'Marie-Claire Joseph',
    clientPhone: '+509 3789-0123',
    fulfillmentMode: RetailFulfillmentMode.pickup,
    discountPercent: 0,
    status: MockRetailQuoteStatus.expired,
    createdAt: DateTime.now().subtract(const Duration(days: 14)),
  ),
  MockRetailQuote(
    id: 'qte_6',
    quoteNumber: 'QTE-2026-0006',
    checkoutId: 'chk_seed_6',
    lines: [
      MockQuoteLine(
        product: _mockProductsSeed[4],
        quantity: 96,
        unitPriceHtg: 180,
      ),
      MockQuoteLine(
        product: _mockProductsSeed[5],
        quantity: 48,
        unitPriceHtg: 120,
      ),
      MockQuoteLine(
        product: _mockProductsSeed[6],
        quantity: 10,
        unitPriceHtg: 280,
      ),
    ],
    clientName: 'Hôtel Roi Christophe',
    clientPhone: '+509 3600-0000',
    fulfillmentMode: RetailFulfillmentMode.inStore,
    discountPercent: 10,
    status: MockRetailQuoteStatus.draft,
    createdAt: DateTime.now().subtract(const Duration(days: 3)),
  ),
  MockRetailQuote(
    id: 'qte_7',
    quoteNumber: 'QTE-2026-0007',
    checkoutId: 'chk_seed_7',
    lines: [
      MockQuoteLine(
        product: _mockProductsSeed[6],
        quantity: 5,
        unitPriceHtg: 280,
        unitPriceUsd: 2.80,
      ),
      MockQuoteLine(
        product: _mockProductsSeed[8],
        quantity: 4,
        unitPriceHtg: 450,
        unitPriceUsd: 4.50,
      ),
    ],
    clientName: 'Philippe Moreau',
    clientPhone: '+1 (514) 555-9876',
    clientEmail: 'pmoreau.htmd@outlook.com',
    fulfillmentMode: RetailFulfillmentMode.delivery,
    deliveryLocation: 'Tabarre 47 — c/o Famille Moreau',
    deliveryPhone: '+509 3798-1234',
    discountPercent: 0,
    status: MockRetailQuoteStatus.converted,
    paymentLinkSent: true,
    createdAt: DateTime.now().subtract(const Duration(hours: 6)),
  ),
  MockRetailQuote(
    id: 'qte_8',
    quoteNumber: 'QTE-2026-0008',
    checkoutId: 'chk_seed_8',
    lines: [
      MockQuoteLine(
        product: _mockProductsSeed[0],
        quantity: 1,
        unitPriceHtg: 3200,
      ),
      MockQuoteLine(
        product: _mockProductsSeed[1],
        quantity: 2,
        unitPriceHtg: 600,
      ),
      MockQuoteLine(
        product: _mockProductsSeed[3],
        quantity: 2,
        unitPriceHtg: 700,
      ),
    ],
    clientName: 'Client de passage',
    clientPhone: '+509 3000-0000',
    fulfillmentMode: RetailFulfillmentMode.inStore,
    discountPercent: 0,
    status: MockRetailQuoteStatus.draft,
    createdAt: DateTime.now().subtract(const Duration(hours: 1)),
  ),
  MockRetailQuote(
    id: 'qte_9',
    quoteNumber: 'QTE-2026-0009',
    checkoutId: 'chk_seed_9',
    lines: [
      MockQuoteLine(
        product: _mockProductsSeed[0],
        quantity: 3,
        unitPriceHtg: 3200,
      ),
      MockQuoteLine(
        product: _mockProductsSeed[1],
        quantity: 10,
        unitPriceHtg: 600,
      ),
      MockQuoteLine(
        product: _mockProductsSeed[2],
        quantity: 5,
        unitPriceHtg: 800,
      ),
    ],
    clientName: 'Restaurant Lakay',
    clientPhone: '+509 3444-5555',
    clientEmail: 'commande@restaurantlakay.ht',
    fulfillmentMode: RetailFulfillmentMode.delivery,
    deliveryLocation: 'Croix-des-Bouquets, Route Nationale 3',
    deliveryPhone: '+509 3444-5556',
    discountPercent: 8,
    status: MockRetailQuoteStatus.converted,
    paymentLinkSent: true,
    createdAt: DateTime.now().subtract(const Duration(days: 10)),
  ),
  MockRetailQuote(
    id: 'qte_10',
    quoteNumber: 'QTE-2026-0010',
    checkoutId: 'chk_seed_10',
    lines: [
      MockQuoteLine(
        product: _mockProductsSeed[12],
        quantity: 3,
        unitPriceHtg: 600,
      ),
      MockQuoteLine(
        product: _mockProductsSeed[13],
        quantity: 4,
        unitPriceHtg: 180,
      ),
      MockQuoteLine(
        product: _mockProductsSeed[7],
        quantity: 6,
        unitPriceHtg: 150,
      ),
    ],
    clientName: 'Sandra Pierre',
    clientPhone: '+509 3111-2222',
    clientEmail: 'sandrapierre07@gmail.com',
    fulfillmentMode: RetailFulfillmentMode.pickup,
    discountPercent: 0,
    status: MockRetailQuoteStatus.cancelled,
    createdAt: DateTime.now().subtract(const Duration(days: 2)),
  ),
  MockRetailQuote(
    id: 'qte_11',
    quoteNumber: 'QTE-2026-0011',
    checkoutId: 'chk_seed_11',
    lines: [
      MockQuoteLine(
        product: _mockProductsSeed[4],
        quantity: 120,
        unitPriceHtg: 180,
      ),
      MockQuoteLine(
        product: _mockProductsSeed[5],
        quantity: 60,
        unitPriceHtg: 120,
      ),
    ],
    clientName: 'Club Sportif Horizon',
    clientPhone: '+509 3888-0000',
    fulfillmentMode: RetailFulfillmentMode.inStore,
    discountPercent: 12,
    status: MockRetailQuoteStatus.expired,
    createdAt: DateTime.now().subtract(const Duration(days: 20)),
  ),
  MockRetailQuote(
    id: 'qte_12',
    quoteNumber: 'QTE-2026-0012',
    checkoutId: 'chk_seed_12',
    lines: [
      MockQuoteLine(
        product: _mockProductsSeed[0],
        quantity: 4,
        unitPriceHtg: 3200,
      ),
      MockQuoteLine(
        product: _mockProductsSeed[1],
        quantity: 8,
        unitPriceHtg: 600,
      ),
      MockQuoteLine(
        product: _mockProductsSeed[3],
        quantity: 6,
        unitPriceHtg: 700,
      ),
      MockQuoteLine(
        product: _mockProductsSeed[2],
        quantity: 4,
        unitPriceHtg: 800,
      ),
    ],
    clientName: 'Magasin Bossou',
    clientPhone: '+509 3555-7890',
    fulfillmentMode: RetailFulfillmentMode.delivery,
    deliveryLocation: 'Cap-Haïtien, Quartier Morin',
    deliveryPhone: '+509 3555-7891',
    discountPercent: 0,
    status: MockRetailQuoteStatus.draft,
    createdAt: DateTime.now().subtract(const Duration(hours: 4)),
  ),
  MockRetailQuote(
    id: 'qte_13',
    quoteNumber: 'QTE-2026-0013',
    checkoutId: 'chk_seed_13',
    lines: [
      MockQuoteLine(
        product: _mockProductsSeed[10],
        quantity: 6,
        unitPriceHtg: 350,
      ),
      MockQuoteLine(
        product: _mockProductsSeed[9],
        quantity: 3,
        unitPriceHtg: 200,
      ),
    ],
    clientName: 'Famille Desroches',
    clientPhone: '+509 3222-7777',
    fulfillmentMode: RetailFulfillmentMode.inStore,
    discountPercent: 0,
    status: MockRetailQuoteStatus.converted,
    paymentLinkSent: true,
    createdAt: DateTime.now().subtract(const Duration(days: 8)),
  ),
  MockRetailQuote(
    id: 'qte_14',
    quoteNumber: 'QTE-2026-0014',
    checkoutId: 'chk_seed_14',
    lines: [
      MockQuoteLine(
        product: _mockProductsSeed[14],
        quantity: 20,
        unitPriceHtg: 150,
      ),
      MockQuoteLine(
        product: _mockProductsSeed[11],
        quantity: 5,
        unitPriceHtg: 800,
      ),
    ],
    clientName: 'Institut Culturel Français',
    clientPhone: '+509 2813-0000',
    fulfillmentMode: RetailFulfillmentMode.inStore,
    discountPercent: 5,
    status: MockRetailQuoteStatus.cancelled,
    createdAt: DateTime.now().subtract(const Duration(hours: 12)),
  ),
  MockRetailQuote(
    id: 'qte_15',
    quoteNumber: 'QTE-2026-0015',
    checkoutId: 'chk_seed_15',
    lines: [
      MockQuoteLine(
        product: _mockProductsSeed[7],
        quantity: 12,
        unitPriceHtg: 150,
        unitPriceUsd: 1.50,
      ),
      MockQuoteLine(
        product: _mockProductsSeed[13],
        quantity: 10,
        unitPriceHtg: 180,
        unitPriceUsd: 1.80,
      ),
      MockQuoteLine(
        product: _mockProductsSeed[12],
        quantity: 6,
        unitPriceHtg: 600,
        unitPriceUsd: 6,
      ),
    ],
    clientName: 'Nathalie Dupont',
    clientPhone: '+33 6 12 34 56 78',
    clientEmail: 'ndupont.ht@protonmail.com',
    fulfillmentMode: RetailFulfillmentMode.delivery,
    deliveryLocation: 'c/o Corinne Valcourt — Pétionville, Rue Grégoire',
    deliveryPhone: '+509 3678-9012',
    discountPercent: 0,
    status: MockRetailQuoteStatus.draft,
    createdAt: DateTime.now().subtract(const Duration(minutes: 30)),
  ),
  MockRetailQuote(
    id: 'qte_16',
    quoteNumber: 'QTE-2026-0016',
    checkoutId: 'chk_seed_16',
    lines: [
      MockQuoteLine(
        product: _mockProductsSeed[9],
        quantity: 10,
        unitPriceHtg: 200,
      ),
      MockQuoteLine(
        product: _mockProductsSeed[10],
        quantity: 15,
        unitPriceHtg: 350,
      ),
      MockQuoteLine(
        product: _mockProductsSeed[8],
        quantity: 8,
        unitPriceHtg: 450,
      ),
    ],
    clientName: 'Clinique Dr. Pierre',
    clientPhone: '+509 3900-1111',
    fulfillmentMode: RetailFulfillmentMode.pickup,
    discountPercent: 0,
    status: MockRetailQuoteStatus.cancelled,
    createdAt: DateTime.now().subtract(const Duration(days: 3)),
  ),
  MockRetailQuote(
    id: 'qte_17',
    quoteNumber: 'QTE-2026-0017',
    checkoutId: 'chk_seed_17',
    lines: [
      MockQuoteLine(
        product: _mockProductsSeed[2],
        quantity: 2,
        unitPriceHtg: 800,
      ),
      MockQuoteLine(
        product: _mockProductsSeed[3],
        quantity: 4,
        unitPriceHtg: 700,
      ),
    ],
    clientName: 'Boutique Soleil',
    clientPhone: '+509 3777-8888',
    fulfillmentMode: RetailFulfillmentMode.pickup,
    discountPercent: 0,
    status: MockRetailQuoteStatus.draft,
    createdAt: DateTime.now().subtract(const Duration(hours: 8)),
  ),
  MockRetailQuote(
    id: 'qte_18',
    quoteNumber: 'QTE-2026-0018',
    checkoutId: 'chk_seed_18',
    lines: [
      MockQuoteLine(
        product: _mockProductsSeed[5],
        quantity: 24,
        unitPriceHtg: 120,
      ),
    ],
    clientName: 'Kafé Twòp',
    clientPhone: '+509 3666-4444',
    clientEmail: 'achats@kafetwop.ht',
    fulfillmentMode: RetailFulfillmentMode.inStore,
    discountPercent: 0,
    status: MockRetailQuoteStatus.draft,
    createdAt: DateTime.now().subtract(const Duration(hours: 20)),
  ),
  MockRetailQuote(
    id: 'qte_19',
    quoteNumber: 'QTE-2026-0019',
    checkoutId: 'chk_seed_19',
    lines: [
      MockQuoteLine(
        product: _mockProductsSeed[11],
        quantity: 2,
        unitPriceHtg: 800,
      ),
      MockQuoteLine(
        product: _mockProductsSeed[14],
        quantity: 40,
        unitPriceHtg: 150,
      ),
    ],
    clientName: 'Pharmacie Centrale',
    clientPhone: '+509 3456-0000',
    fulfillmentMode: RetailFulfillmentMode.delivery,
    deliveryLocation: 'Rue Capois, Port-au-Prince',
    deliveryPhone: '+509 3456-0001',
    discountPercent: 3,
    status: MockRetailQuoteStatus.draft,
    createdAt: DateTime.now().subtract(const Duration(days: 1, hours: 5)),
  ),
  MockRetailQuote(
    id: 'qte_20',
    quoteNumber: 'QTE-2026-0020',
    checkoutId: 'chk_seed_20',
    lines: [
      MockQuoteLine(
        product: _mockProductsSeed[9],
        quantity: 5,
        unitPriceHtg: 200,
      ),
    ],
    clientName: 'Client de passage',
    clientPhone: '+509 3000-1111',
    fulfillmentMode: RetailFulfillmentMode.inStore,
    discountPercent: 0,
    status: MockRetailQuoteStatus.draft,
    createdAt: DateTime.now().subtract(const Duration(minutes: 90)),
  ),
  MockRetailQuote(
    id: 'qte_21',
    quoteNumber: 'QTE-2026-0021',
    checkoutId: 'chk_seed_21',
    lines: [
      MockQuoteLine(
        product: _mockProductsSeed[0],
        quantity: 1,
        unitPriceHtg: 3200,
      ),
      MockQuoteLine(
        product: _mockProductsSeed[4],
        quantity: 48,
        unitPriceHtg: 180,
      ),
    ],
    clientName: 'Hôpital Bernard Mevs',
    clientPhone: '+509 2812-3030',
    fulfillmentMode: RetailFulfillmentMode.delivery,
    deliveryLocation: 'Delmas 33',
    deliveryPhone: '+509 2812-3031',
    discountPercent: 0,
    status: MockRetailQuoteStatus.cancelled,
    createdAt: DateTime.now().subtract(const Duration(days: 5)),
  ),
  MockRetailQuote(
    id: 'qte_22',
    quoteNumber: 'QTE-2026-0022',
    checkoutId: 'chk_seed_22',
    lines: [
      MockQuoteLine(
        product: _mockProductsSeed[6],
        quantity: 8,
        unitPriceHtg: 280,
      ),
    ],
    clientName: 'Marché de Fer',
    clientPhone: '+509 3999-1212',
    fulfillmentMode: RetailFulfillmentMode.pickup,
    discountPercent: 0,
    status: MockRetailQuoteStatus.expired,
    createdAt: DateTime.now().subtract(const Duration(days: 25)),
  ),
  MockRetailQuote(
    id: 'qte_23',
    quoteNumber: 'QTE-2026-0023',
    checkoutId: 'chk_seed_23',
    lines: [
      MockQuoteLine(
        product: _mockProductsSeed[12],
        quantity: 10,
        unitPriceHtg: 600,
      ),
    ],
    clientName: 'Épicerie Délivrance',
    clientPhone: '+509 3123-4545',
    fulfillmentMode: RetailFulfillmentMode.inStore,
    discountPercent: 0,
    status: MockRetailQuoteStatus.converted,
    createdAt: DateTime.now().subtract(const Duration(days: 2, hours: 3)),
  ),
  MockRetailQuote(
    id: 'qte_24',
    quoteNumber: 'QTE-2026-0024',
    checkoutId: 'chk_seed_24',
    lines: [
      MockQuoteLine(
        product: _mockProductsSeed[8],
        quantity: 3,
        unitPriceHtg: 450,
      ),
      MockQuoteLine(
        product: _mockProductsSeed[10],
        quantity: 8,
        unitPriceHtg: 350,
      ),
    ],
    clientName: 'Radio Caraïbes FM',
    clientPhone: '+509 2234-0000',
    clientEmail: 'admin@radiocaraibes.ht',
    fulfillmentMode: RetailFulfillmentMode.pickup,
    discountPercent: 5,
    status: MockRetailQuoteStatus.draft,
    createdAt: DateTime.now().subtract(const Duration(hours: 3)),
  ),
  MockRetailQuote(
    id: 'qte_25',
    quoteNumber: 'QTE-2026-0025',
    checkoutId: 'chk_seed_25',
    lines: [
      MockQuoteLine(
        product: _mockProductsSeed[1],
        quantity: 2,
        unitPriceHtg: 600,
      ),
    ],
    clientName: 'Lycée Toussaint',
    clientPhone: '+509 2944-1000',
    fulfillmentMode: RetailFulfillmentMode.inStore,
    discountPercent: 0,
    status: MockRetailQuoteStatus.expired,
    createdAt: DateTime.now().subtract(const Duration(days: 45)),
  ),
  MockRetailQuote(
    id: 'qte_26',
    quoteNumber: 'QTE-2026-0026',
    checkoutId: 'chk_seed_26',
    lines: [
      MockQuoteLine(
        product: _mockProductsSeed[13],
        quantity: 20,
        unitPriceHtg: 180,
      ),
    ],
    clientName: 'Mme Bélizaire',
    clientPhone: '+509 3777-2000',
    fulfillmentMode: RetailFulfillmentMode.pickup,
    discountPercent: 0,
    status: MockRetailQuoteStatus.cancelled,
    createdAt: DateTime.now().subtract(const Duration(days: 7)),
  ),
  MockRetailQuote(
    id: 'qte_27',
    quoteNumber: 'QTE-2026-0027',
    checkoutId: 'chk_seed_27',
    lines: [
      MockQuoteLine(
        product: _mockProductsSeed[6],
        quantity: 4,
        unitPriceHtg: 280,
      ),
    ],
    clientName: 'Boulangerie Pétion',
    clientPhone: '+509 3611-9090',
    fulfillmentMode: RetailFulfillmentMode.inStore,
    discountPercent: 0,
    status: MockRetailQuoteStatus.expired,
    createdAt: DateTime.now().subtract(const Duration(days: 60)),
  ),
  MockRetailQuote(
    id: 'qte_28',
    quoteNumber: 'QTE-2026-0028',
    checkoutId: 'chk_seed_28',
    lines: [
      MockQuoteLine(
        product: _mockProductsSeed[14],
        quantity: 15,
        unitPriceHtg: 150,
      ),
    ],
    clientName: 'ONG Solidarité',
    clientPhone: '+509 3888-3030',
    fulfillmentMode: RetailFulfillmentMode.delivery,
    deliveryLocation: 'Carrefour',
    deliveryPhone: '+509 3888-3031',
    discountPercent: 0,
    status: MockRetailQuoteStatus.cancelled,
    createdAt: DateTime.now().subtract(const Duration(days: 4)),
  ),
  MockRetailQuote(
    id: 'qte_29',
    quoteNumber: 'QTE-2026-0029',
    checkoutId: 'chk_seed_29',
    lines: [
      MockQuoteLine(
        product: _mockProductsSeed[3],
        quantity: 1,
        unitPriceHtg: 700,
      ),
    ],
    clientName: 'Client de passage',
    clientPhone: '+509 3000-9999',
    fulfillmentMode: RetailFulfillmentMode.inStore,
    discountPercent: 0,
    status: MockRetailQuoteStatus.expired,
    createdAt: DateTime.now().subtract(const Duration(days: 90)),
  ),
  MockRetailQuote(
    id: 'qte_30',
    quoteNumber: 'QTE-2026-0030',
    checkoutId: 'chk_seed_30',
    lines: [
      MockQuoteLine(
        product: _mockProductsSeed[10],
        quantity: 12,
        unitPriceHtg: 350,
      ),
    ],
    clientName: 'Garde-Manger SA',
    clientPhone: '+509 3450-7777',
    fulfillmentMode: RetailFulfillmentMode.pickup,
    discountPercent: 2,
    status: MockRetailQuoteStatus.cancelled,
    createdAt: DateTime.now().subtract(const Duration(days: 12)),
  ),
];

// ──────────────── RETAIL INVENTORY LEDGER (mock) ────────────────

enum RetailStockMovementKind { stockIn, sale, adjustment }

/// One stock movement line. [quantityDelta] is positive for stock in / upward
/// adjustment, negative for sales and downward adjustment.
class RetailStockMovement {
  final String id;
  final int productId;
  final RetailStockMovementKind kind;
  final int quantityDelta;

  /// Physical receipt / effective date (and time when known).
  final DateTime receivedAt;

  /// When the line was recorded in the system.
  final DateTime enteredAt;
  final String? supplierName;
  final String? notes;

  const RetailStockMovement({
    required this.id,
    required this.productId,
    required this.kind,
    required this.quantityDelta,
    required this.receivedAt,
    required this.enteredAt,
    this.supplierName,
    this.notes,
  });
}

List<RetailStockMovement> _seedRetailInventoryMovements() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final out = <RetailStockMovement>[];
  var seq = 0;
  String nid() => 'seed_${seq++}';

  for (final product in _mockProductsSeed) {
    final t = product.stockQuantity;
    var s1 = max(1, min(12, (t * 0.25).round()));
    var s2 = max(0, min(10, (t * 0.15).round()));
    var rin = max(0, min(8, (t * 0.12).round()));
    var opening = t + s1 + s2 - rin;
    if (opening < 0) {
      opening = t;
      s1 = 0;
      s2 = 0;
      rin = 0;
    }

    final tOpen = today.subtract(const Duration(days: 52));
    final tSale1 = today.subtract(const Duration(days: 38));
    final tSale2 = today.subtract(const Duration(days: 21));
    final tIn = today.subtract(const Duration(days: 9));

    out.add(
      RetailStockMovement(
        id: nid(),
        productId: product.id,
        kind: RetailStockMovementKind.stockIn,
        quantityDelta: opening,
        receivedAt: tOpen,
        enteredAt: tOpen.add(const Duration(hours: 3, minutes: 20)),
        supplierName: 'DINASA (Riz & Farine)',
        notes: 'Livraison d\'ouverture — réception palette',
      ),
    );
    if (s1 > 0) {
      out.add(
        RetailStockMovement(
          id: nid(),
          productId: product.id,
          kind: RetailStockMovementKind.sale,
          quantityDelta: -s1,
          receivedAt: tSale1.add(const Duration(hours: 14, minutes: 30)),
          enteredAt: tSale1.add(const Duration(hours: 14, minutes: 30)),
          supplierName: null,
          notes: 'Vente (caisse)',
        ),
      );
    }
    if (s2 > 0) {
      out.add(
        RetailStockMovement(
          id: nid(),
          productId: product.id,
          kind: RetailStockMovementKind.sale,
          quantityDelta: -s2,
          receivedAt: tSale2.add(const Duration(hours: 11)),
          enteredAt: tSale2.add(const Duration(hours: 11)),
          supplierName: null,
          notes: 'Vente (caisse)',
        ),
      );
    }
    if (rin > 0) {
      out.add(
        RetailStockMovement(
          id: nid(),
          productId: product.id,
          kind: RetailStockMovementKind.stockIn,
          quantityDelta: rin,
          receivedAt: tIn,
          enteredAt: tIn.add(const Duration(hours: 5, minutes: 45)),
          supplierName: 'Importex Haïti',
          notes: 'Réapprovisionnement — livraison partielle',
        ),
      );
    }
  }

  // Demo: April-only activity (current year) — dense ledger for month filter / product detail.
  const aprilDemoProductId = 11;
  final y = now.year;
  DateTime ap(int day, [int h = 9, int min = 0]) => DateTime(y, 4, day, h, min);

  out.addAll([
    RetailStockMovement(
      id: nid(),
      productId: aprilDemoProductId,
      kind: RetailStockMovementKind.stockIn,
      quantityDelta: 24,
      receivedAt: ap(2, 8, 30),
      enteredAt: ap(2, 8, 40),
      supplierName: 'DINASA (Riz & Farine)',
      notes: 'April restock — wholesale pallet',
    ),
    RetailStockMovement(
      id: nid(),
      productId: aprilDemoProductId,
      kind: RetailStockMovementKind.sale,
      quantityDelta: -2,
      receivedAt: ap(3, 14, 20),
      enteredAt: ap(3, 14, 20),
      supplierName: null,
      notes: 'Vente (caisse)',
    ),
    RetailStockMovement(
      id: nid(),
      productId: aprilDemoProductId,
      kind: RetailStockMovementKind.sale,
      quantityDelta: -1,
      receivedAt: ap(4, 11, 5),
      enteredAt: ap(4, 11, 5),
      supplierName: null,
      notes: 'Vente (caisse)',
    ),
    RetailStockMovement(
      id: nid(),
      productId: aprilDemoProductId,
      kind: RetailStockMovementKind.stockIn,
      quantityDelta: 18,
      receivedAt: ap(5, 7, 15),
      enteredAt: ap(5, 7, 22),
      supplierName: 'Importex Haïti',
      notes: 'Livraison partielle — quai B',
    ),
    RetailStockMovement(
      id: nid(),
      productId: aprilDemoProductId,
      kind: RetailStockMovementKind.adjustment,
      quantityDelta: 2,
      receivedAt: ap(6, 16, 0),
      enteredAt: ap(6, 16, 10),
      supplierName: null,
      notes: 'Correction d\'inventaire (+)',
    ),
    RetailStockMovement(
      id: nid(),
      productId: aprilDemoProductId,
      kind: RetailStockMovementKind.sale,
      quantityDelta: -3,
      receivedAt: ap(7, 10, 45),
      enteredAt: ap(7, 10, 45),
      supplierName: null,
      notes: 'Vente (caisse)',
    ),
    RetailStockMovement(
      id: nid(),
      productId: aprilDemoProductId,
      kind: RetailStockMovementKind.stockIn,
      quantityDelta: 12,
      receivedAt: ap(9, 6, 0),
      enteredAt: ap(9, 6, 18),
      supplierName: 'Caribbean Electric Supply',
      notes: 'Livraison express — facture n° A-1042',
    ),
    RetailStockMovement(
      id: nid(),
      productId: aprilDemoProductId,
      kind: RetailStockMovementKind.sale,
      quantityDelta: -2,
      receivedAt: ap(10, 15, 30),
      enteredAt: ap(10, 15, 30),
      supplierName: null,
      notes: 'Vente (caisse)',
    ),
    RetailStockMovement(
      id: nid(),
      productId: aprilDemoProductId,
      kind: RetailStockMovementKind.adjustment,
      quantityDelta: -1,
      receivedAt: ap(11, 18, 0),
      enteredAt: ap(11, 18, 5),
      supplierName: null,
      notes: 'Breakage — damaged box',
    ),
    RetailStockMovement(
      id: nid(),
      productId: aprilDemoProductId,
      kind: RetailStockMovementKind.sale,
      quantityDelta: -4,
      receivedAt: ap(12, 12, 0),
      enteredAt: ap(12, 12, 0),
      supplierName: null,
      notes: 'Vente (caisse)',
    ),
    RetailStockMovement(
      id: nid(),
      productId: aprilDemoProductId,
      kind: RetailStockMovementKind.stockIn,
      quantityDelta: 40,
      receivedAt: ap(14, 8, 0),
      enteredAt: ap(14, 8, 45),
      supplierName: 'DINASA (Riz & Farine)',
      notes: 'Commande en gros — contrat hôtel',
    ),
    RetailStockMovement(
      id: nid(),
      productId: aprilDemoProductId,
      kind: RetailStockMovementKind.sale,
      quantityDelta: -1,
      receivedAt: ap(15, 9, 20),
      enteredAt: ap(15, 9, 20),
      supplierName: null,
      notes: 'Vente (caisse)',
    ),
    RetailStockMovement(
      id: nid(),
      productId: aprilDemoProductId,
      kind: RetailStockMovementKind.sale,
      quantityDelta: -2,
      receivedAt: ap(16, 13, 0),
      enteredAt: ap(16, 13, 0),
      supplierName: null,
      notes: 'Vente (caisse)',
    ),
    RetailStockMovement(
      id: nid(),
      productId: aprilDemoProductId,
      kind: RetailStockMovementKind.adjustment,
      quantityDelta: 3,
      receivedAt: ap(18, 17, 30),
      enteredAt: ap(18, 17, 35),
      supplierName: null,
      notes: 'Stock retrouvé — réserve',
    ),
    RetailStockMovement(
      id: nid(),
      productId: aprilDemoProductId,
      kind: RetailStockMovementKind.sale,
      quantityDelta: -5,
      receivedAt: ap(20, 10, 0),
      enteredAt: ap(20, 10, 0),
      supplierName: null,
      notes: 'Vente (caisse)',
    ),
    RetailStockMovement(
      id: nid(),
      productId: aprilDemoProductId,
      kind: RetailStockMovementKind.stockIn,
      quantityDelta: 15,
      receivedAt: ap(22, 7, 0),
      enteredAt: ap(22, 7, 12),
      supplierName: 'Importex Haïti',
      notes: 'Reorder — weekly route',
    ),
    RetailStockMovement(
      id: nid(),
      productId: aprilDemoProductId,
      kind: RetailStockMovementKind.sale,
      quantityDelta: -2,
      receivedAt: ap(24, 16, 20),
      enteredAt: ap(24, 16, 20),
      supplierName: null,
      notes: 'Vente (caisse)',
    ),
    RetailStockMovement(
      id: nid(),
      productId: aprilDemoProductId,
      kind: RetailStockMovementKind.sale,
      quantityDelta: -1,
      receivedAt: ap(26, 11, 0),
      enteredAt: ap(26, 11, 0),
      supplierName: null,
      notes: 'Vente (caisse)',
    ),
    RetailStockMovement(
      id: nid(),
      productId: aprilDemoProductId,
      kind: RetailStockMovementKind.stockIn,
      quantityDelta: 10,
      receivedAt: ap(28, 8, 30),
      enteredAt: ap(28, 8, 40),
      supplierName: 'Caribbean Electric Supply',
      notes: 'Approvisionnement de fin de mois',
    ),
  ]);

  return out;
}

class RetailInventoryLedgerNotifier
    extends StateNotifier<List<RetailStockMovement>> {
  RetailInventoryLedgerNotifier(this._ref)
    : super(_seedRetailInventoryMovements());

  final Ref _ref;
  int _seq = 0;

  String _newId() => 'm_${DateTime.now().microsecondsSinceEpoch}_${_seq++}';

  void addStockIn({
    required int productId,
    required int quantity,
    required DateTime receivedAt,
    required String supplierName,
    String? notes,
  }) {
    if (quantity <= 0) return;
    final enteredAt = DateTime.now();
    final products = _ref.read(mockProductsProvider);
    final idx = products.indexWhere((e) => e.id == productId);
    if (idx < 0) return;
    final p = products[idx];
    _ref
        .read(mockProductsProvider.notifier)
        .replaceQuietly(p.copyWith(stockQuantity: p.stockQuantity + quantity));
    pendingJournal(_ref)(
      PendingOperationKind.stock,
      'Entrée de stock · ${p.name}',
      detail: '+$quantity · $supplierName',
    );
    state = [
      ...state,
      RetailStockMovement(
        id: _newId(),
        productId: productId,
        kind: RetailStockMovementKind.stockIn,
        quantityDelta: quantity,
        receivedAt: receivedAt,
        enteredAt: enteredAt,
        supplierName: supplierName,
        notes: notes,
      ),
    ];
  }

  /// Call after [ProductsNotifier.applySale] so stock stays in sync.
  void recordSalesFromCheckout(
    Map<int, int> productIdToQty,
    DateTime saleTime,
  ) {
    final extra = <RetailStockMovement>[];
    for (final e in productIdToQty.entries) {
      if (e.value <= 0) continue;
      extra.add(
        RetailStockMovement(
          id: _newId(),
          productId: e.key,
          kind: RetailStockMovementKind.sale,
          quantityDelta: -e.value,
          receivedAt: saleTime,
          enteredAt: saleTime,
          supplierName: null,
          notes: 'Vente (caisse)',
        ),
      );
    }
    if (extra.isEmpty) return;
    state = [...state, ...extra];
  }

  void adjust({
    required int productId,
    required int signedDelta,
    String? notes,
  }) {
    if (signedDelta == 0) return;
    final products = _ref.read(mockProductsProvider);
    final idx = products.indexWhere((e) => e.id == productId);
    if (idx < 0) return;
    final p = products[idx];
    final newQ = (p.stockQuantity + signedDelta).clamp(0, 1 << 30);
    _ref
        .read(mockProductsProvider.notifier)
        .replaceQuietly(p.copyWith(stockQuantity: newQ));
    pendingJournal(_ref)(
      PendingOperationKind.stock,
      'Ajustement de stock · ${p.name}',
      detail: signedDelta > 0 ? '+$signedDelta' : '$signedDelta',
    );
    final now = DateTime.now();
    state = [
      ...state,
      RetailStockMovement(
        id: _newId(),
        productId: productId,
        kind: RetailStockMovementKind.adjustment,
        quantityDelta: signedDelta,
        receivedAt: now,
        enteredAt: now,
        supplierName: null,
        notes: notes?.trim().isNotEmpty == true
            ? notes!.trim()
            : 'Ajustement de solde',
      ),
    ];
  }
}

// ──────────────── PROVIDERS ────────────────

final mockProductsProvider =
    StateNotifierProvider<ProductsNotifier, List<MockProduct>>(
      (ref) => ProductsNotifier(journal: pendingJournal(ref)),
    );

final retailInventoryLedgerProvider =
    StateNotifierProvider<
      RetailInventoryLedgerNotifier,
      List<RetailStockMovement>
    >((ref) => RetailInventoryLedgerNotifier(ref));

final mockCustomersProvider = Provider<List<MockCustomer>>(
  (ref) => mockCustomers,
);
final mockSalesProvider = Provider<List<MockSale>>((ref) => mockSales);

final mockSuppliersProvider =
    StateNotifierProvider<SuppliersNotifier, List<MockSupplier>>(
      (ref) => SuppliersNotifier(journal: pendingJournal(ref)),
    );

final retailSettingsProvider =
    StateNotifierProvider<RetailSettingsNotifier, RetailSettings>(
      (ref) => RetailSettingsNotifier(),
    );

final quotesProvider =
    StateNotifierProvider<QuotesNotifier, List<MockRetailQuote>>(
      (ref) => QuotesNotifier(journal: pendingJournal(ref)),
    );

const Object _sentinel = Object();
