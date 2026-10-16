import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/navigation/app_routes.dart';
import '../../core/data/supported_countries.dart';
import '../../core/models/currency_settings.dart';
import '../../core/mock/mock_retail_data.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/utils/auth_logout.dart';
import '../../core/providers/currency_settings_provider.dart';
import '../../core/providers/tax_settings_provider.dart';
import '../../core/providers/theme_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/constants.dart';
import '../../core/utils/input_formatters.dart';
import '../../core/models/staff_directory_entry.dart';
import '../../core/models/staff_role.dart';
import '../../core/providers/staff_directory_provider.dart';
import '../../core/widgets/app_bottom_sheet.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_card.dart';
import '../widgets/permissions_matrix_tab.dart';
import '../widgets/staff_editor_sheet.dart';
import '../widgets/staff_permission_panel.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _tabs = [
    'Business',
    'Currency',
    'Language',
    'Appearance',
    'Tax & Fees',
    'Permissions',
    'Staff',
    'Subscription'
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            child: Text('Settings',
                style: AppTextStyles.h1(
                  color: isDark ? AppColors.warmWhite : AppColors.primaryBlue,
                )),
          ),
          const SizedBox(height: AppConstants.spacing16),
          TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            tabs: _tabs.map((t) => Tab(text: t)).toList(),
          ),
          const Divider(height: 1),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _BusinessTab(),
                _CurrencyTab(),
                _LanguageTab(),
                _AppearanceTab(),
                _TaxTab(),
                const PermissionsMatrixTab(),
                const _StaffTab(),
                _SubscriptionTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BusinessTab extends ConsumerStatefulWidget {
  @override
  ConsumerState<_BusinessTab> createState() => _BusinessTabState();
}

class _BusinessTabState extends ConsumerState<_BusinessTab> {
  String _address = 'Pétion-Ville, Port-au-Prince';
  String _phone = '+509 3456-7890';
  String _email = 'contact@karibe.ht';
  String _receiptHeader = 'Hôtel Karibe - Merci!';
  String _receiptFooter = 'Mèsi pou vizit ou!';

