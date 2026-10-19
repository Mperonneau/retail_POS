import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/customer.dart';
import '../../models/paylink.dart';
import '../../payments/card_charge_pricing.dart';
import '../../payments/payments_client.dart';
import '../../providers/currency_settings_provider.dart';
import '../../theme/app_colors.dart';
import '../../widgets/card_fee_breakdown.dart';
import '../../theme/app_text_styles.dart';
import '../../utils/constants.dart';
import '../../utils/currency_formatter.dart';
import '../../widgets/app_close_button.dart';

// ─── Entry function ───────────────────────────────────────────────────────────

/// Returns the created [PayLink] if the user sent it; otherwise null.
Future<PayLink?> showNewPayLinkModal(
  BuildContext context, {
  required bool isDark,
  required StateNotifierProvider<PayLinkNotifier, PayLinkState> payLinkProvider,
  required StateNotifierProvider<CustomerNotifier, CustomerState>
  customerProvider,
}) async {
  return showDialog<PayLink?>(
    context: context,
    barrierColor: Colors.black54,
    builder: (ctx) => _NewPayLinkModal(
      isDark: isDark,
      payLinkProvider: payLinkProvider,
      customerProvider: customerProvider,
    ),
  );
}

// ─── Modal widget ─────────────────────────────────────────────────────────────

class _NewPayLinkModal extends ConsumerStatefulWidget {
  final bool isDark;
  final StateNotifierProvider<PayLinkNotifier, PayLinkState> payLinkProvider;
  final StateNotifierProvider<CustomerNotifier, CustomerState> customerProvider;

  const _NewPayLinkModal({
    required this.isDark,
    required this.payLinkProvider,
    required this.customerProvider,
  });

  @override
  ConsumerState<_NewPayLinkModal> createState() => _NewPayLinkModalState();
}

enum _ModalStep { pickCustomer, fillDetails }

class _NewPayLinkModalState extends ConsumerState<_NewPayLinkModal> {
  _ModalStep _step = _ModalStep.fillDetails;
  bool _creatingCustomer = false;
  bool _sending = false;
  String? _sendError;

  // Optional existing customer. The link can be sent to anyone.
  Customer? _customer;

  // Form controllers
  final _nameCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();

  PayLinkChannel _channel = PayLinkChannel.whatsApp;
  DateTime? _expiresAt;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    _contactCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _selectCustomer(Customer c) {
    setState(() {
      _customer = c;
      if (_nameCtrl.text.trim().isEmpty) {
        _nameCtrl.text = c.displayFirstLastName;
      }
      _step = _ModalStep.fillDetails;
      _creatingCustomer = false;
    });
  }

  bool get _canSend {
    if (_sending) return false;
    final amt = double.tryParse(_amountCtrl.text.replaceAll(',', '').trim());
    if (amt == null || amt <= 0) return false;
    if (_nameCtrl.text.trim().isEmpty) return false;
    return _contactCtrl.text.trim().isNotEmpty;
  }

  CardChargePricing? _pricingFor(double localPerUsd) {
    final amt = double.tryParse(_amountCtrl.text.replaceAll(',', '').trim());
    if (amt == null || amt <= 0) return null;
    final cents = CardChargePricing.htgToUsdCents(amt, localPerUsd);
    if (cents <= 0) return null;
    return CardChargePricing.fromOrderUsdCents(cents);
  }

