import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:retail_pos/core/theme/app_colors.dart';
import 'package:retail_pos/core/theme/app_text_styles.dart';
import 'package:retail_pos/core/utils/constants.dart';
import 'package:web/web.dart' as web;

import '../api.dart';
import '../widgets.dart';

/// Directory of every open vitrine, searchable and filtered by department.
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
  String? _department;
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
    final shops = _directory?.results ?? const <ShopCard>[];
    final query = _query.trim().toLowerCase();
    return shops.where((shop) {
      if (_department != null && shop.department != _department) return false;
      if (query.isEmpty) return true;
      return shop.name.toLowerCase().contains(query) ||
          shop.city.toLowerCase().contains(query) ||
          shop.department.toLowerCase().contains(query) ||
          shop.description.toLowerCase().contains(query);
    }).toList();
  }

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
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _Intro(width: width)),
            SliverToBoxAdapter(
              child: _SearchField(
                controller: _search,
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            SliverToBoxAdapter(
              child: _DepartmentChips(
                departments: directory.departments,
                selected: _department,
                onSelected: (value) => setState(() => _department = value),
              ),
            ),
            if (shops.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: MessageView(
                  icon: Icons.storefront_outlined,
                  title: _query.trim().isEmpty && _department == null
                      ? 'Aucune boutique en ligne'
                      : 'Aucune boutique',
                  message: _query.trim().isEmpty && _department == null
                      ? 'Les boutiques apparaissent ici dès que leur vitrine est activée.'
                      : 'Essayez un autre mot ou un autre département.',
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
                    childAspectRatio: columns == 1 ? 1.72 : (columns == 2 ? 1.12 : 0.92),
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
          Text('Boutiques', style: AppTextStyles.h1(color: AppColors.nearBlack)),
          const SizedBox(height: 4),
          Text(
            'Parcourez les boutiques par département.',
            style: AppTextStyles.body(color: AppColors.darkGray),
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return Padding(
      padding: EdgeInsets.fromLTRB(_side(width), 16, _side(width), 12),
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
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
            borderSide: const BorderSide(color: AppColors.primaryBlue, width: 1.5),
          ),
        ),
      ),
    );
  }
}

class _DepartmentChips extends StatelessWidget {
  const _DepartmentChips({
    required this.departments,
    required this.selected,
    required this.onSelected,
  });

  final List<String> departments;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final labels = ['Tout', ...departments];
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: _side(width)),
        itemCount: labels.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final label = labels[index];
          final isAll = index == 0;
          final active = isAll ? selected == null : selected == label;
          return ChoiceChip(
            label: Text(label),
            selected: active,
            showCheckmark: false,
            labelStyle: AppTextStyles.body(
              color: active ? AppColors.white : AppColors.nearBlack,
            ).copyWith(fontWeight: FontWeight.w600, fontSize: 13),
            selectedColor: AppColors.primaryBlue,
            backgroundColor: AppColors.white,
            side: BorderSide(
              color: active ? AppColors.primaryBlue : const Color(0xFFECEAE4),
            ),
            onSelected: (_) => onSelected(isAll ? null : label),
          );
        },
      ),
    );
  }
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
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(AppConstants.radiusBadge),
                      ),
                      child: Text(
                        label,
                        style: AppTextStyles.caption(color: color)
                            .copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      shop.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.h2(color: AppColors.white).copyWith(fontSize: 18),
                    ),
                    if (shop.place.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(Icons.place_rounded, size: 13, color: Color(0xD9FFFFFF)),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              shop.place,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.caption(color: const Color(0xD9FFFFFF))
                                  .copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
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
      child: Center(
        child: Text(letter, style: AppTextStyles.appName()),
      ),
    );
  }
}
