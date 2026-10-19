import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/constants.dart';

/// Calling codes shown beside the flag. Haiti stays first.
class DialCountry {
  const DialCountry(
    this.iso,
    this.dial,
    this.min,
    this.max,
    this.name, [
    this.prefixes = const [],
  ]);

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

class PhoneParts {
  const PhoneParts(this.country, this.national);

  final DialCountry country;
  final String national;
}

/// Split a stored number into the flag's country and the digits beside it.
PhoneParts splitPhone(String raw, {String defaultIso = 'HT'}) {
  final fallback = dialCountry(defaultIso);
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return PhoneParts(fallback, '');

  final candidates = <DialCountry>[];
  for (final country in dialCountries) {
    if (!digits.startsWith(country.dial)) continue;
    final national = digits.substring(country.dial.length);
    if (national.length < country.min || national.length > country.max) continue;
    if (country.prefixes.isNotEmpty &&
        !country.prefixes.any(national.startsWith)) {
      continue;
    }
    candidates.add(country);
  }
  if (candidates.isEmpty) {
    var national = digits;
    if (national.startsWith('0') &&
        national.length - 1 >= fallback.min &&
        national.length - 1 <= fallback.max) {
      national = national.substring(1);
    }
    return PhoneParts(fallback, national);
  }
  final prefixed = candidates.where((country) => country.prefixes.isNotEmpty);
  if (prefixed.isNotEmpty) {
    final country = prefixed.reduce(
      (best, country) =>
          country.dial.length > best.dial.length ? country : best,
    );
    return PhoneParts(country, digits.substring(country.dial.length));
  }
  final unitedStates = candidates.where((country) => country.iso == 'US');
  final country = unitedStates.isNotEmpty ? unitedStates.first : candidates.first;
  return PhoneParts(country, digits.substring(country.dial.length));
}

String formatPhone(DialCountry country, String national) {
  final digits = national.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return '';
  return '+${country.dial} $digits';
}

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

Future<DialCountry?> showCountryPicker(
  BuildContext context, {
  required String selected,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return showModalBottomSheet<DialCountry>(
    context: context,
    isScrollControlled: true,
    backgroundColor: isDark ? AppColors.darkSurface : AppColors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) => _CountrySheet(selected: selected),
  );
}

/// Phone entry with the country flag and calling code on the same row.
class PhoneField extends StatefulWidget {
  const PhoneField({
    super.key,
    required this.controller,
    this.label,
    this.errorText,
    this.enabled = true,
    this.onChanged,
    this.onCountryChanged,
    this.textInputAction,
    this.onEditingComplete,
    this.validator,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String? label;
  final String? errorText;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final ValueChanged<DialCountry>? onCountryChanged;
  final TextInputAction? textInputAction;
  final VoidCallback? onEditingComplete;
  final FormFieldValidator<String>? validator;
  final bool autofocus;

  @override
  State<PhoneField> createState() => _PhoneFieldState();
}

class _PhoneFieldState extends State<PhoneField> {
  final _national = TextEditingController();
  late DialCountry _country;
  var _writing = false;

  @override
  void initState() {
    super.initState();
    final parts = splitPhone(widget.controller.text);
    _country = parts.country;
    _national.text = parts.national;
    widget.controller.addListener(_onExternal);
    _national.addListener(_onNational);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _publish();
    });
  }

  @override
  void didUpdateWidget(PhoneField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onExternal);
      widget.controller.addListener(_onExternal);
      _onExternal();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onExternal);
    _national.removeListener(_onNational);
    _national.dispose();
    super.dispose();
  }

  void _onExternal() {
    if (_writing) return;
    final parts = splitPhone(widget.controller.text);
    if (parts.country.iso == _country.iso && parts.national == _national.text) {
      return;
    }
    _writing = true;
    _national.text = parts.national;
    _writing = false;
    setState(() => _country = parts.country);
  }

  void _onNational() {
    if (_writing) return;
    _publish();
  }

  void _publish() {
    final formatted = formatPhone(_country, _national.text);
    if (widget.controller.text == formatted) return;
    _writing = true;
    widget.controller.text = formatted;
    _writing = false;
    widget.onChanged?.call(formatted);
  }

  Future<void> _pick() async {
    if (!widget.enabled) return;
    final picked = await showCountryPicker(context, selected: _country.iso);
    if (picked == null || !mounted || picked.iso == _country.iso) return;
    setState(() => _country = picked);
    _publish();
    widget.onCountryChanged?.call(picked);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppColors.warmWhite : AppColors.nearBlack;
    final muted = isDark ? AppColors.coolGray : AppColors.darkGray;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null && widget.label!.isNotEmpty) ...[
          Text(widget.label!, style: AppTextStyles.inputLabel(color: muted)),
          const SizedBox(height: AppConstants.spacing4),
        ],
        TextFormField(
          controller: _national,
          enabled: widget.enabled,
          autofocus: widget.autofocus,
          keyboardType: TextInputType.phone,
          textInputAction: widget.textInputAction,
          onEditingComplete: widget.onEditingComplete,
          validator: widget.validator,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s\-().]')),
            LengthLimitingTextInputFormatter(18),
          ],
          style: AppTextStyles.body(color: textColor),
          decoration: InputDecoration(
            hintText: 'Numéro',
            errorText: widget.errorText,
            prefixIcon: InkWell(
              onTap: widget.enabled ? _pick : null,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.only(left: 12, right: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_country.flag, style: flagStyle),
                    const SizedBox(width: 6),
                    Text('+${_country.dial}', style: AppTextStyles.body(color: textColor)),
                    Icon(Icons.expand_more, size: 18, color: muted),
                  ],
                ),
              ),
            ),
            prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 48),
          ),
        ),
      ],
    );
  }
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
        if (_fold('${country.name} ${country.iso} ${country.dial}').contains(folded))
          country,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final rows = _visible;
    final height = MediaQuery.sizeOf(context).height * 0.72;
    final titleColor = isDark ? AppColors.warmWhite : AppColors.nearBlack;
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
                        color: active ? AppColors.primaryBlue : titleColor,
                      ),
                    ),
                    trailing: Text(
                      '+${country.dial}',
                      style: AppTextStyles.body(
                        color: isDark ? AppColors.coolGray : AppColors.darkGray,
                      ),
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