  Future<void> _send() async {
    if (!_canSend) return;
    final amt = double.parse(_amountCtrl.text.replaceAll(',', '').trim());
    final pricing = _pricingFor(
      ref.read(currencySettingsProvider).usdToLocalRate,
    );
    if (pricing == null) {
      setState(
        () => _sendError =
            'Taux de change indisponible — impossible de créer le lien en dollars.',
      );
      return;
    }
    final name = _nameCtrl.text.trim();
    final contact = _contactCtrl.text.trim();
    final email = _channel == PayLinkChannel.email ? contact : null;
    final phone = _channel == PayLinkChannel.email
        ? (_customer?.phone ?? '')
        : contact;
    final reference =
        'PL-${DateTime.now().year}-${DateTime.now().millisecondsSinceEpoch}';
    setState(() {
      _sending = true;
      _sendError = null;
    });
    final client = PaymentsClient();
    try {
      final session = await client.createCheckout(
        reference: reference,
        orderUsdCents: pricing.orderUsdCents,
        description: 'Lien $reference',
        recipientName: name,
        recipientEmail: email ?? '',
        recipientPhone: phone,
      );
      if (!mounted) return;
      final link = ref
          .read(widget.payLinkProvider.notifier)
          .create(
            customerId: _customer?.id ?? '',
            customerName: name,
            customerPhone: phone,
            payerEmail: email,
            amountHtg: amt,
            channel: _channel,
            sentTo: contact,
            note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
            expiresAt: _expiresAt,
            createdBy: 'Personnel',
            reference: reference,
            paymentUrl: session.url,
            stripeSessionId: session.id,
            payerTotalUsdCents: session.pricing.totalUsdCents,
            platformFeeUsdCents: session.pricing.platformFeeUsdCents,
            stripeFeeUsdCents: session.pricing.stripeFeeUsdCents,
          );
      Navigator.of(context).pop<PayLink?>(link);
    } on PaymentsException catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _sendError = e.message;
      });
    } finally {
      client.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final mq = MediaQuery.of(context);
    final w = mq.size.width;
    final maxW = w < 540 ? w - 24.0 : 520.0;
    final maxH = math.min(680.0, mq.size.height * 0.9);
    final bg = isDark ? AppColors.darkSurface : AppColors.white;
    final textColor = isDark ? AppColors.warmWhite : AppColors.nearBlack;
    final mutedColor = isDark ? AppColors.coolGray : AppColors.darkGray;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        width: maxW,
        constraints: BoxConstraints(maxHeight: maxH),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.15),
              blurRadius: 32,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ModalHeader(
              isDark: isDark,
              step: _step,
              customer: _customer,
              textColor: textColor,
              mutedColor: mutedColor,
              onBack: _step == _ModalStep.pickCustomer
                  ? () => setState(() {
                      if (_creatingCustomer) {
                        _creatingCustomer = false;
                      } else {
                        _step = _ModalStep.fillDetails;
                      }
                    })
                  : null,
              onClose: () => Navigator.pop(context),
            ),
            Flexible(
              child: AnimatedSwitcher(
                duration: AppConstants.animNormal,
                child: _step == _ModalStep.pickCustomer
                    ? (_creatingCustomer
                          ? _QuickCreateCustomer(
                              key: const ValueKey('create'),
                              isDark: isDark,
                              customerProvider: widget.customerProvider,
                              textColor: textColor,
                              mutedColor: mutedColor,
                              onCreated: _selectCustomer,
                            )
                          : _CustomerPicker(
                              key: const ValueKey('pick'),
                              isDark: isDark,
                              customerProvider: widget.customerProvider,
                              searchCtrl: _searchCtrl,
                              onSelect: _selectCustomer,
                              onCreateTap: () =>
                                  setState(() => _creatingCustomer = true),
                              textColor: textColor,
                              mutedColor: mutedColor,
                            ))
                    : _PayLinkForm(
                        key: const ValueKey('form'),
                        isDark: isDark,
                        customer: _customer,
                        nameCtrl: _nameCtrl,
                        amountCtrl: _amountCtrl,
                        noteCtrl: _noteCtrl,
                        contactCtrl: _contactCtrl,
                        channel: _channel,
                        expiresAt: _expiresAt,
                        canSend: _canSend,
                        sending: _sending,
                        pricing: _pricingFor(
                          ref.watch(currencySettingsProvider).usdToLocalRate,
                        ),
                        error: _sendError,
                        textColor: textColor,
                        mutedColor: mutedColor,
                        onChannelChanged: (c) => setState(() => _channel = c),
                        onExpiryChanged: (d) => setState(() => _expiresAt = d),
                        onAmountChanged: () => setState(() {}),
                        onContactChanged: () => setState(() {}),
                        onPickCustomer: () =>
                            setState(() => _step = _ModalStep.pickCustomer),
                        onClearCustomer: () => setState(() => _customer = null),
                        onSend: _send,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Modal header ─────────────────────────────────────────────────────────────

class _ModalHeader extends StatelessWidget {
  final bool isDark;
  final _ModalStep step;
  final Customer? customer;
  final Color textColor;
  final Color mutedColor;
  final VoidCallback? onBack;
  final VoidCallback onClose;

  const _ModalHeader({
    required this.isDark,
    required this.step,
    required this.customer,
    required this.textColor,
    required this.mutedColor,
    required this.onBack,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final headerBg = isDark
        ? AppColors.darkBackground.withValues(alpha: 0.5)
        : const Color(0xFFF4F6F8);

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 8, 14),
      decoration: BoxDecoration(
        color: headerBg,
        border: Border(
          bottom: BorderSide(
            color: isDark ? AppColors.darkBorder : const Color(0xFFE4E7EC),
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.add_link_rounded,
              color: AppColors.primaryBlue,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step == _ModalStep.pickCustomer
                      ? 'Choisir un client'
                      : 'Nouveau lien de paiement',
                  style: AppTextStyles.h3(
                    color: textColor,
                  ).copyWith(fontWeight: FontWeight.w800, fontSize: 17),
                ),
                Text(
                  step == _ModalStep.pickCustomer
                      ? 'Facultatif — le lien peut partir sans fiche client'
                      : 'Envoyez-le à n\'importe qui',
                  style: AppTextStyles.caption(color: mutedColor),
                ),
              ],
            ),
          ),
          if (onBack != null)
            IconButton(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded),
              color: mutedColor,
              tooltip: 'Retour',
            )
          else
            AppCloseButton(onPressed: onClose),
        ],
      ),
    );
  }
}

