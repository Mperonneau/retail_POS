import 'package:flutter/material.dart';
import 'package:retail_pos/core/theme/app_colors.dart';
import 'package:retail_pos/core/theme/app_text_styles.dart';

/// Calling codes shown beside the flag. Haiti stays first.
class DialCountry {
  const DialCountry(this.iso, this.dial, this.min, this.max, this.name, [this.prefixes = const []]);

  final String iso;
  final String dial;
  final int min;
  final int max;
  final String name;
  final List<String> prefixes;

  String get flag {
    return String.fromCharCodes([
      for (final unit in iso.toUpperCase().codeUnits)
        if (unit >= 65 && unit <= 90) unit + 127397,
    ]);
  }
}

const dialCountries = <DialCountry>[
  DialCountry('HT', '509', 8, 8, 'Haïti'),
  DialCountry('DE', '49', 10, 11, 'Allemagne'),
  DialCountry('AR', '54', 10, 10, 'Argentine'),
  DialCountry('BS', '1', 10, 10, 'Bahamas', ['242']),
  DialCountry('BE', '32', 8, 9, 'Belgique'),
  DialCountry('BR', '55', 10, 11, 'Brésil'),
  DialCountry('CA', '1', 10, 10, 'Canada'),
  DialCountry('CL', '56', 9, 9, 'Chili'),
  DialCountry('CO', '57', 10, 10, 'Colombie'),
  DialCountry('CU', '53', 8, 8, 'Cuba'),
  DialCountry('ES', '34', 9, 9, 'Espagne'),
  DialCountry('US', '1', 10, 10, 'États-Unis'),
  DialCountry('FR', '33', 9, 9, 'France'),
  DialCountry('GP', '590', 9, 9, 'Guadeloupe'),
  DialCountry('GY', '592', 7, 7, 'Guyana'),
  DialCountry('GF', '594', 9, 9, 'Guyane'),
  DialCountry('IT', '39', 9, 10, 'Italie'),
  DialCountry('JM', '1', 10, 10, 'Jamaïque', ['658', '876']),
  DialCountry('MQ', '596', 9, 9, 'Martinique'),
  DialCountry('MX', '52', 10, 10, 'Mexique'),
  DialCountry('PA', '507', 7, 8, 'Panama'),
  DialCountry('NL', '31', 9, 9, 'Pays-Bas'),
  DialCountry('PE', '51', 9, 9, 'Pérou'),
  DialCountry('PR', '1', 10, 10, 'Porto Rico', ['787', '939']),
  DialCountry('PT', '351', 9, 9, 'Portugal'),
  DialCountry('DO', '1', 10, 10, 'République dominicaine', ['809', '829', '849']),
  DialCountry('GB', '44', 10, 10, 'Royaume-Uni'),
  DialCountry('BL', '590', 9, 9, 'Saint-Barthélemy'),
  DialCountry('MF', '590', 9, 9, 'Saint-Martin'),
  DialCountry('CH', '41', 9, 9, 'Suisse'),
  DialCountry('SR', '597', 6, 7, 'Suriname'),
  DialCountry('TT', '1', 10, 10, 'Trinité-et-Tobago', ['868']),
  DialCountry('VE', '58', 10, 10, 'Venezuela'),
];

DialCountry dialCountry(String iso) {
  final code = iso.toUpperCase();
  for (final country in dialCountries) {
    if (country.iso == code) return country;
  }
  return dialCountries.first;
}

String countryName(String iso) => iso.isEmpty ? '' : dialCountry(iso).name;

/// Phone step state kept while the visitor moves from the number to the code.
class LoginDraft {
  String iso = 'HT';
  String national = '';
  String signupToken = '';

  DialCountry get country => dialCountry(iso);

  String get displayPhone {
    final digits = national.replaceAll(RegExp(r'\D'), '');
    return '+${country.dial} $digits';
  }

  void clear() {
    iso = 'HT';
    national = '';
    signupToken = '';
  }
}

final loginDraft = LoginDraft();

const flagStyle = TextStyle(
  fontSize: 22,
  height: 1.2,
  inherit: false,
  fontFamily: 'Noto Color Emoji',
  fontFamilyFallback: [
    'Apple Color Emoji',
    'Segoe UI Emoji',
    'Noto Color Emoji',
    'sans-serif',
  ],
);

Future<DialCountry?> showCountryPicker(BuildContext context, {required String selected}) {
  return showModalBottomSheet<DialCountry>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) => _CountrySheet(selected: selected),
  );
}

class _CountrySheet extends StatefulWidget {
  const _CountrySheet({required this.selected});

  final String selected;

  @override
  State<_CountrySheet> createState() => _CountrySheetState();
}

class _CountrySheetState extends State<_CountrySheet> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<DialCountry> get _visible {
    final folded = _fold(_query.text);
    if (folded.isEmpty) return dialCountries;
    return [
      for (final country in dialCountries)
        if (_fold('${country.name} ${country.iso} ${country.dial}').contains(folded)) country,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final rows = _visible;
    final height = MediaQuery.sizeOf(context).height * 0.72;
    return SafeArea(
      child: SizedBox(
        height: height,
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFD5D1C8),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: _query,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'Pays ou indicatif',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: rows.length,
                itemBuilder: (context, index) {
                  final country = rows[index];
                  final active = country.iso == widget.selected;
                  return ListTile(
                    leading: Text(country.flag, style: flagStyle),
                    title: Text(
                      country.name,
                      style: AppTextStyles.body(
                        color: active ? AppColors.primaryBlue : AppColors.nearBlack,
                      ),
                    ),
                    trailing: Text(
                      '+${country.dial}',
                      style: AppTextStyles.body(color: AppColors.darkGray),
                    ),
                    onTap: () => Navigator.pop(context, country),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _fold(String value) {
  const from = 'àáâãäåèéêëìíîïòóôõöùúûüýÿçñ';
  const to = 'aaaaaaeeeeiiiiooooouuuuyycn';
  final buffer = StringBuffer();
  for (final char in value.toLowerCase().split('')) {
    final index = from.indexOf(char);
    buffer.write(index >= 0 ? to[index] : char);
  }
  return buffer.toString();
}
