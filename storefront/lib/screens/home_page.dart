import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:retail_pos/core/theme/app_colors.dart';
import 'package:retail_pos/core/theme/app_text_styles.dart';
import 'package:retail_pos/core/utils/constants.dart';
import 'package:web/web.dart' as web;

import '../api.dart';
import '../favorites.dart';
import '../widgets.dart';
import 'directory_filters.dart';

/// Directory of every open vitrine, searchable and filtered by department and category.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _api = StorefrontApi();
  final _search = TextEditingController();
  ShopDirectory? _directory;
  String? _error;
  final Set<String> _departments = {};
  final Set<String> _categories = {};
  String _query = '';

  @override
  void initState() {
    super.initState();
    web.document.title = 'Boutiques';
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final directory = await _api.directory();
      if (!mounted) return;
      setState(() {
        _directory = directory;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        if (_directory == null) _error = e.message;
      });
    }
  }

  List<ShopCard> get _visible {
    final directory = _directory;
    final shops = directory?.results ?? const <ShopCard>[];
    final known = directory?.categories.toSet() ?? const <String>{};
    final categories = _categories.where(known.contains).toSet();
    final query = _query.trim().toLowerCase();
    return shops.where((shop) {
      if (_departments.isNotEmpty && !_departments.contains(shop.department)) {
        return false;
      }
      if (categories.isNotEmpty && !shop.categories.any(categories.contains)) {
        return false;
      }
      if (query.isEmpty) return true;
      return shop.name.toLowerCase().contains(query) ||
          shop.city.toLowerCase().contains(query) ||
          shop.department.toLowerCase().contains(query) ||
          shop.description.toLowerCase().contains(query) ||
          shop.categories.any((name) => name.toLowerCase().contains(query));
    }).toList();
  }

  int get _filterCount =>
      _departments.length +
      _categories
          .where((_directory?.categories.toSet() ?? const {}).contains)
          .length;

  @override
  Widget build(BuildContext context) {
    final directory = _directory;
    if (directory == null) {
      return Scaffold(
        body: _error == null
            ? const LoadingView()
            : MessageView(
                icon: Icons.wifi_off_rounded,
                title: 'Chargement impossible',
                message: _error!,
                actionLabel: 'Réessayer',
                onAction: _load,
              ),
      );
    }
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 1000 ? 3 : (width >= 680 ? 2 : 1);
    final shops = _visible;
    final filtering = _query.trim().isNotEmpty || _filterCount > 0;
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _Intro(width: width)),
            SliverToBoxAdapter(
              child: _SearchField(
                controller: _search,
                filterCount: _filterCount,
                onChanged: (value) => setState(() => _query = value),
                onFilter: () => showDirectoryFilters(
                  context,
                  departments: directory.departments,
                  categories: directory.categories,
                  selectedDepartments: _departments,
                  selectedCategories: _categories,
                  onChanged: (departments, categories) => setState(() {
                    _departments
                      ..clear()
                      ..addAll(departments);
                    _categories
                      ..clear()
                      ..addAll(categories);
                  }),
                ),
              ),
            ),
            if (shops.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: MessageView(
                  icon: Icons.storefront_outlined,
                  title: filtering
                      ? 'Aucune boutique'
                      : 'Aucune boutique en ligne',
                  message: filtering
                      ? 'Essayez un autre mot, un autre département ou une autre catégorie.'
                      : 'Les boutiques apparaissent ici dès que leur vitrine est activée.',
                ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  _side(width),
                  AppConstants.spacing16,
                  _side(width),
                  AppConstants.spacing32,
                ),
                sliver: SliverGrid.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    childAspectRatio: columns == 1
                        ? 1.72
                        : (columns == 2 ? 1.12 : 0.92),
                  ),
                  itemCount: shops.length,
                  itemBuilder: (context, index) => _ShopTile(
                    shop: shops[index],
                    onTap: () => context.go('/${shops[index].slug}'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

double _side(double width) {
  const max = 1080.0;
  return width > max + 32 ? (width - max) / 2 : AppConstants.spacing16;
}

class _Intro extends StatelessWidget {
  const _Intro({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(_side(width), 28, _side(width), 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Boutiques',
            style: AppTextStyles.h1(color: AppColors.nearBlack),
          ),
          const SizedBox(height: 4),
          Text(
            'Recherchez une boutique, ou filtrez par département et catégorie.',
            style: AppTextStyles.body(color: AppColors.darkGray),
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onFilter,
    required this.filterCount,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onFilter;
  final int filterCount;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return Padding(
      padding: EdgeInsets.fromLTRB(_side(width), 16, _side(width), 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: AppTextStyles.body(color: AppColors.nearBlack),
              decoration: InputDecoration(
                hintText: 'Boutique, ville…',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: ListenableBuilder(
                  listenable: controller,
                  builder: (context, _) => controller.text.isEmpty
                      ? const SizedBox.shrink()
                      : IconButton(
                          tooltip: 'Effacer',
                          onPressed: () {
                            controller.clear();
                            onChanged('');
                          },
                          icon: const Icon(Icons.close_rounded, size: 18),
                        ),
                ),
                filled: true,
                fillColor: AppColors.white,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: const BorderSide(color: Color(0xFFECEAE4)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: const BorderSide(color: Color(0xFFECEAE4)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: const BorderSide(
                    color: AppColors.primaryBlue,
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _FilterButton(count: filterCount, onPressed: onFilter),
        ],
      ),
    );
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.count, required this.onPressed});

  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
            color: count > 0 ? AppColors.lightBlue : AppColors.white,
            shape: CircleBorder(
              side: BorderSide(
                color: count > 0
                    ? AppColors.primaryBlue
                    : const Color(0xFFD5D1C8),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onPressed,
              child: Tooltip(
                message: 'Filtres',
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Center(
                    child: _FilterMark(
                      color: count > 0
                          ? AppColors.primaryBlue
                          : AppColors.nearBlack,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (count > 0)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                width: 18,
                height: 18,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.primaryBlue,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Funnel drawn in code so the control stays visible without an icon font.
class _FilterMark extends StatelessWidget {
  const _FilterMark({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(18, 18),
      painter: _FilterMarkPainter(color),
    );
  }
}

class _FilterMarkPainter extends CustomPainter {
  _FilterMarkPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(w * 0.08, h * 0.12)
      ..lineTo(w * 0.92, h * 0.12)
      ..lineTo(w * 0.62, h * 0.48)
      ..lineTo(w * 0.62, h * 0.88)
      ..lineTo(w * 0.38, h * 0.88)
      ..lineTo(w * 0.38, h * 0.48)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_FilterMarkPainter old) => old.color != color;
}

class _ShopTile extends StatelessWidget {
  const _ShopTile({required this.shop, required this.onTap});

  final ShopCard shop;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (label, color) = shop.paused
        ? ('En pause', AppColors.amber)
        : shop.isOpenNow
        ? ('Ouvert', AppColors.deepGreen)
        : (
            shop.opensAtLabel.isEmpty ? 'Fermé' : 'Ouvre ${shop.opensAtLabel}',
            AppColors.boldRed,
          );
    return Material(
      color: AppColors.white,
      elevation: 0,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFECEAE4)),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (shop.coverUrl.isNotEmpty)
                Image.network(
                  shop.coverUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => _CoverFallback(name: shop.name),
                )
              else
                _CoverFallback(name: shop.name),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Color(0xE6110D08)],
                    stops: [0.38, 1],
                  ),
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(
                          AppConstants.radiusBadge,
                        ),
                      ),
                      child: Text(
                        label,
                        style: AppTextStyles.caption(
                          color: color,
                        ).copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      shop.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.h2(
                        color: AppColors.white,
                      ).copyWith(fontSize: 18),
                    ),
                    if (shop.place.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(
                            Icons.place_rounded,
                            size: 13,
                            color: Color(0xD9FFFFFF),
                          ),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              shop.place,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.caption(
                                color: const Color(0xD9FFFFFF),
                              ).copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (shop.categories.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        shop.categories.join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.caption(
                          color: const Color(0xD9FFFFFF),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: ListenableBuilder(
                  listenable: Favorites.instance,
                  builder: (context, _) {
                    final saved = Favorites.instance.contains(shop.slug);
                    return IconButton(
                      tooltip: saved
                          ? 'Retirer des favoris'
                          : 'Ajouter aux favoris',
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.white,
                        foregroundColor: saved
                            ? AppColors.boldRed
                            : AppColors.nearBlack,
                      ),
                      onPressed: () => Favorites.instance.toggle(shop),
                      icon: Icon(
                        saved ? Icons.favorite_rounded : Icons.favorite_border,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CoverFallback extends StatelessWidget {
  const _CoverFallback({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final letter = name.trim().isEmpty ? 'B' : name.trim()[0].toUpperCase();
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primaryBlue, Color(0xFF2C7BD6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(child: Text(letter, style: AppTextStyles.appName())),
    );
  }
}