// ─── Customer picker step ─────────────────────────────────────────────────────

class _CustomerPicker extends ConsumerStatefulWidget {
  final bool isDark;
  final StateNotifierProvider<CustomerNotifier, CustomerState> customerProvider;
  final TextEditingController searchCtrl;
  final void Function(Customer) onSelect;
  final VoidCallback onCreateTap;
  final Color textColor;
  final Color mutedColor;

  const _CustomerPicker({
    super.key,
    required this.isDark,
    required this.customerProvider,
    required this.searchCtrl,
    required this.onSelect,
    required this.onCreateTap,
    required this.textColor,
    required this.mutedColor,
  });

  @override
  ConsumerState<_CustomerPicker> createState() => _CustomerPickerState();
}

class _CustomerPickerState extends ConsumerState<_CustomerPicker> {
  /// Strips every non-digit character — used for flexible phone matching.
  static String _digitsOnly(String s) => s.replaceAll(RegExp(r'\D'), '');

  @override
  Widget build(BuildContext context) {
    final customerState = ref.watch(widget.customerProvider);
    final q = widget.searchCtrl.text.trim().toLowerCase();
    final qDigits = _digitsOnly(q);

    // Don't render the list at all until the user starts typing.
    final hasQuery = q.isNotEmpty;

    final filtered =
        !hasQuery
              ? <Customer>[]
              : customerState.customers.where((c) {
                  if (!c.isActive) return false;
                  // Name match (display name + raw name field).
                  final nameBlob = '${c.displayFirstLastName} ${c.name}'
                      .toLowerCase();
                  if (nameBlob.contains(q)) return true;
                  // Phone match — strip all non-digits from both sides so that
                  // spaces, dashes, parentheses, and country-code prefix are ignored.
                  if (qDigits.isNotEmpty) {
                    final phoneDigits = _digitsOnly(c.phone);
                    final altDigits = _digitsOnly(c.secondaryPhone ?? '');
                    if (phoneDigits.contains(qDigits)) return true;
                    if (altDigits.isNotEmpty && altDigits.contains(qDigits)) {
                      return true;
                    }
                  }
                  return false;
                }).toList()
          ..sort(
            (a, b) => a.displayFirstLastName.toLowerCase().compareTo(
              b.displayFirstLastName.toLowerCase(),
            ),
          );

    final isDark = widget.isDark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: TextField(
            controller: widget.searchCtrl,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Rechercher un client ou un téléphone…',
              prefixIcon: const Icon(Icons.search_rounded, size: 22),
              filled: true,
              fillColor: isDark ? AppColors.darkSurface : AppColors.white,
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
                  color: AppColors.primaryBlue,
                  width: 1.5,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              isDense: true,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: widget.onCreateTap,
              icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
              label: const Text('Créer un client'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primaryBlue,
                side: BorderSide(
                  color: AppColors.primaryBlue.withValues(alpha: 0.45),
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
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: !hasQuery
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.search_rounded,
                          size: 28,
                          color: widget.mutedColor.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Saisissez un nom ou un téléphone pour trouver un client.',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.caption(
                            color: widget.mutedColor,
                          ).copyWith(height: 1.5),
                        ),
                      ],
                    ),
                  ),
                )
              : filtered.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      'Aucun résultat. Essayez un autre nom ou numéro, ou créez un client.',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.caption(
                        color: widget.mutedColor,
                      ).copyWith(height: 1.4),
                    ),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    color: widget.mutedColor.withValues(alpha: 0.12),
                  ),
                  itemBuilder: (_, i) {
                    final c = filtered[i];
                    final initials = _initials(c.displayFirstLastName);
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => widget.onSelect(c),
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 20,
                                backgroundColor: AppColors.primaryBlue
                                    .withValues(alpha: 0.12),
                                child: Text(
                                  initials,
                                  style: AppTextStyles.caption(
                                    color: AppColors.primaryBlue,
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
                                        color: widget.textColor,
                                      ).copyWith(fontWeight: FontWeight.w600),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      c.phone.isEmpty || c.phone == '—'
                                          ? 'Aucun téléphone enregistré'
                                          : c.phone,
                                      style: AppTextStyles.caption(
                                        color: widget.mutedColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right_rounded,
                                size: 20,
                                color: AppColors.primaryBlue,
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

  static String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    if (name.length >= 2) return name.substring(0, 2).toUpperCase();
    return name.isEmpty ? '?' : name[0].toUpperCase();
  }
}

// ─── Quick-create customer ────────────────────────────────────────────────────

const _idDocTypes = [
  'Passeport',
  'Carte d\'identité',
  'Permis de conduire',
  'NIF',
  'Autre',
];

class _QuickCreateCustomer extends ConsumerStatefulWidget {
  final bool isDark;
  final StateNotifierProvider<CustomerNotifier, CustomerState> customerProvider;
  final Color textColor;
  final Color mutedColor;
  final void Function(Customer) onCreated;

  const _QuickCreateCustomer({
    super.key,
    required this.isDark,
    required this.customerProvider,
    required this.textColor,
    required this.mutedColor,
    required this.onCreated,
  });

  @override
  ConsumerState<_QuickCreateCustomer> createState() =>
      _QuickCreateCustomerState();
}

class _QuickCreateCustomerState extends ConsumerState<_QuickCreateCustomer> {
  final _firstCtrl = TextEditingController();
  final _lastCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _idCtrl = TextEditingController();
  String _idType = _idDocTypes.first;
  DateTime? _dob;
  String? _error;

  @override
  void dispose() {
    _firstCtrl.dispose();
    _lastCtrl.dispose();
    _phoneCtrl.dispose();
    _idCtrl.dispose();
    super.dispose();
  }

  void _save() {
    setState(() => _error = null);
    final fn = _firstCtrl.text.trim();
    final ln = _lastCtrl.text.trim();
    if (fn.isEmpty || ln.isEmpty) {
      setState(() => _error = 'Le prénom et le nom sont obligatoires.');
      return;
    }
    final govRaw = _idCtrl.text.trim();
    final gov = govRaw.isEmpty ? null : '$_idType · $govRaw';
    if (gov == null && _dob == null) {
      setState(
        () => _error =
            'Ajoutez une pièce d\'identité ou la date de naissance pour identifier ce client.',
      );
      return;
    }
    final phone = _phoneCtrl.text.trim();
    final id = 'cust_${DateTime.now().millisecondsSinceEpoch}';
    final c = Customer(
      id: id,
      name: '$fn $ln'.trim(),
      firstName: fn,
      lastName: ln,
      phone: phone.isEmpty ? '—' : phone,
      governmentId: gov,
      dateOfBirth: _dob,
      createdAt: DateTime.now(),
    );
    ref.read(widget.customerProvider.notifier).addCustomer(c);
    widget.onCreated(c);
  }

  InputDecoration _dec(String label, IconData icon) => InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon, size: 20),
    filled: true,
    fillColor: widget.isDark ? AppColors.darkSurface : AppColors.white,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(
        color: widget.isDark ? AppColors.darkBorder : const Color(0xFFD0D5DD),
      ),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(
        color: widget.isDark ? AppColors.darkBorder : const Color(0xFFD0D5DD),
      ),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: AppColors.primaryBlue, width: 1.5),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    isDense: true,
  );

  @override
  Widget build(BuildContext context) {
    final dobLabel = _dob == null
        ? 'Date de naissance (si pas de pièce)'
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
            'Le nouveau client sera ajouté à votre liste.',
            style: AppTextStyles.caption(
              color: widget.mutedColor,
            ).copyWith(height: 1.4),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _firstCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: _dec('Prénom *', Icons.badge_outlined),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _lastCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: _dec('Nom *', Icons.badge_outlined),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            decoration: _dec('Téléphone (facultatif)', Icons.phone_outlined),
          ),
          const SizedBox(height: 14),
          Text(
            'Identification',
            style: AppTextStyles.caption(
              color: widget.textColor,
            ).copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _idType,
            decoration: _dec(
              'Type de pièce (facultatif)',
              Icons.credit_card_outlined,
            ),
            items: _idDocTypes
                .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                .toList(),
            onChanged: (v) {
              if (v != null) setState(() => _idType = v);
            },
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _idCtrl,
            decoration: _dec(
              'Numéro de pièce (facultatif)',
              Icons.credit_card_outlined,
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate:
                    _dob ?? DateTime(now.year - 25, now.month, now.day),
                firstDate: DateTime(1900),
                lastDate: now,
              );
              if (picked != null) setState(() => _dob = picked);
            },
            icon: const Icon(Icons.cake_outlined, size: 18),
            label: Text(dobLabel),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
              foregroundColor: widget.textColor,
              side: BorderSide(
                color: widget.isDark
                    ? AppColors.darkBorder
                    : const Color(0xFFD0D5DD),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: AppTextStyles.caption(
                color: AppColors.boldRed,
              ).copyWith(fontWeight: FontWeight.w600),
            ),
          ],
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _save,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
              foregroundColor: AppColors.white,
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Enregistrer et continuer',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Paylink form step ────────────────────────────────────────────────────────