  void _showEditProfileSheet(BuildContext context, bool isDark, AuthState auth) {
    final nameCtrl = TextEditingController(text: auth.businessName ?? 'Hôtel Karibe');
    final ownerCtrl = TextEditingController(text: auth.userName ?? 'Jean-Marc Dupont');
    final addressCtrl = TextEditingController(text: _address);
    final phoneCtrl = TextEditingController(text: _phone);
    final emailCtrl = TextEditingController(text: _email);

    showAppBottomSheet(
      context: context,
      child: Padding(
          padding: EdgeInsets.only(
            left: AppConstants.spacing24,
            right: AppConstants.spacing24,
            top: AppConstants.spacing24,
            bottom: MediaQuery.of(context).viewInsets.bottom + AppConstants.spacing24,
          ),
          child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Edit Business Profile',
                  style: AppTextStyles.h2(
                      color: isDark ? AppColors.warmWhite : AppColors.nearBlack)),
              const SizedBox(height: AppConstants.spacing16),
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: 'Business Name',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppConstants.radiusInput)),
                ),
              ),
              const SizedBox(height: AppConstants.spacing12),
              TextField(
                controller: ownerCtrl,
                decoration: InputDecoration(
                  labelText: 'Owner Name',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppConstants.radiusInput)),
                ),
              ),
              const SizedBox(height: AppConstants.spacing12),
              TextField(
                controller: addressCtrl,
                decoration: InputDecoration(
                  labelText: 'Address',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppConstants.radiusInput)),
                ),
              ),
              const SizedBox(height: AppConstants.spacing12),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: phoneCtrl,
                    decoration: InputDecoration(
                      labelText: 'Phone',
                      border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(AppConstants.radiusInput)),
                    ),
                    keyboardType: TextInputType.phone,
                    inputFormatters: InputFormatters.phone,
                  ),
                ),
                const SizedBox(width: AppConstants.spacing12),
                Expanded(
                  child: TextField(
                    controller: emailCtrl,
                    decoration: InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(AppConstants.radiusInput)),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    inputFormatters: InputFormatters.email,
                  ),
                ),
              ]),
              const SizedBox(height: AppConstants.spacing24),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: AppConstants.spacing12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _address = addressCtrl.text.trim();
                        _phone = phoneCtrl.text.trim();
                        _email = emailCtrl.text.trim();
                      });
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.amber,
                      foregroundColor: AppColors.nearBlack,
                    ),
                    child: const Text('Save'),
                  ),
                ),
              ]),
              const SizedBox(height: AppConstants.spacing8),
            ],
          ),
        ),
      ),
    );
  }

  void _showCustomizeReceiptSheet(BuildContext context, bool isDark) {
    final headerCtrl = TextEditingController(text: _receiptHeader);
    final footerCtrl = TextEditingController(text: _receiptFooter);

    showAppBottomSheet(
      context: context,
      child: Padding(
          padding: EdgeInsets.only(
            left: AppConstants.spacing24,
            right: AppConstants.spacing24,
            top: AppConstants.spacing24,
            bottom: MediaQuery.of(context).viewInsets.bottom + AppConstants.spacing24,
          ),
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Customize Receipt',
                style: AppTextStyles.h2(
                    color: isDark ? AppColors.warmWhite : AppColors.nearBlack)),
            const SizedBox(height: AppConstants.spacing16),
            TextField(
              controller: headerCtrl,
              decoration: InputDecoration(
                labelText: 'Receipt Header',
                helperText: 'Shown at top of every receipt',
                border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(AppConstants.radiusInput)),
              ),
            ),
            const SizedBox(height: AppConstants.spacing12),
            TextField(
              controller: footerCtrl,
              decoration: InputDecoration(
                labelText: 'Receipt Footer',
                helperText: 'Thank-you message at the bottom',
                border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(AppConstants.radiusInput)),
              ),
            ),
            const SizedBox(height: AppConstants.spacing24),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: AppConstants.spacing12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _receiptHeader = headerCtrl.text.trim();
                      _receiptFooter = footerCtrl.text.trim();
                    });
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.amber,
                    foregroundColor: AppColors.nearBlack,
                  ),
                  child: const Text('Save'),
                ),
              ),
            ]),
            const SizedBox(height: AppConstants.spacing8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppConstants.spacing24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Business Profile', style: AppTextStyles.h3()),
                const SizedBox(height: AppConstants.spacing16),
                _SettingsRow(
                    label: 'Business Name',
                    value: auth.businessName ?? 'Hôtel Karibe'),
                _SettingsRow(
                    label: 'Owner', value: auth.userName ?? 'Jean-Marc Dupont'),
                _SettingsRow(label: 'Address', value: _address),
                _SettingsRow(label: 'Phone', value: _phone),
                _SettingsRow(label: 'Email', value: _email),
                const SizedBox(height: AppConstants.spacing16),
                AppButton(
                    label: 'Edit Business Profile',
                    onPressed: () => _showEditProfileSheet(context, isDark, auth),
                    variant: AppButtonVariant.secondary,
                    icon: Icons.edit_outlined),
              ],
            ),
          ),
          const SizedBox(height: AppConstants.spacing16),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Module Settings', style: AppTextStyles.h3()),
                const SizedBox(height: AppConstants.spacing16),
                _SettingsRow(
                    label: 'Active Module', value: 'Hotel & Restaurant'),
                _SettingsRow(label: 'Receipt Header', value: _receiptHeader),
                _SettingsRow(label: 'Receipt Footer', value: _receiptFooter),
                const SizedBox(height: AppConstants.spacing16),
                AppButton(
                    label: 'Customize Receipt',
                    onPressed: () => _showCustomizeReceiptSheet(context, isDark),
                    variant: AppButtonVariant.secondary,
                    icon: Icons.receipt_outlined),
              ],
            ),
          ),
          if (auth.module == ActiveModule.retail) ...[
            const SizedBox(height: AppConstants.spacing16),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Retail checkout', style: AppTextStyles.h3()),
                  const SizedBox(height: AppConstants.spacing8),
                  Text(
                    'Turn off options you do not use. If both Pickup and Delivery are off, checkout only asks for client. In store is always the default when options are shown.',
                    style: AppTextStyles.caption(
                      color: isDark
                          ? AppColors.coolGray
                          : AppColors.darkGray,
                    ),
                  ),
                  const SizedBox(height: AppConstants.spacing12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Pickup (collect later at store)',
                          style: AppTextStyles.body(),
                        ),
                      ),
                      Switch(
                        value: ref.watch(retailSettingsProvider).pickupEnabled,
                        onChanged: (v) => ref
                            .read(retailSettingsProvider.notifier)
                            .setPickupEnabled(v),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppConstants.spacing8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Delivery',
                          style: AppTextStyles.body(),
                        ),
                      ),
                      Switch(
                        value:
                            ref.watch(retailSettingsProvider).deliveryEnabled,
                        onChanged: (v) => ref
                            .read(retailSettingsProvider.notifier)
                            .setDeliveryEnabled(v),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppConstants.spacing24),
          AppButton(
            label: 'Log Out',
            onPressed: () {
              logoutCompletely(ref);
              context.go(AppRoutes.login);
            },
            variant: AppButtonVariant.danger,
            icon: Icons.logout_outlined,
          ),
        ],
      ),
    );
  }
}

