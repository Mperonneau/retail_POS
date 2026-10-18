import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/customer.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/constants.dart';
import 'app_close_button.dart';

const _idDocumentTypes = [
  'Passeport',
  'Carte d\'identité',
  'Permis de conduire',
  'NIF',
  'Autre',
];

/// Searchable list of all customers (same source as Customers screens) plus
/// quick-create for store-credit identity. Returns selected customer id or null.
Future<String?> showStoreCreditRecipientPicker(
  BuildContext context, {
  required bool isDark,
}) async {
  return showDialog<String>(
    context: context,
    barrierColor: Colors.black45,
    builder: (ctx) => _StoreCreditRecipientPicker(
      isDark: isDark,
    ),
  );
}

class _StoreCreditRecipientPicker extends ConsumerStatefulWidget {
  final bool isDark;

  const _StoreCreditRecipientPicker({
    required this.isDark,
  });

  @override
  ConsumerState<_StoreCreditRecipientPicker> createState() =>
      _StoreCreditRecipientPickerState();
}

class _StoreCreditRecipientPickerState
    extends ConsumerState<_StoreCreditRecipientPicker> {
  final _searchCtrl = TextEditingController();
  bool _creating = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Customer> _filtered(List<Customer> all) {
    final q = _searchCtrl.text.trim().toLowerCase();
    final active = all.where((c) => c.isActive).toList();
    if (q.isEmpty) {
      active.sort((a, b) =>
          a.displayFirstLastName.toLowerCase().compareTo(
              b.displayFirstLastName.toLowerCase()));
      return active;
    }
    return active.where((c) {
      final blob =
          '${c.displayFirstLastName} ${c.name} ${c.phone} ${c.governmentId ?? ''}'
              .toLowerCase();
      return blob.contains(q);
    }).toList()
      ..sort((a, b) =>
          a.displayFirstLastName.toLowerCase().compareTo(
              b.displayFirstLastName.toLowerCase()));
  }

  void _select(Customer c) {
    if (!c.hasStoreCreditIdentity) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            '${c.displayFirstLastName} doit avoir un prénom et un nom, et soit '
            'une pièce d\'identité, soit une date de naissance, avant un avoir magasin.',
            style: const TextStyle(fontSize: 13),
          ),
        ),
      );
      return;
    }
    Navigator.pop(context, c.id);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final bg = isDark ? AppColors.darkSurface : AppColors.white;
    final onSurface = isDark ? AppColors.warmWhite : AppColors.nearBlack;
    final muted = isDark ? AppColors.coolGray : AppColors.darkGray;
    final customers = ref.watch(customerProvider);
    final list = _filtered(customers.customers);
    final mq = MediaQuery.of(context);
    final w = mq.size.width;
    final maxW = w < 520 ? w - 24.0 : 440.0;
    final dialogH = math.min(560.0, mq.size.height * 0.88);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        width: maxW,
        height: dialogH,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.12),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(18, 16, 8, 12),
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.darkBackground.withValues(alpha: 0.5)
                    : const Color(0xFFF4F6F8),
                border: Border(
                  bottom: BorderSide(
                    color: isDark
                        ? AppColors.darkBorder
                        : const Color(0xFFE4E7EC),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.deepGreen.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.savings_outlined,
                      color: AppColors.deepGreen,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _creating ? 'Nouveau client' : 'Émettre un avoir magasin à',
                      style: AppTextStyles.h3(color: onSurface)
                          .copyWith(fontWeight: FontWeight.w800, fontSize: 17),
                    ),
                  ),
                  if (_creating)
                    IconButton(
                      onPressed: () => setState(() => _creating = false),
                      icon: const Icon(Icons.arrow_back_rounded),
                      color: muted,
                      tooltip: 'Retour',
                    )
                  else
                    AppCloseButton(onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: AppConstants.animNormal,
                child: _creating
                    ? _QuickCustomerForCreditForm(
                        key: const ValueKey('create'),
                        isDark: isDark,
                        onCancel: () => setState(() => _creating = false),
                        onCreated: (id) => Navigator.pop(context, id),
                      )
                    : _CustomerSearchList(
                        key: const ValueKey('list'),
                        isDark: isDark,
                        searchCtrl: _searchCtrl,
                        onSearchChanged: () => setState(() {}),
                        customers: list,
                        onSelect: _select,
                        onCreateTap: () => setState(() => _creating = true),
                        muted: muted,
                        onSurface: onSurface,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomerSearchList extends StatelessWidget {
  final bool isDark;
  final TextEditingController searchCtrl;
  final VoidCallback onSearchChanged;
  final List<Customer> customers;
  final void Function(Customer) onSelect;
  final VoidCallback onCreateTap;
  final Color muted;
  final Color onSurface;

  const _CustomerSearchList({
    super.key,
    required this.isDark,
    required this.searchCtrl,
    required this.onSearchChanged,
    required this.customers,
    required this.onSelect,
    required this.onCreateTap,
    required this.muted,
    required this.onSurface,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: TextField(
            controller: searchCtrl,
            onChanged: (_) => onSearchChanged(),
            decoration: InputDecoration(
              hintText: 'Rechercher un nom ou un téléphone…',
              prefixIcon: const Icon(Icons.search_rounded, size: 22),
              filled: true,
              fillColor: isDark
                  ? AppColors.darkSurface
                  : AppColors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: isDark
                      ? AppColors.darkBorder
                      : const Color(0xFFD0D5DD),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: isDark
                      ? AppColors.darkBorder
                      : const Color(0xFFD0D5DD),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: AppColors.deepGreen,
                  width: 1.5,
                ),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              isDense: true,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onCreateTap,
              icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
              label: const Text('Créer un client'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.deepGreen,
                side: BorderSide(
                  color: AppColors.deepGreen.withValues(alpha: 0.45),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: customers.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      searchCtrl.text.trim().isEmpty
                          ? 'Aucun client. Créez-en un pour continuer.'
                          : 'Aucun résultat. Modifiez la recherche ou créez un client.',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.caption(color: muted)
                          .copyWith(height: 1.4),
                    ),
                  ),
                )
              : ListView.separated(
                  padding:
                      const EdgeInsets.fromLTRB(12, 4, 12, 16),
                  itemCount: customers.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    color: muted.withValues(alpha: 0.12),
                  ),
                  itemBuilder: (_, i) {
                    final c = customers[i];
                    final ready = c.hasStoreCreditIdentity;
                    final initials = _CustomerSearchList._initials(c);
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => onSelect(c),
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 10),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 20,
                                backgroundColor: ready
                                    ? AppColors.deepGreen
                                        .withValues(alpha: 0.15)
                                    : muted.withValues(alpha: 0.15),
                                child: Text(
                                  initials,
                                  style: AppTextStyles.caption(
                                    color: ready
                                        ? AppColors.deepGreen
                                        : muted,
                                  ).copyWith(fontWeight: FontWeight.w800),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      c.displayFirstLastName,
                                      style: AppTextStyles.body(
                                        color: onSurface,
                                      ).copyWith(fontWeight: FontWeight.w600),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      c.phone.isEmpty || c.phone == '—'
                                          ? 'Aucun téléphone enregistré'
                                          : c.phone,
                                      style:
                                          AppTextStyles.caption(color: muted),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: ready
                                      ? AppColors.deepGreen
                                          .withValues(alpha: 0.12)
                                      : AppColors.amber
                                          .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: ready
                                        ? AppColors.deepGreen
                                            .withValues(alpha: 0.35)
                                        : AppColors.amber
                                            .withValues(alpha: 0.4),
                                  ),
                                ),
                                child: Text(
                                  ready ? 'Eligible' : 'ID needed',
                                  style: AppTextStyles.caption(
                                    color: ready
                                        ? AppColors.deepGreen
                                        : AppColors.amber,
                                  ).copyWith(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
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
      ],
    );
  }

  static String _initials(Customer c) {
    final fn = c.firstName?.trim() ?? '';
    final ln = c.lastName?.trim() ?? '';
    if (fn.isNotEmpty && ln.isNotEmpty) {
      return '${fn[0]}${ln[0]}'.toUpperCase();
    }
    final name = c.name.trim();
    if (name.length >= 2) return name.substring(0, 2).toUpperCase();
    if (name.isNotEmpty) return name[0].toUpperCase();
    return '?';
  }
}

class _QuickCustomerForCreditForm extends ConsumerStatefulWidget {
  final bool isDark;
  final VoidCallback onCancel;
  final void Function(String newCustomerId) onCreated;

  const _QuickCustomerForCreditForm({
    super.key,
    required this.isDark,
    required this.onCancel,
    required this.onCreated,
  });

  @override
  ConsumerState<_QuickCustomerForCreditForm> createState() =>
      _QuickCustomerForCreditFormState();
}

class _QuickCustomerForCreditFormState
    extends ConsumerState<_QuickCustomerForCreditForm> {
  final _firstCtrl = TextEditingController();
  final _lastCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _idNumberCtrl = TextEditingController();
  String _idType = _idDocumentTypes.first;
  DateTime? _dob;
  String? _errorSummary;

  @override
  void dispose() {
    _firstCtrl.dispose();
    _lastCtrl.dispose();
    _phoneCtrl.dispose();
    _idNumberCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final initial = _dob ?? DateTime(now.year - 25, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked != null) setState(() => _dob = picked);
  }

  String? _composeGovernmentId() {
    final raw = _idNumberCtrl.text.trim();
    if (raw.isEmpty) return null;
    return '$_idType · $raw';
  }

  void _save() {
    setState(() => _errorSummary = null);
    final fn = _firstCtrl.text.trim();
    final ln = _lastCtrl.text.trim();
    if (fn.isEmpty || ln.isEmpty) {
      setState(() => _errorSummary = 'Le prénom et le nom sont obligatoires.');
      return;
    }
    final gov = _composeGovernmentId();
    if (gov == null && _dob == null) {
      setState(() {
        _errorSummary =
            'Ajoutez une pièce d\'identité (et son numéro), ou la date de naissance s\'il n\'y en a pas.';
      });
      return;
    }
    final phone = _phoneCtrl.text.trim();
    final id = 'cust_${DateTime.now().millisecondsSinceEpoch}';
    final name = '$fn $ln'.trim();
    ref.read(customerProvider.notifier).addCustomer(
          Customer(
            id: id,
            name: name,
            firstName: fn,
            lastName: ln,
            phone: phone.isEmpty ? '—' : phone,
            governmentId: gov,
            dateOfBirth: _dob,
            createdAt: DateTime.now(),
          ),
        );
    widget.onCreated(id);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final onSurface = isDark ? AppColors.warmWhite : AppColors.nearBlack;
    final muted = isDark ? AppColors.coolGray : AppColors.darkGray;
    final dobLabel = _dob == null
        ? 'Date de naissance (obligatoire sans pièce)'
        : '${_dob!.year}-${_dob!.month.toString().padLeft(2, '0')}-${_dob!.day.toString().padLeft(2, '0')}';

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Enregistré dans votre liste de clients. Le téléphone est facultatif.',
            style: AppTextStyles.caption(color: muted).copyWith(height: 1.35),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _firstCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: _decoration(
              'Prénom *',
              Icons.badge_outlined,
              isDark,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _lastCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: _decoration(
              'Nom *',
              Icons.badge_outlined,
              isDark,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            decoration: _decoration(
              'Téléphone (facultatif)',
              Icons.phone_outlined,
              isDark,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Identification',
            style: AppTextStyles.caption(color: onSurface)
                .copyWith(fontWeight: FontWeight.w800, letterSpacing: 0.2),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _idType,
            decoration: InputDecoration(
              labelText: 'Type de pièce (facultatif)',
              filled: true,
              fillColor: isDark ? AppColors.darkSurface : AppColors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: isDark ? AppColors.darkBorder : const Color(0xFFD0D5DD),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: isDark ? AppColors.darkBorder : const Color(0xFFD0D5DD),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    const BorderSide(color: AppColors.deepGreen, width: 1.5),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              isDense: true,
            ),
            items: _idDocumentTypes
                .map(
                  (t) => DropdownMenuItem(value: t, child: Text(t)),
                )
                .toList(),
            onChanged: (v) {
              if (v != null) setState(() => _idType = v);
            },
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _idNumberCtrl,
            decoration: _decoration(
              'Numéro de pièce (facultatif)',
              Icons.credit_card_outlined,
              isDark,
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _pickDob,
            icon: const Icon(Icons.cake_outlined, size: 18),
            label: Text(dobLabel),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
              foregroundColor: onSurface,
              side: BorderSide(
                color: isDark ? AppColors.darkBorder : const Color(0xFFD0D5DD),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          if (_errorSummary != null) ...[
            const SizedBox(height: 12),
            Text(
              _errorSummary!,
              style: AppTextStyles.caption(color: AppColors.boldRed)
                  .copyWith(fontWeight: FontWeight.w600),
            ),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: widget.onCancel,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Annuler'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.deepGreen,
                    foregroundColor: AppColors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'Enregistrer et choisir',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  InputDecoration _decoration(String label, IconData icon, bool isDark) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20),
      filled: true,
      fillColor: isDark ? AppColors.darkSurface : AppColors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
          color: isDark ? AppColors.darkBorder : const Color(0xFFD0D5DD),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
          color: isDark ? AppColors.darkBorder : const Color(0xFFD0D5DD),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.deepGreen, width: 1.5),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      isDense: true,
    );
  }
}
