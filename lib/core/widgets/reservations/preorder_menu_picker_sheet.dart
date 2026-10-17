import 'package:flutter/material.dart';

import '../../mock/mock_reservation_data.dart';
import '../../mock/mock_restaurant_data.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../utils/constants.dart';
import '../../utils/currency_formatter.dart';

/// Category tab order (matches typical menu sections).
const _kCategoryOrder = [
  'Entrées',
  'Plats',
  'Accompagnements',
  'Boissons',
  'Desserts',
  'Suggestions',
];

List<String> _buildCategoryTabs(List<MockMenuItem> menu) {
  final present = menu.map((m) => m.category).toSet();
  final tabs = <String>['Tous'];
  for (final c in _kCategoryOrder) {
    if (present.contains(c)) tabs.add(c);
  }
  for (final c in present) {
    if (!tabs.contains(c)) tabs.add(c);
  }
  return tabs;
}

/// Sum of catalog line quantities matching this menu item (name + category).
int preorderCatalogQtyForMenuItem(
  List<MockDiningReservationPreOrderItem> pre,
  MockMenuItem m,
) {
  var n = 0;
  for (final p in pre) {
    if (p.isCustom) continue;
    final c = p.catalogItem!;
    if (c.name == m.name && c.category == m.category) {
      n += c.quantity;
    }
  }
  return n;
}

/// If a catalog line already matches [m] (name + category), increment quantity;
/// otherwise append a new line with quantity 1.
void mergeOrAddCatalogMenuItemToPreOrder(
  List<MockDiningReservationPreOrderItem> list,
  MockMenuItem m,
) {
  for (var i = 0; i < list.length; i++) {
    final p = list[i];
    if (p.isCustom) continue;
    final c = p.catalogItem!;
    if (c.name == m.name && c.category == m.category) {
      list[i] = MockDiningReservationPreOrderItem.catalog(
        c.copyWith(quantity: c.quantity + 1),
        kitchenSent: p.kitchenSent,
      );
      return;
    }
  }
  list.add(
    MockDiningReservationPreOrderItem.catalog(
      MockOrderItem(
        name: m.name,
        quantity: 1,
        priceHtg: m.priceHtg,
        priceUsd: m.priceUsd,
        category: m.category,
      ),
    ),
  );
}

/// Grid + category tabs for adding menu lines to a reservation pre-order.
/// [getPreOrderItems] is re-read each build so counts stay fresh after [onAdd].
class PreOrderMenuPickerGrid extends StatefulWidget {
  const PreOrderMenuPickerGrid({
    super.key,
    required this.menuItems,
    required this.getPreOrderItems,
    required this.onAdd,
    required this.isDark,
  });

  final List<MockMenuItem> menuItems;
  final List<MockDiningReservationPreOrderItem> Function() getPreOrderItems;
  final void Function(MockMenuItem item) onAdd;
  final bool isDark;

  @override
  State<PreOrderMenuPickerGrid> createState() => _PreOrderMenuPickerGridState();
}

class _PreOrderMenuPickerGridState extends State<PreOrderMenuPickerGrid> {
  late List<String> _tabs;
  String _selectedTab = 'Tous';

  @override
  void initState() {
    super.initState();
    _tabs = _buildCategoryTabs(widget.menuItems);
  }

