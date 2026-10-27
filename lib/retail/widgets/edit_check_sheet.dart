import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/mock/mock_retail_orders.dart';
import '../../core/models/check_credit.dart';
import '../../core/models/customer.dart';
import '../../core/models/retail_check_payment.dart';
import '../../core/models/retail_order.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/constants.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/date_formatter.dart';
import '../../core/utils/input_formatters.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_close_button.dart';
import '../../core/widgets/app_input.dart';
import '../../core/widgets/check_photo_viewer.dart';
import '../../core/widgets/phone_field.dart';
import 'check_photo_pick.dart';
import 'product_photo_pick.dart';

/// Right-hand editor for a check that was already recorded.
Future<void> showEditCheckPanel(
  BuildContext context, {
  required String orderId,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Modifier le chèque',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 220),
    transitionBuilder: (ctx, anim, _, child) => SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(1, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
      child: child,
    ),
    pageBuilder: (ctx, _, _) {
      final width = MediaQuery.sizeOf(ctx).width;
      final panelWidth = AppConstants.sidePanelWidth(width, 480);
      final bg = isDark ? AppColors.darkSurface : AppColors.white;
      return Align(
        alignment: Alignment.centerRight,
        child: Material(
          color: bg,
          elevation: 12,
          child: SizedBox(
            key: const Key('edit-check-panel'),
            width: panelWidth,
            height: double.infinity,
            child: SafeArea(child: _EditCheckPanel(orderId: orderId)),
          ),
        ),
      );
    },
  );
}

class _EditCheckPanel extends ConsumerStatefulWidget {
  final String orderId;

  const _EditCheckPanel({required this.orderId});

  @override
  ConsumerState<_EditCheckPanel> createState() => _EditCheckPanelState();
}

