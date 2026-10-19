import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/mock/mock_retail_data.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/payments/open_payment_url.dart';
import '../../core/providers/app_notification_provider.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/currency_settings_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/constants.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/page_header.dart';
import '../storefront/business_category_picker.dart';
import '../storefront/storefront_link_dialog.dart';
import '../storefront/storefront_settings.dart';
import '../storefront/storefront_sync.dart';
import '../widgets/product_photo_pick.dart';

/// Online vitrine settings. Every change saves and publishes automatically.
class VitrineScreen extends ConsumerStatefulWidget {
  const VitrineScreen({super.key});

  @override
  ConsumerState<VitrineScreen> createState() => _VitrineScreenState();
}

class _VitrineScreenState extends ConsumerState<VitrineScreen> {
  final _slug = TextEditingController();
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _city = TextEditingController();
  final _pickupNote = TextEditingController();
  Timer? _typing;
  bool _hydrated = false;
  String? _coverError;

  static const _dayNames = {
    1: 'Lun',
    2: 'Mar',
    3: 'Mer',
    4: 'Jeu',
    5: 'Ven',
    6: 'Sam',
    7: 'Dim',
  };

  @override
  void dispose() {
    _typing?.cancel();
    _slug.dispose();
    _name.dispose();
    _description.dispose();
    _city.dispose();
    _pickupNote.dispose();
    super.dispose();
  }

