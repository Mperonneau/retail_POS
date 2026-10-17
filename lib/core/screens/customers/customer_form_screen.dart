import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/customer.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../utils/constants.dart';
import '../../utils/input_formatters.dart';
import '../../widgets/app_button.dart';
import '../../widgets/form_field_error.dart';

class CustomerFormSheet extends ConsumerStatefulWidget {
  final bool isDark;
  final Customer? existing;

  const CustomerFormSheet({super.key, required this.isDark, this.existing});

  @override
  ConsumerState<CustomerFormSheet> createState() => _CustomerFormSheetState();
}

class _CustomerFormSheetState extends ConsumerState<CustomerFormSheet> {
  late final TextEditingController _firstNameCtrl;
  late final TextEditingController _lastNameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _phone2Ctrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _notesCtrl;
  late final TextEditingController _limitHtgCtrl;
  late final TextEditingController _govIdCtrl;

  DateTime? _dateOfBirth;

  String? _errorFirstName;
  String? _errorLastName;
  String? _errorPhone;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _firstNameCtrl = TextEditingController();
    _lastNameCtrl = TextEditingController();
    _initFromExisting(e);
    _phoneCtrl = TextEditingController(text: e?.phone ?? '');
    _phone2Ctrl = TextEditingController(text: e?.secondaryPhone ?? '');
    _addressCtrl = TextEditingController(text: e?.address ?? '');
    _notesCtrl = TextEditingController(text: e?.notes ?? '');
    _limitHtgCtrl = TextEditingController(
        text: e?.creditLimitHtg?.toStringAsFixed(0) ?? '');
    _govIdCtrl = TextEditingController(text: e?.governmentId ?? '');
    _dateOfBirth = e?.dateOfBirth;
  }

  void _initFromExisting(Customer? e) {
    if (e == null) return;
    if ((e.firstName ?? '').isNotEmpty || (e.lastName ?? '').isNotEmpty) {
      _firstNameCtrl.text = e.firstName ?? '';
      _lastNameCtrl.text = e.lastName ?? '';
      return;
    }
    final parts = e.name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      _firstNameCtrl.text = parts.first;
      _lastNameCtrl.text = parts.sublist(1).join(' ');
    } else {
      _firstNameCtrl.text = e.name.trim();
      _lastNameCtrl.text = '';
    }
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _phoneCtrl.dispose();
    _phone2Ctrl.dispose();
    _addressCtrl.dispose();
    _notesCtrl.dispose();
    _limitHtgCtrl.dispose();
    _govIdCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final initial = _dateOfBirth ?? DateTime(now.year - 25, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked != null) setState(() => _dateOfBirth = picked);
  }

  void _save() {
    setState(() {
      _errorFirstName = null;
      _errorLastName = null;
      _errorPhone = null;
    });
    final fn = _firstNameCtrl.text.trim();
    final ln = _lastNameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    if (fn.isEmpty) {
      setState(() => _errorFirstName = 'Le prénom est obligatoire');
      return;
    }
    if (ln.isEmpty) {
      setState(() => _errorLastName = 'Le nom est obligatoire');
      return;
    }
    if (phone.isEmpty) {
      setState(() => _errorPhone = 'Le téléphone est obligatoire');
      return;
    }

    final name = '$fn $ln'.trim();
    final limitRaw = _limitHtgCtrl.text.trim();
    final creditLimitHtg =
        limitRaw.isEmpty ? null : double.tryParse(limitRaw);
    final gov = _govIdCtrl.text.trim();

    if (widget.existing != null) {
      ref.read(customerProvider.notifier).updateCustomer(
            widget.existing!.copyWith(
              name: name,
              firstName: fn,
              lastName: ln,
              phone: phone,
              secondaryPhone:
                  _phone2Ctrl.text.trim().isEmpty
                      ? null
                      : _phone2Ctrl.text.trim(),
              address: _addressCtrl.text.trim().isEmpty
                  ? null
                  : _addressCtrl.text.trim(),
              notes: _notesCtrl.text.trim().isEmpty
                  ? null
                  : _notesCtrl.text.trim(),
              creditLimitHtg: creditLimitHtg,
              dateOfBirth: _dateOfBirth,
              governmentId: gov.isEmpty ? null : gov,
            ),
          );
    } else {
      final id = 'cust_${DateTime.now().millisecondsSinceEpoch}';
      ref.read(customerProvider.notifier).addCustomer(Customer(
            id: id,
            name: name,
            firstName: fn,
            lastName: ln,
            phone: phone,
            secondaryPhone: _phone2Ctrl.text.trim().isEmpty
                ? null
                : _phone2Ctrl.text.trim(),
            address: _addressCtrl.text.trim().isEmpty
                ? null
                : _addressCtrl.text.trim(),
            notes: _notesCtrl.text.trim().isEmpty
                ? null
                : _notesCtrl.text.trim(),
            creditLimitHtg: creditLimitHtg,
            dateOfBirth: _dateOfBirth,
            governmentId: gov.isEmpty ? null : gov,
            createdAt: DateTime.now(),
          ));
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final isEdit = widget.existing != null;
    final dobLabel = _dateOfBirth == null
        ? 'Date de naissance (facultatif)'
        : '${_dateOfBirth!.year}-${_dateOfBirth!.month.toString().padLeft(2, '0')}-${_dateOfBirth!.day.toString().padLeft(2, '0')}';

    return Padding(
      padding: EdgeInsets.only(
        left: AppConstants.spacing24,
        right: AppConstants.spacing24,
        top: AppConstants.spacing24,
        bottom:
            MediaQuery.of(context).viewInsets.bottom + AppConstants.spacing24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isEdit ? 'Modifier le client' : 'Nouveau client',
              style: AppTextStyles.h2(
                  color: isDark ? AppColors.warmWhite : AppColors.nearBlack),
            ),
            const SizedBox(height: AppConstants.spacing16),
            _field(_firstNameCtrl, 'Prénom *', Icons.badge_outlined),
            FormFieldError(text: _errorFirstName),
            const SizedBox(height: AppConstants.spacing12),
            _field(_lastNameCtrl, 'Nom *', Icons.badge_outlined),
            FormFieldError(text: _errorLastName),
            const SizedBox(height: AppConstants.spacing12),
            _field(_phoneCtrl, 'Numéro de téléphone *', Icons.phone_outlined,
                type: TextInputType.phone,
                inputFormatters: InputFormatters.phone),
            FormFieldError(text: _errorPhone),
            const SizedBox(height: AppConstants.spacing12),
            _field(_govIdCtrl, 'Pièce d\'identité (facultatif)',
                Icons.credit_card_outlined),
            const SizedBox(height: AppConstants.spacing12),
            OutlinedButton.icon(
              onPressed: _pickDob,
              icon: const Icon(Icons.cake_outlined, size: 18),
              label: Text(dobLabel),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                foregroundColor:
                    isDark ? AppColors.warmWhite : AppColors.nearBlack,
              ),
            ),
            const SizedBox(height: AppConstants.spacing8),
            Text(
              'Pour le crédit magasin : une pièce d\'identité, ou la date de naissance s\'il n\'y en a pas.',
              style: AppTextStyles.caption(
                color: isDark ? AppColors.coolGray : AppColors.darkGray,
              ),
            ),
            const SizedBox(height: AppConstants.spacing12),
            _field(_phone2Ctrl, 'Téléphone secondaire (facultatif)',
                Icons.phone_outlined,
                type: TextInputType.phone,
                inputFormatters: InputFormatters.phone),
            const SizedBox(height: AppConstants.spacing12),
            _field(_addressCtrl, 'Adresse (facultatif)',
                Icons.location_on_outlined),
            const SizedBox(height: AppConstants.spacing12),
            _field(_notesCtrl, 'Notes (facultatif)', Icons.notes_outlined,
                maxLines: 2),
            const SizedBox(height: AppConstants.spacing12),
            _field(
                _limitHtgCtrl,
                'Plafond de crédit (HTG) — vide = sans limite',
                Icons.account_balance_wallet_outlined,
                type: const TextInputType.numberWithOptions(decimal: true),
                prefix: 'HTG ',
                inputFormatters: InputFormatters.decimalAmount),
            const SizedBox(height: AppConstants.spacing24),
            AppButton(
              label: isEdit ? 'Enregistrer' : 'Créer le client',
              onPressed: _save,
              icon: isEdit ? Icons.save_outlined : Icons.person_add_outlined,
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    TextInputType type = TextInputType.text,
    int maxLines = 1,
    String? prefix,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: type,
      maxLines: maxLines,
      inputFormatters: inputFormatters,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        prefixText: prefix,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppConstants.radiusInput)),
      ),
    );
  }
}