class _EditCheckPanelState extends ConsumerState<_EditCheckPanel> {
  final _amountCtrl = TextEditingController();
  final _numberCtrl = TextEditingController();
  final _bankCtrl = TextEditingController();
  final _payerCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  final _newNameCtrl = TextEditingController();
  final _newPhoneCtrl = TextEditingController();
  DateTime _date = DateTime.now();
  Uint8List? _newPhoto;
  String _mime = 'image/jpeg';
  String? _photoError;
  String? _error;
  String? _customerId;
  bool _busy = false;
  bool _showNew = false;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    final order = _order();
    final check = order?.checkPayment;
    if (order != null && check != null) {
      final total = checkSaleTotal(order);
      final face = check.amountHtg ?? order.amountPaidHtg ?? total;
      _amountCtrl.text = _amountField(face);
      _numberCtrl.text = check.number;
      _bankCtrl.text = check.bank;
      _payerCtrl.text = check.payerName;
      _date = check.date;
      _customerId = check.creditCustomerId;
    }
    _ready = true;
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _numberCtrl.dispose();
    _bankCtrl.dispose();
    _payerCtrl.dispose();
    _searchCtrl.dispose();
    _newNameCtrl.dispose();
    _newPhoneCtrl.dispose();
    super.dispose();
  }

  RetailOrder? _order() {
    for (final order in ref.read(retailOrdersProvider)) {
      if (order.id == widget.orderId) return order;
    }
    return null;
  }

  double get _face => double.tryParse(_amountCtrl.text.trim()) ?? 0;

  double _remainder(RetailOrder order) {
    final due = checkSaleTotal(order) - _face;
    return due > 0.009 ? due : 0;
  }

  bool _tooHigh(RetailOrder order) => _face - checkSaleTotal(order) > 0.009;

  String _amountField(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(2);
  }

  Customer? _customer() {
    final id = _customerId;
    if (id == null || id.isEmpty) return null;
    for (final customer in ref.read(customerProvider).customers) {
      if (customer.id == id) return customer;
    }
    return null;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickPhoto() async {
    setState(() {
      _busy = true;
      _photoError = null;
    });
    PickedProductPhoto? picked;
    var failed = false;
    try {
      picked = await checkPhotoPicker();
    } catch (_) {
      failed = true;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (failed) {
        _photoError = 'La photo n\'a pas pu être ajoutée. Réessayez.';
        return;
      }
      if (picked == null) return;
      if (picked.error != null && picked.error!.isNotEmpty) {
        _photoError = picked.error;
        return;
      }
      final bytes = picked.bytes;
      if (bytes == null || bytes.isEmpty) {
        _photoError = 'La photo du chèque est illisible.';
        return;
      }
      _newPhoto = bytes;
      _mime = picked.mime;
    });
  }

  void _useOrderClient(RetailOrder order) {
    final name = order.clientName?.trim() ?? '';
    final phone = order.clientPhone?.trim() ?? '';
    if (name.isEmpty) return;
    final customers = ref.read(customerProvider).customers;
    final match = _customerByPhone(customers, phone);
    if (match != null) {
      setState(() {
        _customerId = match.id;
        _searchCtrl.clear();
        _showNew = false;
        _error = null;
      });
      return;
    }
    final created = Customer(
      id: 'cust_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      phone: phone.isEmpty ? '—' : phone,
      createdAt: DateTime.now(),
    );
    ref.read(customerProvider.notifier).addCustomer(created);
    setState(() {
      _customerId = created.id;
      _showNew = false;
      _error = null;
    });
  }

  void _createCustomer() {
    final name = _newNameCtrl.text.trim();
    final phone = _newPhoneCtrl.text.trim();
    if (name.isEmpty || phone.isEmpty) {
      setState(() => _error = 'Le nom et le téléphone sont requis.');
      return;
    }
    final created = Customer(
      id: 'cust_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      phone: phone,
      createdAt: DateTime.now(),
    );
    ref.read(customerProvider.notifier).addCustomer(created);
    _newNameCtrl.clear();
    _newPhoneCtrl.clear();
    setState(() {
      _customerId = created.id;
      _showNew = false;
      _error = null;
    });
  }

  Future<void> _save(RetailOrder order) async {
    final remainder = _remainder(order);
    if (_tooHigh(order)) {
      setState(() => _error = 'Le chèque ne peut pas dépasser le total.');
      return;
    }
    if (remainder > 0.009 && (_customerId == null || _customerId!.isEmpty)) {
      setState(() => _error = 'Choisissez le client qui portera le solde.');
      return;
    }
    final photo = _newPhoto == null
        ? null
        : RetailCheckPayment.dataUrlFor(_newPhoto!, _mime);
    final error = ref
        .read(retailOrdersProvider.notifier)
        .updateCheck(
          orderId: order.id,
          amountHtg: _face,
          number: _numberCtrl.text,
          bank: _bankCtrl.text,
          payerName: _payerCtrl.text,
          date: _date,
          imageDataUrl: photo,
          creditCustomerId: _customerId,
        );
    if (!mounted) return;
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? AppColors.warmWhite : AppColors.nearBlack;
    final muted = isDark ? AppColors.coolGray : AppColors.darkGray;
    ref.watch(retailOrdersProvider);
    ref.watch(customerProvider);
    if (!_ready) return const SizedBox.shrink();
    final order = _order();
    final check = order?.checkPayment;
    if (order == null || check == null) {
      return const Center(child: Text('Ce chèque est introuvable.'));
    }
    final remainder = _remainder(order);
    final tooLow = _amountCtrl.text.trim().isEmpty || _face < 1;
    final tooHigh = _tooHigh(order);
    final customer = _customer();
    final saleTotal = checkSaleTotal(order);
    final canSave =
        !check.refused &&
        !_busy &&
        !tooLow &&
        !tooHigh &&
        _face >= 1 &&
        _numberCtrl.text.trim().isNotEmpty &&
        _bankCtrl.text.trim().isNotEmpty &&
        _payerCtrl.text.trim().isNotEmpty &&
        (remainder <= 0.009 || customer != null);
    final photo = _newPhoto ?? check.imageBytes;
    final query = _searchCtrl.text.trim().toLowerCase();
    final results = query.isEmpty
        ? <Customer>[]
        : ref
              .read(customerProvider)
              .customers
              .where(
                (item) =>
                    item.isActive &&
                    (item.name.toLowerCase().contains(query) ||
                        item.phone.contains(_searchCtrl.text.trim())),
              )
              .take(8)
              .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
          child: Row(
            children: [
              Expanded(
                child: Text('Modifier le chèque', style: AppTextStyles.h3()),
              ),
              AppCloseButton(onPressed: () => Navigator.of(context).pop()),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Total confirmé : ${CurrencyFormatter.local(context, saleTotal)}',
                style: AppTextStyles.body(color: ink),
              ),
              if (check.cleared) ...[
                const SizedBox(height: 8),
                Text(
                  'Ce chèque est déjà compensé. Changer le montant ajuste le crédit du client.',
                  style: AppTextStyles.caption(color: muted),
                ),
              ],
              const SizedBox(height: 12),
              AppInput(
                key: const Key('edit-check-amount'),
                label: 'Montant du chèque',
                controller: _amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: InputFormatters.decimalAmount,
                onChanged: (_) => setState(() => _error = null),
              ),
              if (tooLow) ...[
                const SizedBox(height: 8),
                Text(
                  'Le montant du chèque doit être d\'au moins 1 HTG.',
                  style: AppTextStyles.body(
                    color: AppColors.boldRed,
                  ).copyWith(fontWeight: FontWeight.w700),
                ),
              ] else if (tooHigh) ...[
                const SizedBox(height: 8),
                Text(
                  'Le chèque ne peut pas dépasser le total.',
                  style: AppTextStyles.body(
                    color: AppColors.boldRed,
                  ).copyWith(fontWeight: FontWeight.w700),
                ),
              ] else if (remainder > 0.009) ...[
                const SizedBox(height: 8),
                Text(
                  check.cleared
                      ? 'Solde restant : ${CurrencyFormatter.local(context, remainder)}. Il sera ajusté sur le compte du client.'
                      : 'Solde restant : ${CurrencyFormatter.local(context, remainder)}. Il restera en attente de crédit jusqu\'à compensation du chèque.',
                  key: const Key('edit-check-balance'),
                  style: AppTextStyles.body(
                    color: AppColors.amber,
                  ).copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                _clientSection(
                  order: order,
                  customer: customer,
                  results: results,
                  ink: ink,
                ),
              ],
              const SizedBox(height: 12),
              AppInput(
                key: const Key('edit-check-number'),
                label: 'Numéro du chèque',
                controller: _numberCtrl,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              AppInput(
                key: const Key('edit-check-bank'),
                label: 'Banque',
                controller: _bankCtrl,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              AppInput(
                key: const Key('edit-check-payer'),
                label: 'Nom du tireur',
                controller: _payerCtrl,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              Text(
                'Date du chèque',
                style: AppTextStyles.inputLabel(color: muted),
              ),
              const SizedBox(height: 4),
              InkWell(
                key: const Key('edit-check-date'),
                onTap: _pickDate,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    DateFormatter.shortDate(_date),
                    style: AppTextStyles.body(color: ink),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (photo != null)
                CheckPhotoThumb(
                  bytes: photo,
                  height: 120,
                  isDark: isDark,
                  photoKey: const Key('edit-check-photo-preview'),
                ),
              const SizedBox(height: 8),
              AppButton(
                key: const Key('edit-check-photo'),
                label: photo == null
                    ? 'Ajouter la photo'
                    : 'Remplacer la photo',
                icon: Icons.add_a_photo_outlined,
                variant: AppButtonVariant.secondary,
                compact: true,
                isLoading: _busy,
                onPressed: _busy ? null : _pickPhoto,
              ),
              if (_photoError != null) ...[
                const SizedBox(height: 8),
                Text(
                  _photoError!,
                  style: AppTextStyles.caption(color: AppColors.boldRed),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  key: const Key('edit-check-error'),
                  style: AppTextStyles.body(
                    color: AppColors.boldRed,
                  ).copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: AppButton(
            key: const Key('edit-check-save'),
            label: 'Enregistrer',
            compact: true,
            onPressed: canSave ? () => _save(order) : null,
          ),
        ),
      ],
    );
  }

  Widget _clientSection({
    required RetailOrder order,
    required Customer? customer,
    required List<Customer> results,
    required Color ink,
  }) {
    if (customer != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            customer.name,
            key: const Key('edit-check-client'),
            style: AppTextStyles.body(
              color: ink,
            ).copyWith(fontWeight: FontWeight.w700),
          ),
          if (customer.phone.trim().isNotEmpty)
            Text(customer.phone, style: AppTextStyles.caption()),
          TextButton(
            onPressed: () => setState(() => _customerId = null),
            child: const Text('Changer le client'),
          ),
        ],
      );
    }
    final orderName = order.clientName?.trim() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (orderName.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const Key('edit-check-use-client'),
              onPressed: () => _useOrderClient(order),
              child: Text('Utiliser $orderName'),
            ),
          ),
        TextField(
          key: const Key('edit-check-client-search'),
          controller: _searchCtrl,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Rechercher un client',
            prefixIcon: Icon(Icons.search, size: 20),
          ),
        ),
        for (final item in results)
          ListTile(
            dense: true,
            title: Text(item.name),
            subtitle: Text(item.phone),
            onTap: item.isCreditBlocked
                ? null
                : () => setState(() {
                    _customerId = item.id;
                    _searchCtrl.clear();
                    _error = null;
                  }),
          ),
        TextButton.icon(
          key: const Key('edit-check-new-client'),
          onPressed: () => setState(() => _showNew = !_showNew),
          icon: const Icon(Icons.person_add_outlined, size: 16),
          label: Text(_showNew ? 'Annuler' : 'Nouveau client'),
        ),
        if (_showNew) ...[
          AppInput(
            key: const Key('edit-check-client-name'),
            label: 'Nom complet *',
            controller: _newNameCtrl,
          ),
          const SizedBox(height: 8),
          PhoneField(
            key: const Key('edit-check-client-phone'),
            controller: _newPhoneCtrl,
            label: 'Téléphone *',
          ),
          const SizedBox(height: 8),
          AppButton(
            key: const Key('edit-check-client-create'),
            label: 'Créer et choisir',
            compact: true,
            onPressed: _createCustomer,
          ),
        ],
      ],
    );
  }
}

Customer? _customerByPhone(List<Customer> customers, String phone) {
  final digits = phone.replaceAll(RegExp(r'\D'), '');
  if (digits.length < 8) return null;
  for (final customer in customers) {
    final other = customer.phone.replaceAll(RegExp(r'\D'), '');
    if (other.length < 8) continue;
    if (other.endsWith(digits) || digits.endsWith(other)) return customer;
  }
  return null;
}
