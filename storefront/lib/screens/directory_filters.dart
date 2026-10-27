import 'package:flutter/material.dart';
import 'package:retail_pos/core/theme/app_colors.dart';
import 'package:retail_pos/core/theme/app_text_styles.dart';
import 'package:retail_pos/core/utils/constants.dart';
import 'package:retail_pos/core/widgets/app_button.dart';
import 'package:retail_pos/core/widgets/app_close_button.dart';

/// Right-hand filter panel. Full screen on a phone.
Future<void> showDirectoryFilters(
  BuildContext context, {
  required List<String> departments,
  required List<String> categories,
  required Set<String> selectedDepartments,
  required Set<String> selectedCategories,
  required void Function(Set<String> departments, Set<String> categories)
  onChanged,
}) {
  final width = MediaQuery.sizeOf(context).width;
  final fullScreen = width < AppConstants.mobileBreakpoint;
  final panelWidth = AppConstants.sidePanelWidth(width, 420);
  return Navigator.of(context, rootNavigator: true).push<void>(
    PageRouteBuilder<void>(
      opaque: fullScreen,
      fullscreenDialog: fullScreen,
      barrierDismissible: !fullScreen,
      barrierColor: fullScreen ? null : Colors.black.withValues(alpha: 0.45),
      barrierLabel: 'Fermer',
      transitionDuration: AppConstants.animNormal,
      reverseTransitionDuration: AppConstants.animNormal,
      pageBuilder: (ctx, animation, secondary) {
        final page = Scaffold(
          backgroundColor: AppColors.white,
          body: SafeArea(
            child: _FilterPanel(
              departments: departments,
              categories: categories,
              selectedDepartments: selectedDepartments,
              selectedCategories: selectedCategories,
              onChanged: onChanged,
            ),
          ),
        );
        if (fullScreen) return page;
        return Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: panelWidth,
            height: MediaQuery.sizeOf(ctx).height,
            child: Material(
              elevation: 16,
              shadowColor: Colors.black.withValues(alpha: 0.35),
              color: AppColors.white,
              child: page,
            ),
          ),
        );
      },
      transitionsBuilder: (ctx, animation, secondary, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      },
    ),
  );
}

class _FilterPanel extends StatefulWidget {
  const _FilterPanel({
    required this.departments,
    required this.categories,
    required this.selectedDepartments,
    required this.selectedCategories,
    required this.onChanged,
  });

  final List<String> departments;
  final List<String> categories;
  final Set<String> selectedDepartments;
  final Set<String> selectedCategories;
  final void Function(Set<String> departments, Set<String> categories)
  onChanged;

  @override
  State<_FilterPanel> createState() => _FilterPanelState();
}

class _FilterPanelState extends State<_FilterPanel> {
  late final Set<String> _departments = {...widget.selectedDepartments};
  late final Set<String> _categories = {...widget.selectedCategories};

  void _publish() {
    widget.onChanged({..._departments}, {..._categories});
  }

  Future<void> _pickDepartments() async {
    await _pick(
      title: 'Département',
      options: widget.departments,
      selected: _departments,
    );
  }

  Future<void> _pickCategories() async {
    await _pick(
      title: 'Catégorie',
      options: widget.categories,
      selected: _categories,
      searchable: true,
      emptyMessage: 'Aucune catégorie n\'est utilisée pour le moment.',
    );
  }

  Future<void> _pick({
    required String title,
    required List<String> options,
    required Set<String> selected,
    bool searchable = false,
    String? emptyMessage,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) => _ChoiceSheet(
        title: title,
        options: options,
        selected: selected,
        searchable: searchable,
        emptyMessage: emptyMessage,
        onChanged: () {
          setState(() {});
          _publish();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final active = _departments.isNotEmpty || _categories.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Filtres',
                  style: AppTextStyles.h1(
                    color: AppColors.nearBlack,
                  ).copyWith(fontSize: 22),
                ),
              ),
              AppCloseButton(onPressed: () => Navigator.of(context).pop()),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(
            'Plusieurs départements et catégories peuvent être combinés.',
            style: AppTextStyles.caption(),
          ),
        ),
        _FilterRow(
          title: 'Département',
          value: _summary(_departments),
          onTap: _pickDepartments,
        ),
        const Divider(height: 1, color: Color(0xFFF0EEE9)),
        _FilterRow(
          title: 'Catégorie',
          value: _summary(_categories),
          onTap: _pickCategories,
        ),
        const Divider(height: 1, color: Color(0xFFF0EEE9)),
        const Spacer(),
        if (active)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: AppButton(
              label: 'Effacer les filtres',
              variant: AppButtonVariant.secondary,
              onPressed: () {
                setState(() {
                  _departments.clear();
                  _categories.clear();
                });
                _publish();
              },
            ),
          ),
      ],
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.title,
    required this.value,
    required this.onTap,
  });

  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTextStyles.body(
                      color: AppColors.nearBlack,
                    ).copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(value, style: AppTextStyles.caption()),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.darkGray),
          ],
        ),
      ),
    );
  }
}

String _summary(Set<String> selected) {
  if (selected.isEmpty) return 'Tous';
  final names = selected.toList();
  if (names.length <= 2) return names.join(', ');
  return '${names.take(2).join(', ')} +${names.length - 2}';
}

class _ChoiceSheet extends StatefulWidget {
  const _ChoiceSheet({
    required this.title,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.searchable = false,
    this.emptyMessage,
  });

  final String title;
  final List<String> options;
  final Set<String> selected;
  final VoidCallback onChanged;
  final bool searchable;
  final String? emptyMessage;

  @override
  State<_ChoiceSheet> createState() => _ChoiceSheetState();
}

class _ChoiceSheetState extends State<_ChoiceSheet> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _fold(_query);
    final options = query.isEmpty
        ? widget.options
        : widget.options.where((name) => _fold(name).contains(query)).toList();
    final height = MediaQuery.sizeOf(context).height * 0.72;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: height,
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE0DDD6),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: AppTextStyles.h2(color: AppColors.nearBlack),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Terminé'),
                  ),
                ],
              ),
            ),
            if (widget.searchable)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: TextField(
                  controller: _search,
                  onChanged: (value) => setState(() => _query = value),
                  decoration: InputDecoration(
                    hintText: 'Rechercher',
                    prefixIcon: const Icon(Icons.search_rounded),
                    isDense: true,
                    filled: true,
                    fillColor: AppColors.warmOffWhite,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            Expanded(
              child: options.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          widget.emptyMessage ?? 'Aucun résultat',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.body(color: AppColors.darkGray),
                        ),
                      ),
                    )
                  : ListView(
                      children: [
                        for (final name in options)
                          CheckboxListTile(
                            value: widget.selected.contains(name),
                            onChanged: (checked) {
                              setState(() {
                                if (checked == true) {
                                  widget.selected.add(name);
                                } else {
                                  widget.selected.remove(name);
                                }
                              });
                              widget.onChanged();
                            },
                            controlAffinity: ListTileControlAffinity.leading,
                            title: Text(
                              name,
                              style: AppTextStyles.body(
                                color: AppColors.nearBlack,
                              ),
                            ),
                          ),
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
