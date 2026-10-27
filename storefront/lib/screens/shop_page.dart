import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:retail_pos/core/theme/app_colors.dart';
import 'package:retail_pos/core/theme/app_text_styles.dart';
import 'package:retail_pos/core/utils/constants.dart';
import 'package:retail_pos/retail/models/sale_measure.dart';
import 'package:web/web.dart' as web;

import '../api.dart';
import '../cart.dart';
import '../favorites.dart';
import '../money.dart';
import '../widgets.dart';
import 'cart_sheet.dart';
import 'product_sheet.dart';

class ShopPage extends StatefulWidget {
  const ShopPage({super.key, required this.slug});

  final String slug;

  @override
  State<ShopPage> createState() => _ShopPageState();
}

class _ShopPageState extends State<ShopPage> {
  final _api = StorefrontApi();
  final _search = TextEditingController();
  Shop? _shop;
  String? _error;
  bool _notFound = false;
  String? _category;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _notFound = false;
    });
    try {
      final shop = await _api.shop(widget.slug);
      if (!mounted) return;
      web.document.title = shop.name;
      appCart.bindShop(shop.slug, shop.name, shop.usdRate);
      setState(() => _shop = shop);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _notFound = e.status == 404;
      });
    }
  }

  List<Product> get _visible {
    final shop = _shop;
    if (shop == null) return const [];
    final query = _search.text.trim().toLowerCase();
    return shop.products.where((p) {
      if (_category != null && p.category != _category) return false;
      if (query.isEmpty) return true;
      return p.name.toLowerCase().contains(query) ||
          p.description.toLowerCase().contains(query) ||
          p.category.toLowerCase().contains(query);
    }).toList();
  }

  void _quickAdd(Product product) {
    if (product.options.isNotEmpty || product.saleMode != SaleMode.piece) {
      _openProduct(product);
      return;
    }
    if (!appCart.add(product, const [], 1)) {
      showToast(
        context,
        'Stock maximum atteint pour ${product.name}.',
        error: true,
      );
    }
  }

  void _openProduct(Product product) {
    showProductSheet(context, shop: _shop!, product: product, cart: appCart);
  }

  void _openCart() {
    showCartSheet(context, shop: _shop!, cart: appCart, api: _api);
  }

  @override
  Widget build(BuildContext context) {
    final shop = _shop;
    if (shop == null) {
      return Scaffold(
        body: _error == null
            ? const LoadingView()
            : MessageView(
                icon: _notFound
                    ? Icons.storefront_outlined
                    : Icons.wifi_off_rounded,
                title: _notFound
                    ? 'Vitrine indisponible'
                    : 'Chargement impossible',
                message: _error!,
                actionLabel: _notFound ? null : 'Réessayer',
                onAction: _notFound ? null : _load,
              ),
      );
    }
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 1000 ? 4 : (width >= 680 ? 3 : 2);
    final products = _visible;
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _Header(shop: shop)),
            SliverPersistentHeader(
              pinned: true,
              delegate: _FilterBar(
                search: _search,
                categories: shop.categories,
                selected: _category,
                onSearch: () => setState(() {}),
                onCategory: (c) => setState(() => _category = c),
              ),
            ),
            if (products.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: MessageView(
                  icon: Icons.search_off_rounded,
                  title: shop.products.isEmpty
                      ? 'Catalogue vide'
                      : 'Aucun produit',
                  message: shop.products.isEmpty
                      ? 'La boutique n\'a pas encore mis de produits en ligne.'
                      : 'Essayez un autre mot ou une autre catégorie.',
                ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  _sidePadding(width),
                  AppConstants.spacing8,
                  _sidePadding(width),
                  120,
                ),
                sliver: ListenableBuilder(
                  listenable: appCart,
                  builder: (context, _) => SliverGrid.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      mainAxisExtent: width < 400 ? 286 : 308,
                    ),
                    itemCount: products.length,
                    itemBuilder: (context, i) => _ProductCard(
                      product: products[i],
                      rate: shop.usdRate,
                      inCart: appCart.quantityOf(products[i].id),
                      canBuy:
                          shop.availability.acceptsOrders ||
                          shop.availability.acceptsQuotes,
                      onTap: () => _openProduct(products[i]),
                      onAdd: () => _quickAdd(products[i]),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: ListenableBuilder(
        listenable: appCart,
        builder: (context, _) =>
            appCart.isEmpty || appCart.shopSlug != shop.slug
            ? const SizedBox.shrink()
            : _CartBar(cart: appCart, rate: shop.usdRate, onTap: _openCart),
      ),
    );
  }
}

