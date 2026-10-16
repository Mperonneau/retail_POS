// Curated supplier categories for Haiti-oriented retail / procurement.
// Used for suggestions and the domain → category browser. Extend over time.

class SupplierCategoryDomain {
  const SupplierCategoryDomain({
    required this.id,
    required this.label,
    required this.categories,
  });

  final String id;
  final String label;
  final List<String> categories;
}

/// Domains and leaf categories (English labels; suitable for search + uniformity).
class SupplierCategoryTaxonomy {
  SupplierCategoryTaxonomy._();

  static const List<SupplierCategoryDomain> domains = [
    SupplierCategoryDomain(
      id: 'food_beverage',
      label: 'Food & beverages',
      categories: [
        'Rice & grains',
        'Flour & baking',
        'Cooking oil & fats',
        'Sugar & sweeteners',
        'Salt & spices',
        'Dry goods & groceries',
        'Canned & packaged foods',
        'Fresh produce',
        'Meat & poultry',
        'Seafood',
        'Dairy & eggs',
        'Frozen foods',
        'Bakery & bread',
        'Snacks & confectionery',
        'Bottled water & beverages',
        'Soft drinks & juices',
        'Beer & wine & spirits',
        'Coffee & tea',
        'HORECA ingredients',
      ],
    ),
    SupplierCategoryDomain(
      id: 'health_pharma',
      label: 'Health & pharmacy',
      categories: [
        'Pharmaceuticals & OTC',
        'Vitamins & supplements',
        'First aid & medical supplies',
        'Baby care & hygiene',
        'Personal hygiene basics',
        'Medical equipment (non-specialized)',
      ],
    ),
    SupplierCategoryDomain(
      id: 'education_office',
      label: 'Education & office',
      categories: [
        'School supplies',
        'Stationery & paper',
        'Office furniture',
        'Printing & copying supplies',
        'Books & educational materials',
      ],
    ),
    SupplierCategoryDomain(
      id: 'construction',
      label: 'Construction & materials',
      categories: [
        'Cement & concrete',
        'Aggregates & sand',
        'Steel & rebar',
        'Lumber & wood',
        'Roofing materials',
        'Paint & coatings',
        'Drywall & panels',
        'Windows & doors',
        'Tiles & flooring',
        'Insulation',
      ],
    ),
    SupplierCategoryDomain(
      id: 'electrical',
      label: 'Electrical & lighting',
      categories: [
        'Cables & wiring',
        'Switches & outlets',
        'Circuit breakers & panels',
        'Lighting fixtures & bulbs',
        'Generators & backup power',
        'Fans & ventilation',
        'Solar components',
      ],
    ),
    SupplierCategoryDomain(
      id: 'plumbing',
      label: 'Plumbing & sanitary',
      categories: [
        'Pipes & fittings',
        'Valves & taps',
        'Pumps & water systems',
        'Toilets & sinks',
        'Water tanks & storage',
        'Drainage & gutters',
      ],
    ),
    SupplierCategoryDomain(
      id: 'hardware_tools',
      label: 'Hardware & tools',
      categories: [
        'Hand tools',
        'Power tools',
        'Fasteners & screws',
        'Locks & security hardware',
        'Welding & cutting',
        'Safety equipment (PPE)',
        'Ladders & lifting',
      ],
    ),
    SupplierCategoryDomain(
      id: 'packaging',
      label: 'Packaging & consumables',
      categories: [
        'Bags & sacks',
        'Cartons & boxes',
        'Plastic film & wrap',
        'Labels & tape',
        'Disposable cups & plates',
        'Food service disposables',
      ],
    ),
    SupplierCategoryDomain(
      id: 'cleaning',
      label: 'Cleaning & hygiene',
      categories: [
        'Household cleaners',
        'Laundry products',
        'Janitorial supplies',
        'Mops & brooms',
        'Trash bags & bins',
        'Air fresheners',
      ],
    ),
    SupplierCategoryDomain(
      id: 'textile',
      label: 'Textile & apparel',
      categories: [
        'Uniforms & workwear',
        'Bed & bath linen',
        'Towels & napkins',
        'Fabric & notions',
        'Footwear (bulk / work)',
      ],
    ),
    SupplierCategoryDomain(
      id: 'it_telecom',
      label: 'IT & telecom',
      categories: [
        'Computers & tablets',
        'Networking equipment',
        'Phones & accessories',
        'POS & barcode hardware',
        'Cables & adapters',
        'Software & subscriptions (vendor)',
      ],
    ),
    SupplierCategoryDomain(
      id: 'transport',
      label: 'Transport & fuel',
      categories: [
        'Fuel & lubricants',
        'Vehicle parts (general)',
        'Tires & batteries',
        'Logistics & freight services',
      ],
    ),
    SupplierCategoryDomain(
      id: 'furniture',
      label: 'Furniture & equipment',
      categories: [
        'Office furniture',
        'Kitchen equipment',
        'Hotel & restaurant equipment',
        'Shelving & storage',
        'Appliances (commercial)',
      ],
    ),
    SupplierCategoryDomain(
      id: 'cosmetics',
      label: 'Cosmetics & personal care',
      categories: [
        'Hair care',
        'Skin care',
        'Fragrances',
        'Oral care',
        'Shaving & grooming',
      ],
    ),
    SupplierCategoryDomain(
      id: 'garden_ag',
      label: 'Gardening & agriculture',
      categories: [
        'Seeds & fertilizers',
        'Pesticides & crop care',
        'Irrigation & hoses',
        'Tools & small equipment',
        'Animal feed',
      ],
    ),
    SupplierCategoryDomain(
      id: 'hospitality',
      label: 'Hospitality & restaurant',
      categories: [
        'Tableware & glassware',
        'Kitchen smallwares',
        'Bar supplies',
        'Linen service supplies',
        'Guest amenities',
        'Coffee & tea (HORECA)',
      ],
    ),
  ];

  /// All unique leaf categories (for autocomplete seed).
  static List<String> get allCategories {
    final set = <String>{};
    for (final d in domains) {
      set.addAll(d.categories);
    }
    return set.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }
}
