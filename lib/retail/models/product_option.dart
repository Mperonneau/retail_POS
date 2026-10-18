/// A priced choice inside a product option (for example « Grand » + 20 HTG).
class ProductOptionChoice {
  const ProductOptionChoice({
    required this.id,
    required this.name,
    this.priceDeltaHtg = 0,
  });

  final String id;
  final String name;
  final double priceDeltaHtg;
}

enum ProductOptionKind { size, color, extra, other }

/// One option on a product. [required] means the cashier must pick at least
/// one choice. [multiple] allows more than one choice.
class ProductOptionGroup {
  const ProductOptionGroup({
    required this.id,
    required this.name,
    required this.kind,
    required this.required,
    required this.multiple,
    required this.choices,
  });

  final String id;
  final String name;
  final ProductOptionKind kind;
  final bool required;
  final bool multiple;
  final List<ProductOptionChoice> choices;
}

class ProductOptionPreset {
  const ProductOptionPreset({
    required this.kind,
    required this.label,
    required this.multiple,
    required this.required,
    this.suggestions = const [],
  });

  final ProductOptionKind kind;
  final String label;
  final bool multiple;
  final bool required;
  final List<String> suggestions;

  static const List<ProductOptionPreset> all = [
    ProductOptionPreset(
      kind: ProductOptionKind.size,
      label: 'Taille',
      multiple: false,
      required: true,
      suggestions: ['Petit', 'Moyen', 'Grand'],
    ),
    ProductOptionPreset(
      kind: ProductOptionKind.color,
      label: 'Couleur',
      multiple: false,
      required: false,
      suggestions: ['Noir', 'Blanc', 'Bleu', 'Rouge'],
    ),
    ProductOptionPreset(
      kind: ProductOptionKind.extra,
      label: 'Supplément',
      multiple: true,
      required: false,
    ),
    ProductOptionPreset(
      kind: ProductOptionKind.other,
      label: 'Autre',
      multiple: false,
      required: true,
    ),
  ];
}

int _optionSeq = 0;

String newProductOptionId(String prefix) =>
    '$prefix-${DateTime.now().microsecondsSinceEpoch}-${_optionSeq++}';