double _sidePadding(double width) {
  const max = 1080.0;
  return width > max + 32 ? (width - max) / 2 : AppConstants.spacing16;
}

class _Header extends StatelessWidget {
  const _Header({required this.shop});

  final Shop shop;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final side = _sidePadding(width);
    final a = shop.availability;
    final (label, color) = a.paused
        ? ('En pause', AppColors.amber)
        : a.isOpenNow
        ? ('Ouvert', AppColors.deepGreen)
        : (
            'Fermé${a.opensAtLabel != null ? ' · ouvre ${a.opensAtLabel}' : ''}',
            AppColors.boldRed,
          );
    final notice = a.paused
        ? 'La boutique a mis les commandes en pause. Revenez un peu plus tard.'
        : !a.isOpenNow && a.acceptsOrders
        ? 'La boutique est fermée : votre commande sera préparée à l\'ouverture.'
        : !a.isOpenNow
        ? 'La boutique est fermée. Vous pouvez quand même demander un devis.'
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: width < 600 ? 190 : 260,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (shop.coverUrl.isNotEmpty)
                Image.network(
                  shop.coverUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const _CoverFallback(),
                )
              else
                const _CoverFallback(),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Color(0x99000000)],
                    stops: [0.35, 1],
                  ),
                ),
              ),
              Positioned(
                right: 8,
                top: 8,
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
                      onPressed: () => Favorites.instance.toggle(
                        ShopCard(
                          slug: shop.slug,
                          name: shop.name,
                          city: shop.city,
                          department: shop.department,
                          categories: shop.businessCategories,
                          description: shop.description,
                          coverUrl: shop.coverUrl,
                          isOpenNow: shop.availability.isOpenNow,
                          paused: shop.availability.paused,
                          opensAtLabel: shop.availability.opensAtLabel ?? '',
                        ),
                      ),
                      icon: Icon(
                        saved ? Icons.favorite_rounded : Icons.favorite_border,
                      ),
                    );
                  },
                ),
              ),
              Positioned(
                left: 8,
                top: 8,
                child: IconButton(
                  tooltip: 'Toutes les boutiques',
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.white,
                    foregroundColor: AppColors.nearBlack,
                  ),
                  onPressed: () => context.go('/'),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
              ),
              Positioned(
                left: side,
                right: side,
                bottom: 18,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      shop.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.h1(
                        color: AppColors.white,
                      ).copyWith(fontSize: width < 600 ? 26 : 32, height: 1.15),
                    ),
                    if (shop.city.isNotEmpty || shop.department.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        [
                          shop.city,
                          shop.department,
                        ].where((part) => part.isNotEmpty).join(', '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.body(
                          color: const Color(0xF2FFFFFF),
                        ).copyWith(fontSize: 14),
                      ),
                    ],
                    if (shop.businessCategories.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        shop.businessCategories.join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.body(
                          color: const Color(0xF2FFFFFF),
                        ).copyWith(fontSize: 13),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(side, 14, side, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Pill(label: label, color: color),
                  Pill(
                    label: a.openHour == a.closeHour
                        ? 'Ouvert 24 h/24'
                        : '${a.openHour}h – ${a.closeHour}h',
                    color: AppColors.darkGray,
                    icon: Icons.schedule_rounded,
                  ),
                  Pill(
                    label:
                        '1 US\$ = ${shop.usdRate.toStringAsFixed(shop.usdRate % 1 == 0 ? 0 : 2)} HTG',
                    color: AppColors.primaryBlue,
                    icon: Icons.currency_exchange_rounded,
                  ),
                ],
              ),
              if (shop.description.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  shop.description,
                  style: AppTextStyles.body(
                    color: AppColors.darkGray,
                  ).copyWith(fontSize: 14, height: 1.45),
                ),
              ],
              if (notice != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.amber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(
                      AppConstants.radiusButton,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        size: 18,
                        color: Color(0xFF9A6200),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          notice,
                          style: AppTextStyles.body(
                            color: const Color(0xFF7A4E00),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _CoverFallback extends StatelessWidget {
  const _CoverFallback();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A3C5E), AppColors.primaryBlue, Color(0xFF3A86D9)],
        ),
      ),
    );
  }
}

class _FilterBar extends SliverPersistentHeaderDelegate {
  _FilterBar({
    required this.search,
    required this.categories,
    required this.selected,
    required this.onSearch,
    required this.onCategory,
  });

  final TextEditingController search;
  final List<String> categories;
  final String? selected;
  final VoidCallback onSearch;
  final ValueChanged<String?> onCategory;

  bool get _hasChips => categories.length > 1;

