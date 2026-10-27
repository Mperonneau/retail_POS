import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_close_button.dart';
import 'business_categories.dart';

/// Searchable checklist. A shop can keep several categories.
Future<void> showBusinessCategoryPicker(
  BuildContext context, {
  required List<String> selected,
  required ValueChanged<List<String>> onChanged,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) =>
        _CategoryPicker(selected: selected, onChanged: onChanged),
  );
}

class _CategoryPicker extends StatefulWidget {
  const _CategoryPicker({required this.selected, required this.onChanged});

  final List<String> selected;
  final ValueChanged<List<String>> onChanged;

  @override
  State<_CategoryPicker> createState() => _CategoryPickerState();
}

class _CategoryPickerState extends State<_CategoryPicker> {
  final _search = TextEditingController();
  late final List<String> _selected = [...widget.selected];
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _toggle(String name) {
    setState(() {
      if (_selected.contains(name)) {
        _selected.remove(name);
      } else {
        _selected.add(name);
      }
    });
    widget.onChanged(List<String>.unmodifiable(_selected));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final query = _fold(_query);
    final groups = [
      for (final group in businessCategoryGroups)
        if (query.isEmpty ||
            _fold(group.label).contains(query) ||
            group.names.any((name) => _fold(name).contains(query)))
          (
            group: group,
            names: query.isEmpty || _fold(group.label).contains(query)
                ? group.names
                : group.names
                      .where((name) => _fold(name).contains(query))
                      .toList(),
          ),
    ];
    final surface = isDark ? AppColors.darkSurface : AppColors.white;
    final ink = isDark ? AppColors.warmWhite : AppColors.nearBlack;
    return Dialog(
      backgroundColor: surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 640),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Catégories',
                      style: AppTextStyles.h2(color: ink),
                    ),
                  ),
                  AppCloseButton(onPressed: () => Navigator.of(context).pop()),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: TextField(
                controller: _search,
                autofocus: true,
                onChanged: (value) => setState(() => _query = value),
                style: AppTextStyles.body(color: ink),
                decoration: InputDecoration(
                  hintText: 'Rechercher une catégorie',
                  prefixIcon: const Icon(Icons.search_rounded),
                  isDense: true,
                  filled: true,
                  fillColor: isDark
                      ? AppColors.darkBackground
                      : AppColors.warmOffWhite,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Expanded(
              child: groups.isEmpty
                  ? Center(
                      child: Text(
                        'Aucune catégorie',
                        style: AppTextStyles.body(
                          color: isDark
                              ? AppColors.coolGray
                              : AppColors.darkGray,
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                      children: [
                        for (final entry in groups) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
                            child: Text(
                              entry.group.label,
                              style: AppTextStyles.caption(
                                color: isDark
                                    ? AppColors.coolGray
                                    : AppColors.darkGray,
                              ).copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          for (final name in entry.names)
                            CheckboxListTile(
                              value: _selected.contains(name),
                              onChanged: (_) => _toggle(name),
                              dense: true,
                              controlAffinity: ListTileControlAffinity.leading,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              title: Text(
                                name,
                                style: AppTextStyles.body(color: ink),
                              ),
                            ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

String _fold(String value) {
  const accents = {
    'à': 'a',
    'â': 'a',
    'ä': 'a',
    'á': 'a',
    'ç': 'c',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',
    'î': 'i',
    'ï': 'i',
    'í': 'i',
    'ô': 'o',
    'ö': 'o',
    'ó': 'o',
    'ù': 'u',
    'û': 'u',
    'ü': 'u',
    'ú': 'u',
    'ÿ': 'y',
    'ñ': 'n',
  };
  final buffer = StringBuffer();
  for (final rune in value.toLowerCase().runes) {
    final char = String.fromCharCode(rune);
    buffer.write(accents[char] ?? char);
  }
  return buffer.toString();
}