  void _hydrate(StorefrontSettings s) {
    if (_hydrated || !s.loaded) return;
    _hydrated = true;
    final business = ref.read(authProvider).businessName ?? '';
    var slug = s.slug;
    if (slug.isEmpty) {
      slug = suggestStorefrontSlug(business);
      if (slug.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _update((c) => c.copyWith(slug: slug)),
        );
      }
    }
    _slug.text = slug;
    _name.text = s.displayName;
    _description.text = s.description;
    _city.text = s.city;
    _pickupNote.text = s.pickupNote;
  }

  void _update(StorefrontSettings Function(StorefrontSettings) change) {
    ref.read(storefrontSettingsProvider.notifier).update(change);
  }

  void _onTyping() {
    _typing?.cancel();
    _typing = Timer(const Duration(milliseconds: 600), () {
      final slug = _slug.text.trim().toLowerCase();
      _update(
        (c) => c.copyWith(
          slug: slug,
          displayName: _name.text.trim(),
          description: _description.text.trim(),
          city: _city.text.trim(),
          pickupNote: _pickupNote.text.trim(),
        ),
      );
    });
    setState(() {});
  }

  Future<void> _pickCover() async {
    final picked = await pickProductPhoto();
    if (!mounted || picked == null) return;
    if (picked.error != null || picked.bytes == null) {
      setState(() => _coverError = picked.error);
      return;
    }
    setState(() => _coverError = null);
    final dataUrl = 'data:${picked.mime};base64,${base64Encode(picked.bytes!)}';
    _update((c) => c.copyWith(coverDataUrl: dataUrl));
  }

  String get _shopUrl => StorefrontLinks.shop(_slug.text.trim().toLowerCase());

  bool get _slugValid => isValidStorefrontSlug(_slug.text.trim().toLowerCase());

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(storefrontSettingsProvider);
    final sync = ref.watch(storefrontSyncProvider);
    _hydrate(settings);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final wide = MediaQuery.sizeOf(context).width >= 1100;

    if (!settings.loaded) {
      return const Center(child: CircularProgressIndicator());
    }

    final preview = _PreviewCard(
      settings: settings,
      name: _name.text.trim().isNotEmpty
          ? _name.text.trim()
          : (ref.watch(authProvider).businessName ?? 'Boutique'),
      description: _description.text.trim(),
      url: _slugValid ? _shopUrl : null,
      onPreview: _slugValid && settings.everPublished
          ? () => openPaymentUrl(_shopUrl)
          : null,
    );

    final sections = <Widget>[
      _statusCard(settings, isDark),
      _linkCard(settings, sync, isDark),
      _hoursCard(settings, isDark),
      _presentationCard(settings, isDark),
      _pickupCard(isDark),
      _catalogCard(isDark),
      _requestsCard(sync, isDark),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppConstants.spacing16),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: wide ? 1080 : 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                title: 'Vitrine en ligne',
                subtitle:
                    'Vos clients commandent ou demandent un devis depuis leur téléphone.',
                action: _SaveStatus(settings: settings, sync: sync),
              ),
              if (sync.error != null && !sync.slugTaken) ...[
                const SizedBox(height: AppConstants.spacing12),
                _ErrorBanner(
                  message: sync.error!,
                  onRetry: () =>
                      ref.read(storefrontSyncProvider.notifier).publishNow(),
                ),
              ],
              const SizedBox(height: AppConstants.spacing16),
              if (wide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _spaced(sections)),
                    const SizedBox(width: AppConstants.spacing16),
                    SizedBox(width: 340, child: preview),
                  ],
                )
              else
                _spaced([preview, ...sections]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _spaced(List<Widget> children) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0) const SizedBox(height: AppConstants.spacing16),
        children[i],
      ],
    ],
  );

  Widget _statusCard(StorefrontSettings s, bool isDark) {
    return _Section(
      title: 'Statut',
      icon: Icons.toggle_on_outlined,
      children: [
        _SwitchRow(
          title: 'Accepter les commandes en ligne',
          subtitle: s.enabled
              ? 'La vitrine est visible à son adresse.'
              : 'La vitrine est hors ligne. Activez-la pour la publier.',
          value: s.enabled,
          onChanged: (v) {
            if (v && !_slugValid) {
              ref
                  .read(appNotificationProvider.notifier)
                  .show(
                    'Choisissez d\'abord un lien de vitrine valide.',
                    kind: AppNotificationKind.warning,
                  );
              return;
            }
            _update((c) => c.copyWith(enabled: v));
          },
        ),
        _SwitchRow(
          title: 'Pause temporaire',
          subtitle:
              'Les clients voient la vitrine mais ne peuvent ni commander ni demander de devis.',
          value: s.paused,
          onChanged: s.enabled
              ? (v) => _update((c) => c.copyWith(paused: v))
              : null,
        ),
        _SwitchRow(
          title: 'Commander hors horaires',
          subtitle:
              'Les commandes passées boutique fermée sont préparées à l\'ouverture. Les devis restent possibles.',
          value: s.acceptWhenClosed,
          onChanged: s.enabled
              ? (v) => _update((c) => c.copyWith(acceptWhenClosed: v))
              : null,
        ),
      ],
    );
  }

  Widget _linkCard(
    StorefrontSettings s,
    StorefrontSyncState sync,
    bool isDark,
  ) {
    final raw = _slug.text.trim();
    String? error;
    if (raw.isNotEmpty && !_slugValid) {
      error = '3 à 40 caractères : lettres minuscules, chiffres ou tirets.';
    } else if (raw.isEmpty) {
      error = 'Le lien est requis pour publier la vitrine.';
    } else if (sync.slugTaken) {
      error = sync.error;
    }
    return _Section(
      title: 'Lien de la vitrine',
      icon: Icons.link_rounded,
      children: [
        TextField(
          controller: _slug,
          onChanged: (_) => _onTyping(),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9-]')),
            LengthLimitingTextInputFormatter(40),
          ],
          decoration: InputDecoration(
            labelText: 'Adresse',
            prefixText: '${StorefrontLinks.host}/',
            errorText: error,
            errorMaxLines: 2,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppConstants.radiusInput),
            ),
          ),
        ),
        const SizedBox(height: AppConstants.spacing12),
        Wrap(
          spacing: AppConstants.spacing8,
          runSpacing: AppConstants.spacing8,
          children: [
            AppButton(
              label: 'Copier le lien',
              icon: Icons.copy_rounded,
              variant: AppButtonVariant.secondary,
              compact: true,
              fullWidth: false,
              onPressed: _slugValid
                  ? () async {
                      await Clipboard.setData(ClipboardData(text: _shopUrl));
                      if (!mounted) return;
                      ref
                          .read(appNotificationProvider.notifier)
                          .show('Lien de la vitrine copié.');
                    }
                  : null,
            ),
            AppButton(
              label: 'Code QR',
              icon: Icons.qr_code_2_rounded,
              variant: AppButtonVariant.secondary,
              compact: true,
              fullWidth: false,
              onPressed: _slugValid
                  ? () => showStorefrontLinkDialog(
                      context,
                      title: 'Code QR de la vitrine',
                      message:
                          'À afficher en boutique ou à partager : vos clients ouvrent la vitrine en le scannant.',
                      url: _shopUrl,
                      openLabel: 'Aperçu de la vitrine',
                    )
                  : null,
            ),
            AppButton(
              label: 'Aperçu de la vitrine',
              icon: Icons.open_in_new_rounded,
              compact: true,
              fullWidth: false,
              onPressed: _slugValid && s.everPublished
                  ? () => openPaymentUrl(_shopUrl)
                  : null,
            ),
          ],
        ),
      ],
    );
  }

  Widget _hoursCard(StorefrontSettings s, bool isDark) {
    final hours = List<int>.generate(24, (h) => h);
    String label(int h) => '${h.toString().padLeft(2, '0')}h00';
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppConstants.radiusInput),
    );
    return _Section(
      title: 'Horaires',
      icon: Icons.schedule_rounded,
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: s.openHour,
                decoration: InputDecoration(
                  labelText: 'Ouverture',
                  border: border,
                ),
                items: [
                  for (final h in hours)
                    DropdownMenuItem(value: h, child: Text(label(h))),
                ],
                onChanged: (v) {
                  if (v != null) _update((c) => c.copyWith(openHour: v));
                },
              ),
            ),
            const SizedBox(width: AppConstants.spacing12),
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: s.closeHour,
                decoration: InputDecoration(
                  labelText: 'Fermeture',
                  border: border,
                ),
                items: [
                  for (final h in hours)
                    DropdownMenuItem(value: h, child: Text(label(h))),
                ],
                onChanged: (v) {
                  if (v != null) _update((c) => c.copyWith(closeHour: v));
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: AppConstants.spacing16),
        Text('Jours de fermeture', style: AppTextStyles.inputLabel()),
        const SizedBox(height: AppConstants.spacing8),
        Wrap(
          spacing: AppConstants.spacing6,
          runSpacing: AppConstants.spacing6,
          children: [
            for (final entry in _dayNames.entries)
              FilterChip(
                label: Text(entry.value),
                selected: s.closedWeekdays.contains(entry.key),
                showCheckmark: false,
                selectedColor: AppColors.boldRed.withValues(alpha: 0.14),
                labelStyle: AppTextStyles.body(
                  color: s.closedWeekdays.contains(entry.key)
                      ? AppColors.boldRed
                      : null,
                ).copyWith(fontWeight: FontWeight.w600),
                onSelected: (selected) => _update((c) {
                  final days = {...c.closedWeekdays};
                  selected ? days.add(entry.key) : days.remove(entry.key);
                  return c.copyWith(closedWeekdays: days);
                }),
              ),
          ],
        ),
        const SizedBox(height: AppConstants.spacing8),
        Text(
          s.openHour == s.closeHour
              ? 'Ouverte 24 h sur 24 les jours non cochés.'
              : 'Heure d\'Haïti. Les jours en rouge, la vitrine s\'affiche fermée.',
          style: AppTextStyles.caption(),
        ),
      ],
    );
  }

  Widget _presentationCard(StorefrontSettings s, bool isDark) {
    final cover = _decode(s.coverDataUrl);
    final business = ref.watch(authProvider).businessName ?? '';
    return _Section(
      title: 'Présentation',
      icon: Icons.photo_outlined,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppConstants.radiusCard),
          child: AspectRatio(
            aspectRatio: 16 / 7,
            child: Material(
              color: isDark ? AppColors.darkBackground : AppColors.warmOffWhite,
              child: InkWell(
                onTap: _pickCover,
                child: cover != null
                    ? Image.memory(cover, fit: BoxFit.cover)
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.add_photo_alternate_outlined,
                            size: 32,
                            color: isDark
                                ? AppColors.coolGray
                                : AppColors.darkGray,
                          ),
                          const SizedBox(height: AppConstants.spacing6),
                          Text(
                            'Ajouter une photo de couverture',
                            style: AppTextStyles.body(),
                          ),
                          Text(
                            'JPEG, PNG ou WebP, moins de 1,5 Mo',
                            style: AppTextStyles.caption(),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
        if (_coverError != null) ...[
          const SizedBox(height: AppConstants.spacing6),
          Text(_coverError!, style: AppTextStyles.errorText()),
        ],
        if (cover != null) ...[
          const SizedBox(height: AppConstants.spacing8),
          Row(
            children: [
              TextButton.icon(
                onPressed: _pickCover,
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Changer'),
              ),
              TextButton.icon(
                onPressed: () => _update((c) => c.copyWith(coverDataUrl: null)),
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('Retirer'),
                style: TextButton.styleFrom(foregroundColor: AppColors.boldRed),
              ),
            ],
          ),
        ],
        const SizedBox(height: AppConstants.spacing16),
        TextField(
          controller: _name,
          onChanged: (_) => _onTyping(),
          maxLength: 80,
          decoration: _fieldDecoration(
            'Nom affiché',
            hint: business.isEmpty ? 'Nom de la boutique' : business,
          ),
        ),
        const SizedBox(height: AppConstants.spacing8),
        TextField(
          controller: _description,
          onChanged: (_) => _onTyping(),
          maxLength: 300,
          minLines: 2,
          maxLines: 4,
          decoration: _fieldDecoration(
            'Description',
            hint: 'Ce que vous vendez, où vous trouver…',
          ),
        ),
        const SizedBox(height: AppConstants.spacing8),
        DropdownButtonFormField<String>(
          initialValue: haitiDepartments.contains(s.department)
              ? s.department
              : '',
          decoration: _fieldDecoration('Département'),
          items: [
            const DropdownMenuItem(value: '', child: Text('Non précisé')),
            for (final department in haitiDepartments)
              DropdownMenuItem(value: department, child: Text(department)),
          ],
          onChanged: (value) {
            if (value == null) return;
            _update((c) => c.copyWith(department: value));
          },
        ),
        const SizedBox(height: AppConstants.spacing8),
        TextField(
          controller: _city,
          onChanged: (_) => _onTyping(),
          maxLength: 60,
          decoration: _fieldDecoration('Ville', hint: 'Pétion-Ville'),
        ),
        const SizedBox(height: AppConstants.spacing12),
        Text('Catégories', style: AppTextStyles.inputLabel()),
        const SizedBox(height: AppConstants.spacing6),
        if (s.categories.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final name in s.categories)
                InputChip(
                  label: Text(name),
                  onDeleted: () => _update(
                    (c) => c.copyWith(
                      categories: [
                        for (final item in c.categories)
                          if (item != name) item,
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppConstants.spacing8),
        ],
        AppButton(
          label: s.categories.isEmpty
              ? 'Choisir les catégories'
              : 'Modifier les catégories',
          icon: Icons.category_outlined,
          variant: AppButtonVariant.secondary,
          compact: true,
          fullWidth: false,
          onPressed: () => showBusinessCategoryPicker(
            context,
            selected: s.categories,
            onChanged: (categories) =>
                _update((c) => c.copyWith(categories: categories)),
          ),
        ),
        const SizedBox(height: AppConstants.spacing4),
        Text(
          'Une boutique peut en avoir plusieurs. L\'annuaire ne propose que les catégories déjà utilisées.',
          style: AppTextStyles.caption(),
        ),
      ],
    );
  }

  Widget _pickupCard(bool isDark) {
    return _Section(
      title: 'Consigne de retrait',
      icon: Icons.storefront_outlined,
      children: [
        TextField(
          controller: _pickupNote,
          onChanged: (_) => _onTyping(),
          maxLength: 300,
          minLines: 2,
          maxLines: 4,
          decoration: _fieldDecoration(
            'Affichée après le paiement',
            hint:
                'Ex. : Retrait au comptoir du lundi au samedi. Présentez le numéro de commande.',
          ),
        ),
      ],
    );
  }

  Widget _catalogCard(bool isDark) {
    final products = ref.watch(mockProductsProvider);
    final visible = products
        .where((p) => p.active && p.showOnStorefront)
        .length;
    final currency = ref.watch(currencySettingsProvider);
    return _Section(
      title: 'Catalogue',
      icon: Icons.inventory_2_outlined,
      children: [
        Text(
          visible == 0
              ? 'Aucun produit visible sur la vitrine.'
              : '$visible produit${visible > 1 ? 's' : ''} visible${visible > 1 ? 's' : ''} sur la vitrine.',
          style: AppTextStyles.body().copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: AppConstants.spacing4),
        Text(
          'Prix affichés en dollars US puis en gourdes '
          '(1 USD = ${currency.usdToLocalRate.toStringAsFixed(currency.usdToLocalRate % 1 == 0 ? 0 : 2)} ${currency.localCurrencyCode}). '
          'Masquez un produit avec « Afficher sur la vitrine » dans sa fiche.',
          style: AppTextStyles.caption(),
        ),
        const SizedBox(height: AppConstants.spacing12),
        AppButton(
          label: 'Gérer les produits',
          icon: Icons.inventory_outlined,
          variant: AppButtonVariant.secondary,
          compact: true,
          fullWidth: false,
          onPressed: () => context.go(AppRoutes.retailProducts),
        ),
      ],
    );
  }

  Widget _requestsCard(StorefrontSyncState sync, bool isDark) {
    return _Section(
      title: 'Demandes en ligne',
      icon: Icons.inbox_outlined,
      trailing: IconButton(
        tooltip: 'Actualiser',
        onPressed: () => ref.read(storefrontSyncProvider.notifier).pullInbox(),
        icon: const Icon(Icons.refresh_rounded, size: 20),
      ),
      children: [
        Row(
          children: [
            Expanded(
              child: _Stat(
                value: '${sync.openQuotes}',
                label: 'Devis à traiter',
                color: AppColors.amber,
              ),
            ),
            const SizedBox(width: AppConstants.spacing12),
            Expanded(
              child: _Stat(
                value: '${sync.paidOrders}',
                label: 'Commandes payées',
                color: AppColors.deepGreen,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppConstants.spacing8),
        Text(
          'Les devis arrivent dans Devis et les commandes payées dans Commandes, '
          'avec la mise à jour du stock.',
          style: AppTextStyles.caption(),
        ),
        const SizedBox(height: AppConstants.spacing12),
        Row(
          children: [
            Expanded(
              child: AppButton(
                label: 'Voir les devis',
                variant: AppButtonVariant.secondary,
                compact: true,
                onPressed: () => context.go(AppRoutes.retailQuotes),
              ),
            ),
            const SizedBox(width: AppConstants.spacing8),
            Expanded(
              child: AppButton(
                label: 'Voir les commandes',
                variant: AppButtonVariant.secondary,
                compact: true,
                onPressed: () => context.go(AppRoutes.retailOrderHistory),
              ),
            ),
          ],
        ),
      ],
    );
  }

  InputDecoration _fieldDecoration(String label, {String? hint}) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        hintMaxLines: 2,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusInput),
        ),
      );
}

Uint8List? _decode(String? dataUrl) {
  if (dataUrl == null) return null;
  final comma = dataUrl.indexOf(',');
  if (comma < 0) return null;
  try {
    return base64Decode(dataUrl.substring(comma + 1));
  } catch (_) {
    return null;
  }
}

enum _Live { offline, paused, open, closedAccepting, closed }

_Live _liveStatus(StorefrontSettings s) {
  if (!s.enabled) return _Live.offline;
  if (s.paused) return _Live.paused;
  if (s.isOpenAt(DateTime.now())) return _Live.open;
  return s.acceptWhenClosed ? _Live.closedAccepting : _Live.closed;
}

(String, Color) _liveLabel(_Live live) => switch (live) {
  _Live.offline => ('Hors ligne', AppColors.darkGray),
  _Live.paused => ('En pause', AppColors.amber),
  _Live.open => ('Ouverte', AppColors.deepGreen),
  _Live.closedAccepting => (
    'Fermée · commandes acceptées',
    AppColors.primaryBlue,
  ),
  _Live.closed => ('Fermée', AppColors.boldRed),
};

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.children,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AppCard(
      padding: const EdgeInsets.all(AppConstants.spacing20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.skyBlue.withValues(alpha: 0.16)
                      : AppColors.lightBlue,
                  borderRadius: BorderRadius.circular(
                    AppConstants.radiusButton,
                  ),
                ),
                child: Icon(
                  icon,
                  size: 18,
                  color: isDark ? AppColors.skyBlue : AppColors.primaryBlue,
                ),
              ),
              const SizedBox(width: AppConstants.spacing10),
              Expanded(
                child: Text(
                  title,
                  style: AppTextStyles.h2(
                    color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
                  ).copyWith(fontSize: 16),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: AppConstants.spacing16),
          ...children,
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final disabled = onChanged == null;
    return Opacity(
      opacity: disabled ? 0.5 : 1,
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppConstants.spacing12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTextStyles.body().copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle, style: AppTextStyles.caption()),
                ],
              ),
            ),
            const SizedBox(width: AppConstants.spacing12),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, required this.color});

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppConstants.spacing12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppConstants.radiusButton),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: AppTextStyles.statNumber(color: color)),
          Text(label, style: AppTextStyles.caption()),
        ],
      ),
    );
  }
}