class _PayLinkForm extends StatelessWidget {
  final bool isDark;
  final Customer? customer;
  final TextEditingController nameCtrl;
  final TextEditingController amountCtrl;
  final TextEditingController noteCtrl;
  final TextEditingController contactCtrl;
  final PayLinkChannel channel;
  final DateTime? expiresAt;
  final bool canSend;
  final bool sending;
  final CardChargePricing? pricing;
  final String? error;
  final Color textColor;
  final Color mutedColor;
  final void Function(PayLinkChannel) onChannelChanged;
  final void Function(DateTime?) onExpiryChanged;
  final VoidCallback onAmountChanged;
  final VoidCallback onContactChanged;
  final VoidCallback onPickCustomer;
  final VoidCallback onClearCustomer;
  final VoidCallback onSend;

  const _PayLinkForm({
    super.key,
    required this.isDark,
    required this.customer,
    required this.nameCtrl,
    required this.amountCtrl,
    required this.noteCtrl,
    required this.contactCtrl,
    required this.channel,
    required this.expiresAt,
    required this.canSend,
    required this.sending,
    required this.pricing,
    required this.error,
    required this.textColor,
    required this.mutedColor,
    required this.onChannelChanged,
    required this.onExpiryChanged,
    required this.onAmountChanged,
    required this.onContactChanged,
    required this.onPickCustomer,
    required this.onClearCustomer,
    required this.onSend,
  });