  @override
  void didUpdateWidget(covariant PreOrderMenuPickerGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.menuItems.length != widget.menuItems.length) {
      _tabs = _buildCategoryTabs(widget.menuItems);
      if (!_tabs.contains(_selectedTab)) {
        _selectedTab = 'Tous';
      }
    }
  }

  List<MockMenuItem> get _filtered {
    if (_selectedTab == 'Tous') return widget.menuItems;
    return widget.menuItems.where((m) => m.category == _selectedTab).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final cardBg = isDark ? AppColors.darkSurface : AppColors.white;
    final textPrimary = isDark ? AppColors.warmWhite : AppColors.nearBlack;
    final muted = isDark ? AppColors.coolGray : AppColors.darkGray;
    final priceColor = isDark ? AppColors.skyBlue : AppColors.primaryBlue;
    final border = isDark ? AppColors.darkBorder : const Color(0xFFE2E2EA);

    final pre = widget.getPreOrderItems();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
          child: Text(
            'Ajouter depuis la carte',
            style: AppTextStyles.h2(color: textPrimary).copyWith(fontSize: 18),
          ),
        ),
        SizedBox(
          height: 34,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _tabs.length,
            separatorBuilder: (_, __) => const SizedBox(width: 4),
            itemBuilder: (context, i) {
              final tab = _tabs[i];
              final sel = tab == _selectedTab;
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => setState(() => _selectedTab = tab),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          tab,
                          style: AppTextStyles.caption(color: sel ? priceColor : muted)
                              .copyWith(
                            fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Container(
                          height: 2,
                          width: 32,
                          decoration: BoxDecoration(
                            color: sel ? priceColor : Colors.transparent,
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) {
              final w = c.maxWidth;
              var cols = (w / 152).floor();
              if (cols < 2) cols = 2;
              if (cols > 5) cols = 5;
              final list = _filtered;
              if (list.isEmpty) {
                return Center(
                  child: Text(
                    'Aucun article dans cette catégorie',
                    style: AppTextStyles.body(color: muted),
                  ),
                );
              }
              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  // Wider vs tall cells — shorter row height.
                  childAspectRatio: 1.42,
                ),
                itemCount: list.length,
                itemBuilder: (context, i) {
                  final m = list[i];
                  final qty = preorderCatalogQtyForMenuItem(pre, m);
                  return _MenuItemCard(
                    item: m,
                    qty: qty,
                    cardBg: cardBg,
                    border: border,
                    textPrimary: textPrimary,
                    priceColor: priceColor,
                    isDark: isDark,
                    onAdd: () => widget.onAdd(m),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _MenuItemCard extends StatelessWidget {
  const _MenuItemCard({
    required this.item,
    required this.qty,
    required this.cardBg,
    required this.border,
    required this.textPrimary,
    required this.priceColor,
    required this.isDark,
    required this.onAdd,
  });

  final MockMenuItem item;
  final int qty;
  final Color cardBg;
  final Color border;
  final Color textPrimary;
  final Color priceColor;
  final bool isDark;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: cardBg,
      elevation: isDark ? 0 : 1,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: border.withValues(alpha: 0.85)),
        ),
        padding: const EdgeInsets.fromLTRB(8, 7, 6, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.caption(color: textPrimary).copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 10.5,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              CurrencyFormatter.local(context, item.priceHtg),
              style: AppTextStyles.caption(color: priceColor).copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 10,
              ),
            ),
            const Spacer(),
            Align(
              alignment: Alignment.bottomRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (qty > 0) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: priceColor.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '×$qty',
                        style: AppTextStyles.caption(color: priceColor).copyWith(
                          fontWeight: FontWeight.w800,
                          fontSize: 10,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  Material(
                    color: AppColors.amber,
                    borderRadius: BorderRadius.circular(5),
                    child: InkWell(
                      onTap: onAdd,
                      borderRadius: BorderRadius.circular(5),
                      child: const SizedBox(
                        width: 26,
                        height: 26,
                        child: Icon(
                          Icons.add,
                          size: 17,
                          color: AppColors.nearBlack,
                        ),
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

/// Opens the full-height menu picker sheet (order-style grid).
Future<void> showPreOrderMenuPickerSheet({
  required BuildContext context,
  required List<MockMenuItem> menuItems,
  required List<MockDiningReservationPreOrderItem> Function() getPreOrderItems,
  required void Function(MockMenuItem item) onItemAdded,
  required bool isDark,
}) {
  final screenH = MediaQuery.sizeOf(context).height;
  final sheetH = screenH * 0.86;

  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: false,
    isScrollControlled: true,
    backgroundColor: isDark ? AppColors.darkSurface : AppColors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) {
      return SizedBox(
        height: sheetH,
        child: StatefulBuilder(
          builder: (context, setModalState) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(
                    left: AppConstants.spacing24,
                    right: AppConstants.spacing8,
                    top: AppConstants.spacing12,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: (isDark ? AppColors.coolGray : AppColors.darkGray)
                                  .withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.close,
                          size: 22,
                          color: isDark ? AppColors.coolGray : AppColors.darkGray,
                        ),
                        onPressed: () {
                          if (sheetContext.mounted) {
                            Navigator.maybePop(sheetContext);
                          }
                        },
                        style: IconButton.styleFrom(
                          padding: const EdgeInsets.all(8),
                          minimumSize: const Size(36, 36),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppConstants.spacing8),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: PreOrderMenuPickerGrid(
                      isDark: isDark,
                      menuItems: menuItems,
                      getPreOrderItems: getPreOrderItems,
                      onAdd: (m) {
                        onItemAdded(m);
                        setModalState(() {});
                        if (sheetContext.mounted) {
                          ScaffoldMessenger.of(sheetContext)
                            ..clearSnackBars()
                            ..showSnackBar(
                              SnackBar(
                                content: Text(
                                  '${m.name} ajouté à la précommande',
                                  style: AppTextStyles.body(
                                    color: isDark
                                        ? AppColors.warmWhite
                                        : AppColors.nearBlack,
                                  ),
                                ),
                                duration: const Duration(milliseconds: 1600),
                                behavior: SnackBarBehavior.floating,
                                margin: const EdgeInsets.fromLTRB(16, 0, 16, 88),
                              ),
                            );
                        }
                      },
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      );
    },
  );
}
