/// Country + default local ISO 4217 for registration / settings.
class SupportedCountry {
  final String code;
  final String name;
  final String currencyCode;
  final String currencyName;

  const SupportedCountry({
    required this.code,
    required this.name,
    required this.currencyCode,
    required this.currencyName,
  });
}

/// Curated list — expand as you onboard more markets.
const List<SupportedCountry> kSupportedCountries = [
  SupportedCountry(
    code: 'HT',
    name: 'Haïti',
    currencyCode: 'HTG',
    currencyName: 'Gourde haïtienne',
  ),
  SupportedCountry(
    code: 'US',
    name: 'États-Unis',
    currencyCode: 'USD',
    currencyName: 'Dollar américain',
  ),
  SupportedCountry(
    code: 'DO',
    name: 'République dominicaine',
    currencyCode: 'DOP',
    currencyName: 'Peso dominicain',
  ),
  SupportedCountry(
    code: 'JM',
    name: 'Jamaïque',
    currencyCode: 'JMD',
    currencyName: 'Dollar jamaïcain',
  ),
  SupportedCountry(
    code: 'BS',
    name: 'Bahamas',
    currencyCode: 'BSD',
    currencyName: 'Dollar bahaméen',
  ),
  SupportedCountry(
    code: 'BB',
    name: 'Barbados',
    currencyCode: 'BBD',
    currencyName: 'Dollar barbadien',
  ),
  SupportedCountry(
    code: 'TT',
    name: 'Trinité-et-Tobago',
    currencyCode: 'TTD',
    currencyName: 'Dollar de Trinité-et-Tobago',
  ),
];

SupportedCountry? countryByCode(String? code) {
  if (code == null || code.isEmpty) return null;
  final u = code.toUpperCase();
  for (final c in kSupportedCountries) {
    if (c.code == u) return c;
  }
  return null;
}