class _CurrencyTab extends ConsumerStatefulWidget {
  @override
  ConsumerState<_CurrencyTab> createState() => _CurrencyTabState();
}

class _CurrencyTabState extends ConsumerState<_CurrencyTab> {
  bool _synced = false;
  late String _countryCode;
  late BusinessCurrencyMode _mode;
  late final TextEditingController _rateCtrl;
  String? _rateError;

  @override
  void initState() {
    super.initState();
    _rateCtrl = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_synced) return;
    _synced = true;
    final s = ref.read(currencySettingsProvider);
    _countryCode = s.countryCode;
    _mode = s.mode;
    _rateCtrl.text = s.isLocalUsd
        ? '1'
        : (s.usdToLocalRate % 1 == 0
            ? s.usdToLocalRate.toStringAsFixed(0)
            : s.usdToLocalRate.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _rateCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = countryByCode(_countryCode);
    final localCode = c?.currencyCode ?? 'HTG';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppConstants.spacing24),
      child: Column(
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Currency Settings', style: AppTextStyles.h3()),
                const SizedBox(height: AppConstants.spacing8),
                Text(
                  'One exchange rate for your whole business. It applies to every module (restaurant, hotel, retail) and updates USD amounts on screen and when taking cash in USD.',
                  style: AppTextStyles.caption(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? AppColors.coolGray
                        : AppColors.darkGray,
                  ),
                ),
                const SizedBox(height: AppConstants.spacing16),
                DropdownButtonFormField<String>(
                  value: _countryCode,
                  decoration: InputDecoration(
                    labelText: 'Country',
                    border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(AppConstants.radiusInput),
                    ),
                  ),
                  items: kSupportedCountries
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.code,
                          child: Text('${e.name} · ${e.currencyCode}'),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() {
                      _countryCode = v;
                      _mode = BusinessCurrencyMode.both;
                      final nc = countryByCode(v);
                      if (nc != null && nc.currencyCode != 'USD') {
                        final s = ref.read(currencySettingsProvider);
                        _rateCtrl.text = s.usdToLocalRate % 1 == 0
                            ? s.usdToLocalRate.toStringAsFixed(0)
                            : s.usdToLocalRate.toStringAsFixed(2);
                      } else {
                        _rateCtrl.text = '1';
                      }
                    });
                  },
                ),
                if (c != null && c.currencyCode != 'USD') ...[
                  const SizedBox(height: AppConstants.spacing16),
                  TextField(
                    controller: _rateCtrl,
                    onChanged: (_) => setState(() => _rateError = null),
                    decoration: InputDecoration(
                      labelText: 'Exchange rate (1 USD = ? $localCode)',
                      errorText: _rateError,
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppConstants.radiusInput),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppConstants.radiusInput),
                        borderSide: const BorderSide(color: AppColors.boldRed),
                      ),
                      focusedErrorBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppConstants.radiusInput),
                        borderSide:
                            const BorderSide(color: AppColors.boldRed, width: 2),
                      ),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: InputFormatters.decimalAmount,
                  ),
                ],
                if (c != null && c.currencyCode != 'USD') ...[
                  const SizedBox(height: AppConstants.spacing8),
                  Theme(
                    data: Theme.of(context)
                        .copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: const EdgeInsets.only(top: 8),
                      title: Text(
                        'Pricing mode (optional)',
                        style: AppTextStyles.body().copyWith(
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? AppColors.skyBlue
                              : AppColors.primaryBlue,
                        ),
                      ),
                      subtitle: Text(
                        'Default: local currency with USD reference and optional USD cash.',
                        style: AppTextStyles.caption(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? AppColors.coolGray
                              : AppColors.darkGray,
                        ),
                      ),
                      children: [
                        ...[
                          (
                            BusinessCurrencyMode.both,
                            'Local + USD reference',
                            'Recommended: $localCode primary; USD on totals and optional cash',
                          ),
                          (
                            BusinessCurrencyMode.localOnly,
                            'Local only',
                            'Prices and cash in $localCode',
                          ),
                          (
                            BusinessCurrencyMode.usdOnly,
                            'USD only',
                            'US Dollar pricing and cash',
                          ),
                        ].map((row) {
                          final isSelected = _mode == row.$1;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: GestureDetector(
                              onTap: () => setState(() => _mode = row.$1),
                              child: AnimatedContainer(
                                duration: AppConstants.animFast,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isSelected
                                        ? AppColors.primaryBlue
                                        : const Color(0xFFE0E0E0),
                                    width: isSelected ? 2 : 1,
                                  ),
                                  color: isSelected
                                      ? AppColors.lightBlue
                                      : Colors.transparent,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(row.$2,
                                              style: AppTextStyles.body()),
                                          Text(row.$3,
                                              style: AppTextStyles.caption()),
                                        ],
                                      ),
                                    ),
                                    Radio<BusinessCurrencyMode>(
                                      value: row.$1,
                                      groupValue: _mode,
                                      onChanged: (v) => setState(
                                          () => _mode = v ?? _mode),
                                      activeColor: AppColors.primaryBlue,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ] else if (c != null && c.currencyCode == 'USD') ...[
                  const SizedBox(height: AppConstants.spacing12),
                  Text(
                    'Prices and cash use US dollars (USD).',
                    style: AppTextStyles.caption(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? AppColors.coolGray
                          : AppColors.darkGray,
                    ),
                  ),
                ],
                const SizedBox(height: AppConstants.spacing16),
                AppButton(
                  label: 'Save Currency Settings',
                  onPressed: () {
                    final parsed = double.tryParse(_rateCtrl.text.trim());
                    final nc = countryByCode(_countryCode);
                    if (nc != null &&
                        nc.currencyCode != 'USD' &&
                        (parsed == null || parsed <= 0)) {
                      setState(() => _rateError = 'Enter a valid exchange rate (must be greater than 0).');
                      return;
                    }
                    setState(() => _rateError = null);
                    ref.read(currencySettingsProvider.notifier).setFromSettings(
                          countryCode: _countryCode,
                          mode: _mode,
                          usdToLocalRate: parsed ?? 1,
                        );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Currency settings saved')),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LanguageTab extends StatefulWidget {
  @override
  State<_LanguageTab> createState() => _LanguageTabState();
}

class _LanguageTabState extends State<_LanguageTab> {
  String _lang = 'kr';

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppConstants.spacing24),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Language', style: AppTextStyles.h3()),
            const SizedBox(height: AppConstants.spacing16),
            ...[
              ('kr', 'Kreyòl Ayisyen', 'Primary language of Haiti'),
              ('fr', 'Français', 'French'),
              ('en', 'English', 'English')
            ].map((l) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: RadioListTile<String>(
                  title: Text(l.$2, style: AppTextStyles.body()),
                  subtitle: Text(l.$3, style: AppTextStyles.caption()),
                  value: l.$1,
                  groupValue: _lang,
                  onChanged: (v) => setState(() => _lang = v!),
                  activeColor: AppColors.primaryBlue,
                  contentPadding: EdgeInsets.zero,
                ),
              );
            }),
            const SizedBox(height: AppConstants.spacing16),
            AppButton(label: 'Save Language', onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Language settings saved')),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _AppearanceTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeSetting = ref.watch(themeProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppConstants.spacing24),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Theme', style: AppTextStyles.h3()),
            const SizedBox(height: AppConstants.spacing16),
            ...[
              (
                ThemeSetting.auto,
                'Auto (Time-based)',
                'Light 6am–6pm · Dark 6pm–6am'
              ),
              (ThemeSetting.light, 'Always Light', 'Deep Ocean Blue theme'),
              (ThemeSetting.dark, 'Always Dark', 'Deep Charcoal Navy theme'),
            ].map((t) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: RadioListTile<ThemeSetting>(
                    title: Text(t.$2, style: AppTextStyles.body()),
                    subtitle: Text(t.$3, style: AppTextStyles.caption()),
                    value: t.$1,
                    groupValue: themeSetting,
                    onChanged: (v) =>
                        ref.read(themeProvider.notifier).setTheme(v!),
                    activeColor: AppColors.primaryBlue,
                    contentPadding: EdgeInsets.zero,
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

class _TaxTab extends ConsumerStatefulWidget {
  @override
  ConsumerState<_TaxTab> createState() => _TaxTabState();
}

class _TaxTabState extends ConsumerState<_TaxTab> {
  double? _taxPercent;
  bool? _taxEnabled;
  bool? _gratuityEnabled;
  double? _gratuityPercent;
  bool? _discountAllowed;
  final _discountCodeCtrl = TextEditingController();
  bool _loaded = false;

  static const _percentOptions = [0, 5, 10, 15, 20];

  @override
  void dispose() {
    _discountCodeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      _loaded = true;
      _taxPercent = ref.read(taxPercentProvider);
      _taxEnabled = ref.read(taxEnabledProvider);
      _gratuityEnabled = ref.read(gratuityEnabledProvider);
      _gratuityPercent = ref.read(gratuityPercentProvider);
      _discountAllowed = ref.read(discountAllowedProvider);
      _discountCodeCtrl.text = ref.read(discountApprovalCodeProvider);
    }
    final taxPercent = _taxPercent ?? ref.watch(taxPercentProvider);
    final taxEnabled = _taxEnabled ?? ref.watch(taxEnabledProvider);
    final gratuityEnabled = _gratuityEnabled ?? ref.watch(gratuityEnabledProvider);
    final gratuityPercent = _gratuityPercent ?? ref.watch(gratuityPercentProvider);
    final discountAllowed = _discountAllowed ?? ref.watch(discountAllowedProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppConstants.spacing24),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tax & Fees', style: AppTextStyles.h3()),
            const SizedBox(height: AppConstants.spacing16),
            SwitchListTile(
              title: Text('Enable tax', style: AppTextStyles.body()),
              subtitle: Text('Apply tax on bills (all modules)',
                  style: AppTextStyles.caption()),
              value: taxEnabled == true,
              onChanged: (v) => setState(() => _taxEnabled = v),
              activeThumbColor: AppColors.primaryBlue,
              contentPadding: EdgeInsets.zero,
            ),
            Text('Tax rate (when enabled)', style: AppTextStyles.body()),
            const SizedBox(height: AppConstants.spacing8),
            DropdownButtonFormField<double>(
              value: taxPercent,
              decoration: InputDecoration(
                labelText: 'Tax %',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusInput),
                ),
              ),
              items: _percentOptions
                  .map((v) => DropdownMenuItem(
                        value: v.toDouble(),
                        child: Text('$v%'),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _taxPercent = v ?? 0),
            ),
            const Divider(height: AppConstants.spacing24),
            SwitchListTile(
              title: Text('Enable gratuity (service charge)', style: AppTextStyles.body()),
              subtitle: Text('Add gratuity % to bills (all modules)',
                  style: AppTextStyles.caption()),
              value: gratuityEnabled == true,
              onChanged: (v) => setState(() => _gratuityEnabled = v),
              activeThumbColor: AppColors.primaryBlue,
              contentPadding: EdgeInsets.zero,
            ),
            Text('Gratuity % (when enabled)', style: AppTextStyles.body()),
            const SizedBox(height: AppConstants.spacing8),
            DropdownButtonFormField<double>(
              value: gratuityPercent,
              decoration: InputDecoration(
                labelText: 'Gratuity %',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusInput),
                ),
              ),
              items: _percentOptions
                  .map((v) => DropdownMenuItem(
                        value: v.toDouble(),
                        child: Text('$v%'),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _gratuityPercent = v ?? 0),
            ),
            const Divider(height: AppConstants.spacing24),
            SwitchListTile(
              title: Text('Allow discount on bills', style: AppTextStyles.body()),
              subtitle: Text('When off, discount option is hidden (all modules)',
                  style: AppTextStyles.caption()),
              value: discountAllowed == true,
              onChanged: (v) => setState(() => _discountAllowed = v),
              activeThumbColor: AppColors.primaryBlue,
              contentPadding: EdgeInsets.zero,
            ),
            Text('Discount approval', style: AppTextStyles.body()),
            const SizedBox(height: AppConstants.spacing4),
            Text('Code or password required to apply a discount on a bill.',
                style: AppTextStyles.caption()),
            const SizedBox(height: AppConstants.spacing8),
            TextField(
              controller: _discountCodeCtrl,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'Discount approval code',
                hintText: 'Enter code admins will use',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusInput),
                ),
              ),
            ),
            const SizedBox(height: AppConstants.spacing24),
            AppButton(
              label: 'Save Tax & Fees',
              onPressed: () {
                ref.read(taxEnabledProvider.notifier).state =
                    _taxEnabled ?? ref.read(taxEnabledProvider);
                ref.read(taxPercentProvider.notifier).state =
                    _taxPercent ?? ref.read(taxPercentProvider);
                ref.read(gratuityEnabledProvider.notifier).state =
                    _gratuityEnabled ?? ref.read(gratuityEnabledProvider);
                ref.read(gratuityPercentProvider.notifier).state =
                    _gratuityPercent ?? ref.read(gratuityPercentProvider);
                ref.read(discountAllowedProvider.notifier).state =
                    _discountAllowed ?? ref.read(discountAllowedProvider);
                ref.read(discountApprovalCodeProvider.notifier).state =
                    _discountCodeCtrl.text.trim().isEmpty
                        ? 'admin'
                        : _discountCodeCtrl.text.trim();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Tax & fees settings saved')),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _StaffTab extends ConsumerWidget {
  const _StaffTab();

  void _openEditor(BuildContext context, bool isDark, {StaffDirectoryEntry? existing}) {
    showAppBottomSheet(
      context: context,
      child: StaffEditorSheet(isDark: isDark, existing: existing),
    );
  }

  void _showStaffOptions(
    BuildContext context,
    WidgetRef ref,
    bool isDark,
    StaffDirectoryEntry entry,
  ) {
    showAppBottomSheet(
      context: context,
      isScrollControlled: false,
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit'),
              onTap: () {
                Navigator.pop(context);
                _openEditor(context, isDark, existing: entry);
              },
            ),
            ListTile(
              leading: const Icon(Icons.admin_panel_settings_outlined),
              title: const Text('Manage permission'),
              onTap: () {
                Navigator.pop(context);
                showStaffPermissionPanel(context, entry);
              },
            ),
            ListTile(
              leading: Icon(
                entry.isActive ? Icons.block_outlined : Icons.check_circle_outline,
                color: entry.isActive ? AppColors.amber : AppColors.deepGreen,
              ),
              title: Text(entry.isActive ? 'Deactivate' : 'Activate'),
              onTap: () {
                ref.read(staffDirectoryProvider.notifier).update(
                      entry.copyWith(isActive: !entry.isActive),
                    );
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.boldRed),
              title: const Text('Remove', style: TextStyle(color: AppColors.boldRed)),
              onTap: () {
                ref.read(staffDirectoryProvider.notifier).remove(entry.id);
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final staff = ref.watch(staffDirectoryProvider);

    return Padding(
      padding: const EdgeInsets.all(AppConstants.spacing24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Staff Members', style: AppTextStyles.h3())),
              AppButton(
                label: 'Add Staff',
                onPressed: () => _openEditor(context, isDark),
                icon: Icons.person_add_outlined,
                fullWidth: false,
                width: 130,
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spacing16),
          Expanded(
            child: ListView.separated(
              itemCount: staff.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AppConstants.spacing8),
              itemBuilder: (_, i) {
                final s = staff[i];
                final initial = s.fullName.isNotEmpty ? s.fullName[0] : '?';
                return AppCard(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor:
                            AppColors.primaryBlue.withValues(alpha: 0.1),
                        child: Text(
                          initial.toUpperCase(),
                          style: AppTextStyles.body(
                            color: isDark
                                ? AppColors.skyBlue
                                : AppColors.primaryBlue,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.fullName,
                              style: AppTextStyles.body(
                                color: isDark
                                    ? AppColors.warmWhite
                                    : AppColors.nearBlack,
                              ),
                            ),
                            Text(
                              '${staffRoleDisplayLabel(s.role)} · ${s.phone}',
                              style: AppTextStyles.caption(),
                            ),
                            Text(
                              s.email,
                              style: AppTextStyles.caption(
                                color: isDark
                                    ? AppColors.coolGray
                                    : AppColors.darkGray,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(top: 6),
                        decoration: BoxDecoration(
                          color: s.isActive
                              ? AppColors.deepGreen
                              : AppColors.darkGray,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.more_vert, size: 18),
                        onPressed: () =>
                            _showStaffOptions(context, ref, isDark, s),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SubscriptionTab extends StatelessWidget {
  void _showManageSubscriptionDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Manage Subscription'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Current Plan: Pro (Active)', style: AppTextStyles.body()),
            const SizedBox(height: 8),
            Text('Renews: March 26, 2026', style: AppTextStyles.caption()),
            const SizedBox(height: 16),
            Text('To upgrade, downgrade, or cancel your subscription, please contact support or visit our billing portal.',
                style: AppTextStyles.caption()),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.amber,
              foregroundColor: AppColors.nearBlack,
            ),
            child: const Text('Contact Support'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppConstants.spacing24),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(AppConstants.spacing24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primaryBlue,
                  AppColors.primaryBlue.withValues(alpha: 0.7)
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(AppConstants.radiusCard),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.star_rounded,
                        color: AppColors.amber, size: 28),
                    const SizedBox(width: 8),
                    Text('Pro Plan',
                        style: AppTextStyles.h2(color: AppColors.white)),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.amber,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('Active',
                          style: AppTextStyles.caption(
                              color: AppColors.nearBlack)),
                    ),
                  ],
                ),
                const SizedBox(height: AppConstants.spacing16),
                Text('Renews: March 26, 2026',
                    style: AppTextStyles.body(color: Colors.white70)),
                Text('All modules · Unlimited staff · Priority support',
                    style: AppTextStyles.caption(color: Colors.white54)),
              ],
            ),
          ),
          const SizedBox(height: AppConstants.spacing24),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Plan Features', style: AppTextStyles.h3()),
                const SizedBox(height: AppConstants.spacing12),
                ...[
                  'Hotel & Restaurant module',
                  'Retail module',
                  'MonCash integration',
                  'Stripe card payments',
                  'Offline mode',
                  'Multi-language (KR/FR/EN)',
                  'Unlimited transactions',
                  'Priority email support',
                ].map((f) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle_rounded,
                              color: AppColors.deepGreen, size: 16),
                          const SizedBox(width: 8),
                          Text(f, style: AppTextStyles.body()),
                        ],
                      ),
                    )),
              ],
            ),
          ),
          const SizedBox(height: AppConstants.spacing16),
          AppButton(
              label: 'Manage Subscription',
              onPressed: () => _showManageSubscriptionDialog(context),
              variant: AppButtonVariant.secondary,
              icon: Icons.manage_accounts_outlined),
        ],
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final String label;
  final String value;
  const _SettingsRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
              width: 140, child: Text(label, style: AppTextStyles.caption())),
          Expanded(
              child: Text(value,
                  style: AppTextStyles.body(
                    color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
                  ))),
        ],
      ),
    );
  }
}