  InputDecoration _dec(String label, IconData icon) => InputDecoration(
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
      borderSide: const BorderSide(color: AppColors.primaryBlue, width: 1.5),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    isDense: true,
  );

  @override
  Widget build(BuildContext context) {
    final parsedAmt = double.tryParse(
      amountCtrl.text.replaceAll(',', '').trim(),
    );

    final expiryLabel = expiresAt == null
        ? 'Date d\'expiration (facultatif)'
        : 'Expire le ${expiresAt!.day}/${expiresAt!.month}/${expiresAt!.year}';

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
          _SectionLabel(label: 'PAYEUR', mutedColor: mutedColor),
          const SizedBox(height: 6),
          TextField(
            controller: nameCtrl,
            onChanged: (_) => onContactChanged(),
            textCapitalization: TextCapitalization.words,
            decoration: _dec('Nom du payeur *', Icons.person_outline),
          ),
          const SizedBox(height: 8),
          if (customer == null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onPickCustomer,
                icon: const Icon(Icons.person_search_rounded, size: 18),
                label: const Text('Associer un client (facultatif)'),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.primaryBlue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.primaryBlue.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.person_rounded,
                    size: 16,
                    color: AppColors.primaryBlue,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      customer!.displayFirstLastName,
                      style: AppTextStyles.body(
                        color: AppColors.primaryBlue,
                      ).copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    onPressed: onClearCustomer,
                    icon: const Icon(Icons.close_rounded, size: 18),
                    tooltip: 'Retirer le client',
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),

          const SizedBox(height: 8),

          // ─ Prepaid amount
          _SectionLabel(label: 'MONTANT PRÉPAYÉ', mutedColor: mutedColor),
          const SizedBox(height: 6),
          TextField(
            controller: amountCtrl,
            onChanged: (_) => onAmountChanged(),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
            ],
            decoration: _dec('Montant (HTG) *', Icons.payments_outlined),
          ),
          if (pricing != null) ...[
            const SizedBox(height: 10),
            CardFeeBreakdown(
              pricing: pricing!,
              isDark: isDark,
              orderLocalLabel: parsedAmt == null
                  ? null
                  : CurrencyFormatter.local(context, parsedAmt),
            ),
          ],

