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
      label: 'Alimentation et boissons',
      categories: [
        'Riz et céréales',
        'Farine et pâtisserie',
        'Huiles et matières grasses',
        'Sucre et édulcorants',
        'Sel et épices',
        'Épicerie sèche',
        'Conserves et produits emballés',
        'Fruits et légumes frais',
        'Viande et volaille',
        'Fruits de mer',
        'Produits laitiers et œufs',
        'Surgelés',
        'Boulangerie',
        'Snacks et confiserie',
        'Eau en bouteille et boissons',
        'Boissons gazeuses et jus',
        'Bière, vin et spiritueux',
        'Café et thé',
        'Ingrédients HORECA',
      ],
    ),
    SupplierCategoryDomain(
      id: 'health_pharma',
      label: 'Santé et pharmacie',
      categories: [
        'Médicaments et vente libre',
        'Vitamines et compléments',
        'Premiers secours et fournitures médicales',
        'Puériculture et hygiène',
        'Hygiène de base',
        'Matériel médical (non spécialisé)',
      ],
    ),
    SupplierCategoryDomain(
      id: 'education_office',
      label: 'Éducation et bureau',
      categories: [
        'Fournitures scolaires',
        'Papeterie et papier',
        'Mobilier de bureau',
        'Fournitures d\'impression',
        'Livres et fournitures scolaires',
      ],
    ),
    SupplierCategoryDomain(
      id: 'construction',
      label: 'Construction et matériaux',
      categories: [
        'Ciment et béton',
        'Granulats et sable',
        'Acier et fer à béton',
        'Bois',
        'Matériaux de toiture',
        'Peinture et revêtements',
        'Plaques et panneaux',
        'Fenêtres et portes',
        'Carrelage et sols',
        'Isolation',
      ],
    ),
    SupplierCategoryDomain(
      id: 'electrical',
      label: 'Électricité et éclairage',
      categories: [
        'Câbles et fils',
        'Interrupteurs et prises',
        'Disjoncteurs et tableaux',
        'Luminaires et ampoules',
        'Générateurs et secours électrique',
        'Ventilateurs et ventilation',
        'Composants solaires',
      ],
    ),
    SupplierCategoryDomain(
      id: 'plumbing',
      label: 'Plomberie et sanitaire',
      categories: [
        'Tuyaux et raccords',
        'Vannes et robinets',
        'Pompes et systèmes d\'eau',
        'Toilettes et lavabos',
        'Réservoirs et stockage d\'eau',
        'Évacuation et gouttières',
      ],
    ),
    SupplierCategoryDomain(
      id: 'hardware_tools',
      label: 'Quincaillerie et outils',
      categories: [
        'Outils à main',
        'Outils électriques',
        'Visserie et fixations',
        'Serrures et sécurité',
        'Soudure et découpe',
        'Équipement de protection',
        'Échelles et levage',
      ],
    ),
    SupplierCategoryDomain(
      id: 'packaging',
      label: 'Emballage et consommables',
      categories: [
        'Sacs',
        'Cartons et boîtes',
        'Film et emballage plastique',
        'Étiquettes et ruban',
        'Gobelets et assiettes jetables',
        'Jetables pour la restauration',
      ],
    ),
    SupplierCategoryDomain(
      id: 'cleaning',
      label: 'Nettoyage et hygiène',
      categories: [
        'Produits ménagers',
        'Produits de blanchisserie',
        'Fournitures d\'entretien',
        'Serpillères et balais',
        'Sacs poubelle et bacs',
        'Désodorisants',
      ],
    ),
    SupplierCategoryDomain(
      id: 'textile',
      label: 'Textile et vêtements',
      categories: [
        'Uniformes et vêtements de travail',
        'Linge de lit et de bain',
        'Serviettes et torchons',
        'Tissus et mercerie',
        'Chaussures (gros / travail)',
      ],
    ),
    SupplierCategoryDomain(
      id: 'it_telecom',
      label: 'Informatique et télécom',
      categories: [
        'Ordinateurs et tablettes',
        'Équipement réseau',
        'Téléphones et accessoires',
        'Matériel de caisse et codes-barres',
        'Câbles et adaptateurs',
        'Logiciels et abonnements',
      ],
    ),
    SupplierCategoryDomain(
      id: 'transport',
      label: 'Transport et carburant',
      categories: [
        'Carburant et lubrifiants',
        'Pièces auto (général)',
        'Pneus et batteries',
        'Logistique et fret',
      ],
    ),
    SupplierCategoryDomain(
      id: 'furniture',
      label: 'Meubles et équipement',
      categories: [
        'Mobilier de bureau',
        'Équipement de cuisine',
        'Équipement hôtel et restaurant',
        'Rayonnages et stockage',
        'Appareils (professionnel)',
      ],
    ),
    SupplierCategoryDomain(
      id: 'cosmetics',
      label: 'Cosmétiques et soins',
      categories: [
        'Soins capillaires',
        'Soins de la peau',
        'Parfums',
        'Hygiène bucco-dentaire',
        'Rasage et soins',
      ],
    ),
    SupplierCategoryDomain(
      id: 'garden_ag',
      label: 'Jardinage et agriculture',
      categories: [
        'Semences et engrais',
        'Pesticides et protection des cultures',
        'Irrigation et tuyaux',
        'Outils et petit matériel',
        'Aliments pour animaux',
      ],
    ),
    SupplierCategoryDomain(
      id: 'hospitality',
      label: 'Hôtellerie et restaurant',
      categories: [
        'Vaisselle et verrerie',
        'Petit matériel de cuisine',
        'Fournitures de bar',
        'Linge et fournitures',
        'Articles de courtoisie',
        'Café et thé (HORECA)',
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
