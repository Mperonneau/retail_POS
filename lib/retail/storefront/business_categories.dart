/// Enterprise types a Haitian shop can show on its vitrine.
/// The same names are accepted by the payments server. Keep the two lists aligned.
class BusinessCategoryGroup {
  const BusinessCategoryGroup(this.label, this.names);

  final String label;
  final List<String> names;
}

const businessCategoryGroups = <BusinessCategoryGroup>[
  BusinessCategoryGroup('Alimentation', [
    'Supermarché',
    'Supérette',
    'Épicerie',
    'Magasin de vivres',
    'Boulangerie',
    'Pâtisserie',
    'Boucherie',
    'Charcuterie',
    'Poissonnerie',
    'Fruits et légumes',
    'Produits frais et laitiers',
    'Épicerie fine',
    'Dépôt alimentaire',
  ]),
  BusinessCategoryGroup('Boissons', [
    'Dépôt de boissons',
    'Boissons alcoolisées',
    'Eau en bouteille et bonbonnes',
    'Glace et surgelés',
  ]),
  BusinessCategoryGroup('Mode', [
    'Vêtements',
    'Friperie',
    'Chaussures',
    'Sacs et maroquinerie',
    'Tissus et mercerie',
    'Uniformes',
    'Bijouterie',
    'Horlogerie',
    'Articles de cérémonie',
  ]),
  BusinessCategoryGroup('Maison', [
    'Meubles',
    'Literie',
    'Linge de maison',
    'Électroménager',
    'Vaisselle et articles de cuisine',
    'Décoration',
  ]),
  BusinessCategoryGroup('Construction', [
    'Matériaux de construction',
    'Quincaillerie',
    'Bois et menuiserie',
    'Toiture',
    'Peinture',
    'Plomberie et sanitaire',
    'Électricité du bâtiment',
    'Carrelage et revêtements',
    'Portes et fenêtres',
    'Outillage',
  ]),
  BusinessCategoryGroup('Énergie', [
    'Générateurs, onduleurs et batteries',
    'Énergie solaire',
    'Gaz domestique',
    'Station-service',
  ]),
  BusinessCategoryGroup('Électronique', [
    'Téléphones et accessoires',
    'Informatique',
    'Électronique et audiovisuel',
    'Pièces électroniques',
  ]),
  BusinessCategoryGroup('Santé et beauté', [
    'Pharmacie',
    'Parapharmacie',
    'Matériel médical',
    'Optique',
    'Cosmétiques et soins',
    'Parfumerie',
    'Salon de coiffure',
    'Institut de beauté',
  ]),
  BusinessCategoryGroup('Enfants', [
    'Articles pour bébé',
    'Jouets',
    'Fournitures scolaires',
  ]),
  BusinessCategoryGroup('Auto et moto', [
    'Pièces automobiles',
    'Pièces moto',
    'Pneus',
    'Lubrifiants',
    'Accessoires auto',
    'Vélos',
  ]),
  BusinessCategoryGroup('Agriculture et élevage', [
    'Intrants agricoles',
    'Semences et plants',
    'Matériel agricole',
    'Irrigation',
    'Aliments pour animaux',
    'Produits vétérinaires',
    'Matériel de pêche',
  ]),
  BusinessCategoryGroup('Bureau et impression', [
    'Librairie',
    'Papeterie',
    'Fournitures de bureau',
    'Imprimerie',
  ]),
  BusinessCategoryGroup('Loisirs', [
    'Articles de sport',
    'Musique et instruments',
    'Artisanat et souvenirs',
    'Jeux',
  ]),
  BusinessCategoryGroup('Cadeaux et événements', [
    'Cadeaux',
    'Fleurs',
    'Location pour événements',
    'Traiteur',
  ]),
  BusinessCategoryGroup('Autres commerces', [
    'Produits d\'entretien',
    'Emballages',
    'Animalerie',
    'Sécurité et serrurerie',
    'Pompes funèbres',
    'Magasin général',
    'Grossiste',
    'Import-export',
  ]),
];

/// Every selectable category, in catalogue order.
final List<String> businessCategories = [
  for (final group in businessCategoryGroups) ...group.names,
];

final Set<String> businessCategoryNames = businessCategories.toSet();

/// Keeps known names, in the order the shop chose them.
List<String> sanitizeBusinessCategories(Object? raw) {
  if (raw is! List) return const [];
  final chosen = <String>[];
  for (final item in raw) {
    final name = '$item'.trim();
    if (businessCategoryNames.contains(name) && !chosen.contains(name)) {
      chosen.add(name);
    }
  }
  return chosen;
}