          const SizedBox(height: 16),

          // ─ Payer contact (not the client record; who receives the link)
          _SectionLabel(label: 'ENVOYER À (PAYEUR)', mutedColor: mutedColor),
          const SizedBox(height: 6),
          TextField(
            controller: contactCtrl,
            onChanged: (_) => onContactChanged(),
            keyboardType: channel == PayLinkChannel.email
                ? TextInputType.emailAddress
                : TextInputType.phone,
            autofillHints: null,
            enableSuggestions: false,
            autocorrect: false,
            decoration: _dec(
              channel == PayLinkChannel.email
                  ? 'E-mail du payeur *'
                  : 'Téléphone du payeur *',
              channel == PayLinkChannel.email
                  ? Icons.email_outlined
                  : Icons.phone_outlined,
            ),
          ),

          const SizedBox(height: 12),

          // ─ Channel selector
          _SectionLabel(label: 'ENVOYER PAR', mutedColor: mutedColor),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _ChannelChip(
                  icon: Icons.chat_rounded,
                  label: 'WhatsApp',
                  color: const Color(0xFF25D366),
                  selected: channel == PayLinkChannel.whatsApp,
                  isDark: isDark,
                  onTap: () => onChannelChanged(PayLinkChannel.whatsApp),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _ChannelChip(
                  icon: Icons.email_outlined,
                  label: 'E-mail',
                  color: AppColors.primaryBlue,
                  selected: channel == PayLinkChannel.email,
                  isDark: isDark,
                  onTap: () => onChannelChanged(PayLinkChannel.email),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _ChannelChip(
                  icon: Icons.sms_outlined,
                  label: 'SMS',
                  color: AppColors.amber,
                  selected: channel == PayLinkChannel.sms,
                  isDark: isDark,
                  onTap: () => onChannelChanged(PayLinkChannel.sms),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.darkBackground
                  : const Color(0xFFF0F4F8),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isDark
                    ? AppColors.darkBorder
                    : AppColors.primaryBlue.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: isDark ? AppColors.skyBlue : AppColors.primaryBlue,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Le lien et l\'enregistrement ne sont créés que lorsque vous touchez Envoyer le lien. '
                    'L\'écran de copie et de partage s\'ouvrira juste après.',
                    style: AppTextStyles.caption(
                      color: isDark ? AppColors.coolGray : AppColors.darkGray,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ─ Optional: expiry + note
          OutlinedButton.icon(
            onPressed: () async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: expiresAt ?? now.add(const Duration(days: 30)),
                firstDate: now,
                lastDate: now.add(const Duration(days: 365)),
              );
              onExpiryChanged(picked);
            },
            icon: const Icon(Icons.event_outlined, size: 18),
            label: Text(expiryLabel),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 44),
              foregroundColor: expiresAt != null
                  ? AppColors.primaryBlue
                  : mutedColor,
              side: BorderSide(
                color: expiresAt != null
                    ? AppColors.primaryBlue.withValues(alpha: 0.45)
                    : (isDark ? AppColors.darkBorder : const Color(0xFFD0D5DD)),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: noteCtrl,
            maxLines: 2,
            decoration: _dec(
              'Note (facultatif — visible par le personnel)',
              Icons.sticky_note_2_outlined,
            ),
          ),

          if (error != null && error!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(error!, style: AppTextStyles.body(color: AppColors.boldRed)),
          ],

          const SizedBox(height: 20),

          // ─ Send button
          FilledButton.icon(
            onPressed: canSend ? onSend : null,
            icon: Icon(
              sending ? Icons.hourglass_top_rounded : Icons.send_rounded,
              size: 18,
            ),
            label: Text(
              sending ? 'Création du lien…' : 'Envoyer le lien',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
              foregroundColor: AppColors.white,
              disabledBackgroundColor: isDark
                  ? AppColors.darkBorder
                  : const Color(0xFFEEEEEE),
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  final Color mutedColor;

  const _SectionLabel({required this.label, required this.mutedColor});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: AppTextStyles.caption(
        color: mutedColor,
      ).copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.8, fontSize: 10),
    );
  }
}

class _ChannelChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;

  const _ChannelChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppConstants.animFast,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: isDark ? 0.18 : 0.1)
              : (isDark ? AppColors.darkBackground : const Color(0xFFF7F7F7)),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? color
                : (isDark ? AppColors.darkBorder : const Color(0xFFE0E0E0)),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: selected
                  ? color
                  : (isDark ? AppColors.coolGray : AppColors.darkGray),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: AppTextStyles.caption(
                color: selected
                    ? color
                    : (isDark ? AppColors.coolGray : AppColors.darkGray),
              ).copyWith(fontWeight: FontWeight.w600, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}
