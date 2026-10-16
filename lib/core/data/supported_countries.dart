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
    name: 'Haiti',
    currencyCode: 'HTG',
    currencyName: 'Haitian Gourde',
  ),
  SupportedCountry(
    code: 'US',
    name: 'United States',
    currencyCode: 'USD',
    currencyName: 'US Dollar',
  ),
  SupportedCountry(
    code: 'DO',
    name: 'Dominican Republic',
    currencyCode: 'DOP',
    currencyName: 'Dominican Peso',
  ),
  SupportedCountry(
    code: 'JM',
    name: 'Jamaica',
    currencyCode: 'JMD',
    currencyName: 'Jamaican Dollar',
  ),
  SupportedCountry(
    code: 'BS',
    name: 'Bahamas',
    currencyCode: 'BSD',
    currencyName: 'Bahamian Dollar',
  ),
  SupportedCountry(
    code: 'BB',
    name: 'Barbados',
    currencyCode: 'BBD',
    currencyName: 'Barbados Dollar',
  ),
  SupportedCountry(
    code: 'TT',
    name: 'Trinidad and Tobago',
    currencyCode: 'TTD',
    currencyName: 'Trinidad and Tobago Dollar',
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
