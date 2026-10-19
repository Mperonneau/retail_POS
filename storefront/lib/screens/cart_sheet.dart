import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:retail_pos/core/theme/app_colors.dart';
import 'package:retail_pos/core/theme/app_text_styles.dart';
import 'package:retail_pos/core/utils/constants.dart';
import 'package:retail_pos/core/widgets/app_button.dart';
import 'package:retail_pos/core/widgets/app_close_button.dart';

import '../api.dart';
import '../cart.dart';
import '../session.dart';
import '../money.dart';
import '../widgets.dart';

/// Checkout cart. A right-hand panel on a wide window, the full screen on a phone.
Future<void> showCartSheet(
  BuildContext context, {
  required Shop shop,
  required Cart cart,
  required StorefrontApi api,
}) {
  final width = MediaQuery.sizeOf(context).width;
  final fullScreen = width < AppConstants.mobileBreakpoint;
  final panelWidth = AppConstants.sidePanelWidth(width, 480);
  final router = GoRouter.of(context);

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
            child: _CartSheet(shop: shop, cart: cart, api: api, router: router),
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

class _CartSheet extends StatefulWidget {
  const _CartSheet({
    required this.shop,
    required this.cart,
    required this.api,
    required this.router,
  });

  final Shop shop;
  final Cart cart;
  final StorefrontApi api;
  final GoRouter router;

  @override
  State<_CartSheet> createState() => _CartSheetState();
}

class _CartSheetState extends State<_CartSheet> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _note = TextEditingController();
  String? _busyKind;
  String? _error;

  @override
  void initState() {
    super.initState();
    final session = Session.instance;
    if (session.isLoggedIn) {
      _name.text = session.name;
      _phone.text = session.phone;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit(String kind) async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _busyKind = kind;
      _error = null;
    });
    try {
      final request = await widget.api.submit(
        slug: widget.shop.slug,
        kind: kind,
        lines: widget.cart.toPayload(),
        name: _name.text.trim(),
        phone: _phone.text.trim(),
        email: _email.text.trim(),
        note: _note.text.trim(),
        token: Session.instance.isLoggedIn ? Session.instance.token : null,
      );
      await Session.instance.rememberOrder(request.id);
      widget.cart.clear();
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.router.go('/r/${request.id}');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busyKind = null;
        _error = e.message;
      });
    }
  }

  InputDecoration _field(String label, {String? hint, IconData? icon}) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: icon == null ? null : Icon(icon, size: 20),
        filled: true,
        fillColor: AppColors.warmOffWhite,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final shop = widget.shop;
    final rate = shop.usdRate;
    final a = shop.availability;
    return ListenableBuilder(
      listenable: widget.cart,
      builder: (context, _) {
        final cart = widget.cart;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Votre panier',
                      style: AppTextStyles.h1(
                        color: AppColors.nearBlack,
                      ).copyWith(fontSize: 22),
                    ),
                  ),
                  if (!cart.isEmpty)
                    TextButton(
                      onPressed: () async {
                        if (await confirmClearCart(context)) cart.clear();
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.boldRed,
                      ),
                      child: const Text('Vider'),
                    ),
                  AppCloseButton(onPressed: () => Navigator.of(context).pop()),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFF0EEE9)),
            Expanded(
              child: Form(
                key: _form,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  children: [
                    if (cart.isEmpty)
                      const SizedBox(
                        height: 320,
                        child: MessageView(
                          icon: Icons.shopping_bag_outlined,
                          title: 'Panier vide',
                          message: 'Ajoutez des produits pour commander.',
                        ),
                      )
                    else ...[
                      for (final line in cart.lines) ...[
                        _LineTile(
                          line: line,
                          rate: rate,
                          onRemove: () => cart.remove(line),
                          onMinus: () => cart.decrement(line),
                          onPlus: () {
                            if (!cart.increment(line)) {
                              showToast(
                                context,
                                'Stock maximum atteint.',
                                error: true,
                              );
                            }
                          },
                        ),
                        const Divider(height: 20, color: Color(0xFFF0EEE9)),
                      ],
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              'Total',
                              style: AppTextStyles.h2(
                                color: AppColors.nearBlack,
                              ),
                            ),
                          ),
                          DualPrice(
                            htg: cart.totalHtg,
                            rate: rate,
                            large: true,
                            alignEnd: true,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Les frais de paiement s\'affichent à l\'étape suivante.',
                        style: AppTextStyles.caption(),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Vos coordonnées',
                        style: AppTextStyles.h2(
                          color: AppColors.nearBlack,
                        ).copyWith(fontSize: 16),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        decoration: _field(
                          'Nom complet',
                          icon: Icons.person_outline_rounded,
                        ),
                        validator: (v) => (v ?? '').trim().isEmpty
                            ? 'Indiquez votre nom.'
                            : null,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        decoration: _field(
                          'Téléphone',
                          hint: '+509 …',
                          icon: Icons.phone_outlined,
                        ),
                        validator: (v) =>
                            (v ?? '').replaceAll(RegExp(r'\D'), '').length < 8
                            ? 'Indiquez un numéro valide.'
                            : null,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        decoration: _field(
                          'E-mail (facultatif)',
                          icon: Icons.mail_outline_rounded,
                        ),
                        validator: (v) {
                          final text = (v ?? '').trim();
                          if (text.isEmpty) return null;
                          return RegExp(
                                r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                              ).hasMatch(text)
                              ? null
                              : 'Adresse e-mail invalide.';
                        },
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _note,
                        maxLines: 3,
                        minLines: 1,
                        maxLength: 500,
                        decoration: _field(
                          'Note pour la boutique (facultatif)',
                          icon: Icons.edit_note_rounded,
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _error!,
                          style: AppTextStyles.errorText().copyWith(
                            fontSize: 13,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      if (a.acceptsOrders)
                        AppButton(
                          label:
                              'Commander · ${Money.usdFromHtg(cart.totalHtg, rate)}',
                          icon: Icons.shopping_bag_rounded,
                          isLoading: _busyKind == 'commande',
                          onPressed: _busyKind == null
                              ? () => _submit('commande')
                              : null,
                        ),
                      if (a.acceptsOrders && a.acceptsQuotes)
                        const SizedBox(height: 10),
                      if (a.acceptsQuotes)
                        AppButton(
                          label: 'Demander un devis',
                          icon: Icons.request_quote_outlined,
                          variant: AppButtonVariant.secondary,
                          isLoading: _busyKind == 'devis',
                          onPressed: _busyKind == null
                              ? () => _submit('devis')
                              : null,
                        ),
                      const SizedBox(height: 12),
                      Text(
                        a.acceptsOrders
                            ? 'Commander : vous payez maintenant, ou vous partagez le lien pour qu\'un proche paie, même à l\'étranger. '
                                  'Devis : la boutique reçoit votre demande et vous pourrez la payer plus tard.'
                            : 'La boutique reçoit votre demande de devis. Vous pourrez la payer plus tard depuis le lien.',
                        style: AppTextStyles.caption().copyWith(height: 1.45),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _LineTile extends StatelessWidget {
  const _LineTile({
    required this.line,
    required this.rate,
    required this.onRemove,
    required this.onMinus,
    required this.onPlus,
  });

  final CartLine line;
  final double rate;
  final VoidCallback onRemove;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    final photo = line.product.photoUrl;
    return Row(
      children: [
        if (photo.isNotEmpty) ...[
          SizedBox(
            width: 56,
            height: 56,
            child: ProductPhoto(
              url: photo,
              name: line.product.name,
              radius: 10,
            ),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                line.product.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.body(
                  color: AppColors.nearBlack,
                ).copyWith(fontWeight: FontWeight.w600),
              ),
              if (line.optionsLabel.isNotEmpty)
                Text(line.optionsLabel, style: AppTextStyles.caption()),
              const SizedBox(height: 2),
              Text(
                '${Money.usdFromHtg(line.totalHtg, rate)} · ${Money.htg(line.totalHtg)}',
                style: AppTextStyles.caption(
                  color: AppColors.darkGray,
                ).copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        QtyStepper(
          value: line.quantity,
          onMinus: onMinus,
          onPlus: onPlus,
          compact: true,
        ),
        IconButton(
          tooltip: 'Retirer',
          onPressed: onRemove,
          icon: const Icon(Icons.close_rounded, size: 18),
          color: AppColors.darkGray,
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}