  @override
  double get maxExtent => _hasChips ? 118 : 72;

  @override
  double get minExtent => maxExtent;

  @override
  bool shouldRebuild(_FilterBar old) =>
      old.selected != selected ||
      old.categories != categories ||
      old.search != search;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final side = _sidePadding(MediaQuery.sizeOf(context).width);
    return Container(
      color: AppColors.warmOffWhite.withValues(alpha: 0.97),
      padding: EdgeInsets.fromLTRB(side, 12, side, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 46,
            child: TextField(
              controller: search,
              onChanged: (_) => onSearch(),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Rechercher un produit',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: search.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () {
                          search.clear();
                          onSearch();
                        },
                      ),
                filled: true,
                fillColor: AppColors.white,
                contentPadding: EdgeInsets.zero,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: const BorderSide(color: Color(0xFFE6E3DC)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: const BorderSide(color: Color(0xFFE6E3DC)),
                ),
              ),
            ),
          ),
          if (_hasChips) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 34,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _chip('Tout', selected == null, () => onCategory(null)),
                  for (final c in categories)
                    _chip(
                      c,
                      selected == c,
                      () => onCategory(selected == c ? null : c),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _chip(String label, bool active, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: active ? AppColors.primaryBlue : AppColors.white,
        shape: StadiumBorder(
          side: BorderSide(
            color: active ? AppColors.primaryBlue : const Color(0xFFE6E3DC),
          ),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Center(
              child: Text(
                label,
                style: AppTextStyles.body(
                  color: active ? AppColors.white : AppColors.nearBlack,
                ).copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.product,
    required this.rate,
    required this.inCart,
    required this.canBuy,
    required this.onTap,
    required this.onAdd,
  });

  final Product product;
  final double rate;
  final int inCart;
  final bool canBuy;
  final VoidCallback onTap;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(AppConstants.radiusCard + 2),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ProductPhoto(url: product.photoUrl, name: product.name),
                  if (!product.available)
                    Container(
                      color: const Color(0x99FFFFFF),
                      alignment: Alignment.center,
                      child: const Pill(
                        label: 'Rupture de stock',
                        color: AppColors.boldRed,
                      ),
                    ),
                  if (product.onSale && product.available)
                    Positioned(
                      left: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.boldRed,
                          borderRadius: BorderRadius.circular(
                            AppConstants.radiusBadge,
                          ),
                        ),
                        child: Text(
                          '-${(100 - product.priceHtg / product.regularPriceHtg * 100).round()} %',
                          style: AppTextStyles.caption(
                            color: AppColors.white,
                          ).copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 36,
                    child: Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body(
                        color: AppColors.nearBlack,
                      ).copyWith(fontWeight: FontWeight.w600, height: 1.3),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            DualPrice(
                              htg: product.priceHtg,
                              rate: rate,
                              regularHtg: product.regularPriceHtg,
                            ),
                            if (product.saleHint.isNotEmpty)
                              Text(
                                product.saleMode == SaleMode.roll
                                    ? '${product.saleHint} · par pouce'
                                    : product.saleHint,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.caption(color: AppColors.darkGray),
                              ),
                          ],
                        ),
                      ),
                      if (product.available && canBuy)
                        _AddButton(count: inCart, onTap: onAdd),
                    ],
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

class _AddButton extends StatelessWidget {
  const _AddButton({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: count > 0 ? AppColors.primaryBlue : AppColors.lightBlue,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 38,
          height: 38,
          child: Center(
            child: count > 0
                ? Text(
                    '$count',
                    style: AppTextStyles.button(
                      color: AppColors.white,
                    ).copyWith(fontSize: 14),
                  )
                : const Icon(
                    Icons.add_rounded,
                    color: AppColors.primaryBlue,
                    size: 22,
                  ),
          ),
        ),
      ),
    );
  }
}

class _CartBar extends StatelessWidget {
  const _CartBar({required this.cart, required this.rate, required this.onTap});

  final Cart cart;
  final double rate;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kPhoneMaxWidth),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Material(
              color: AppColors.primaryBlue,
              elevation: 6,
              shadowColor: const Color(0x401A5AA8),
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${cart.count}',
                          style: AppTextStyles.button(color: AppColors.white),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Voir le panier',
                          style: AppTextStyles.button(
                            color: AppColors.white,
                          ).copyWith(fontSize: 15),
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            Money.usdFromHtg(cart.totalHtg, rate),
                            style: AppTextStyles.price(color: AppColors.white),
                          ),
                          Text(
                            Money.htg(cart.totalHtg),
                            style: AppTextStyles.caption(
                              color: AppColors.white.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