class _SaveStatus extends StatelessWidget {
  const _SaveStatus({required this.settings, required this.sync});

  final StorefrontSettings settings;
  final StorefrontSyncState sync;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = sync.publishing
        ? ('Publication…', AppColors.primaryBlue, Icons.cloud_upload_outlined)
        : sync.error != null
        ? ('Non publiée', AppColors.boldRed, Icons.cloud_off_outlined)
        : sync.publishedAt != null
        ? (
            'Publiée à ${sync.publishedAt!.hour.toString().padLeft(2, '0')}:${sync.publishedAt!.minute.toString().padLeft(2, '0')}',
            AppColors.deepGreen,
            Icons.cloud_done_outlined,
          )
        : settings.everPublished
        ? ('Enregistrée', AppColors.deepGreen, Icons.check_rounded)
        : ('Brouillon', AppColors.darkGray, Icons.edit_note_rounded);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppConstants.radiusBadge),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppTextStyles.caption(
              color: color,
            ).copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(
        color: AppColors.boldRed.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppConstants.radiusButton),
        border: Border.all(color: AppColors.boldRed.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 18, color: AppColors.boldRed),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.body(color: AppColors.boldRed),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Réessayer')),
        ],
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    required this.settings,
    required this.name,
    required this.description,
    required this.url,
    required this.onPreview,
  });

  final StorefrontSettings settings;
  final String name;
  final String description;
  final String? url;
  final VoidCallback? onPreview;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cover = _decode(settings.coverDataUrl);
    final (label, color) = _liveLabel(_liveStatus(settings));
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppConstants.radiusCard),
            ),
            child: AspectRatio(
              aspectRatio: 16 / 7,
              child: cover != null
                  ? Image.memory(cover, fit: BoxFit.cover)
                  : DecoratedBox(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [AppColors.primaryBlue, Color(0xFF2C7BD6)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          name.isNotEmpty ? name[0].toUpperCase() : 'B',
                          style: AppTextStyles.appName(),
                        ),
                      ),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppConstants.spacing16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        label,
                        style: AppTextStyles.caption(
                          color: color,
                        ).copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppConstants.spacing6),
                Text(
                  name,
                  style: AppTextStyles.h2(
                    color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
                  ),
                ),
                if (settings.city.isNotEmpty ||
                    settings.department.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    [
                      settings.city,
                      settings.department,
                    ].where((part) => part.isNotEmpty).join(', '),
                    style: AppTextStyles.caption(),
                  ),
                ],
                if (settings.categories.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    settings.categories.join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption(),
                  ),
                ],
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    description,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.body(
                      color: isDark ? AppColors.coolGray : AppColors.darkGray,
                    ),
                  ),
                ],
                const SizedBox(height: AppConstants.spacing12),
                Text(
                  'Ouvert ${settings.openHour}h – ${settings.closeHour}h',
                  style: AppTextStyles.caption(),
                ),
                if (url != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    url!.replaceFirst(RegExp(r'^https?://'), ''),
                    style: AppTextStyles.caption(
                      color: isDark ? AppColors.skyBlue : AppColors.primaryBlue,
                    ).copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
                const SizedBox(height: AppConstants.spacing12),
                AppButton(
                  label: 'Aperçu de la vitrine',
                  icon: Icons.open_in_new_rounded,
                  variant: AppButtonVariant.ghost,
                  compact: true,
                  onPressed: onPreview,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
