import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../mock/mock_hotel_data.dart';
import '../mock/mock_restaurant_data.dart';
import '../providers/new_order_draft_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/constants.dart';
import 'phone_field.dart';

/// Collects order-type-specific info before opening the menu screen.
/// Returns [NewOrderDraft] on Next, or `null` if cancelled.
Future<NewOrderDraft?> showNewOrderSetupDialog({
  required BuildContext context,
  required WidgetRef ref,
  required bool isHotel,
  required String initialType,
}) {
  return showDialog<NewOrderDraft>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _NewOrderSetupDialog(
      isHotel: isHotel,
      initialType: initialType,
    ),
  );
}

class _NewOrderSetupDialog extends ConsumerStatefulWidget {
  final bool isHotel;
  final String initialType;

  const _NewOrderSetupDialog({
    required this.isHotel,
    required this.initialType,
  });

  @override
  ConsumerState<_NewOrderSetupDialog> createState() =>
      _NewOrderSetupDialogState();
}

class _NewOrderSetupDialogState extends ConsumerState<_NewOrderSetupDialog> {
  late String _type;
  String? _tableName;
  int? _tableId;
  int? _roomId;
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();

  String? _phoneError;
  String? _addressError;
  String? _tableError;
  String? _roomError;

  @override
  void initState() {
    super.initState();
    _type = widget.initialType;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  bool get _needsTable => _type == 'dine_in';
  bool get _needsRoom => widget.isHotel && _type == 'room_service';
  bool get _needsDeliveryFields => _type == 'delivery';
  bool get _showCustomerOptional =>
      _type == 'takeout' || _type == 'delivery' || _type == 'room_service';

  void _submit() {
    setState(() {
      _phoneError = null;
      _addressError = null;
      _tableError = null;
      _roomError = null;
    });

    if (_needsTable) {
      if (_tableName == null || _tableName!.isEmpty) {
        setState(() => _tableError = 'Choisir une table');
        return;
      }
    }
    if (_needsRoom) {
      if (_roomId == null) {
        setState(() => _roomError = 'Choisir une chambre');
        return;
      }
    }
    if (_needsDeliveryFields) {
      if (_phoneCtrl.text.trim().isEmpty) {
        setState(() => _phoneError = 'Le téléphone est obligatoire pour la livraison');
        return;
      }
      if (_addressCtrl.text.trim().isEmpty) {
        setState(() => _addressError = 'L\'adresse de livraison est obligatoire');
        return;
      }
    }

    final roomNumber = _needsRoom
        ? ref
            .read(mockRoomsProvider)
            .where((r) => r.id == _roomId)
            .firstOrNull
            ?.number
        : null;

    final draft = NewOrderDraft(
      orderType: _type,
      tableId: _needsTable ? _tableId : null,
      tableName: _needsTable ? (_tableName ?? '') : '',
      customerName: _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
      deliveryAddress:
          _needsDeliveryFields ? _addressCtrl.text.trim() : null,
      customerPhone:
          _needsDeliveryFields ? _phoneCtrl.text.trim() : null,
      roomNumber: roomNumber,
    );

    Navigator.of(context).pop(draft);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tables = ref.watch(mockTablesProvider);
    final rooms = ref
        .watch(mockRoomsProvider)
        .where((r) =>
            r.status == 'occupied' ||
            r.status == 'checkout_today' ||
            r.status == 'available')
        .toList();
    final availableTables =
        tables.where((t) => t.status == 'available').toList();

    if (_roomId != null && !rooms.any((r) => r.id == _roomId)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _roomId = null);
      });
    }
    final roomDropdownValue =
        _roomId != null && rooms.any((r) => r.id == _roomId) ? _roomId : null;

    return AlertDialog(
      title: Text('Nouvelle commande',
          style: AppTextStyles.h2(
              color: isDark ? AppColors.warmWhite : AppColors.primaryBlue)),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Type de commande', style: AppTextStyles.caption()),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _typeChip('dine_in', 'Dine-in', isDark),
                  if (widget.isHotel)
                    _typeChip('room_service', 'Service en chambre', isDark),
                  _typeChip('takeout', 'Takeout', isDark),
                  _typeChip('delivery', 'Livraison', isDark),
                ],
              ),
              const SizedBox(height: AppConstants.spacing16),
              if (_needsTable) ...[
                Text('Table', style: AppTextStyles.caption()),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: _tableName,
                  decoration: InputDecoration(
                    errorText: _tableError,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  hint: const Text('Choisir la table'),
                  items: availableTables
                      .map(
                        (t) => DropdownMenuItem(
                          value: t.name,
                          child: Text('${t.name} (${t.capacity} places)'),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    final matches =
                        availableTables.where((x) => x.name == v);
                    final t = matches.isEmpty ? null : matches.first;
                    setState(() {
                      _tableName = v;
                      _tableId = t?.id;
                      _tableError = null;
                    });
                  },
                ),
              ],
              if (_needsRoom) ...[
                Text('Chambre', style: AppTextStyles.caption()),
                const SizedBox(height: 6),
                DropdownButtonFormField<int>(
                  value: roomDropdownValue,
                  decoration: InputDecoration(
                    errorText: _roomError,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  hint: const Text('Choisir la chambre'),
                  items: rooms
                      .map(
                        (r) => DropdownMenuItem(
                          value: r.id,
                          child: Text(
                              'Chambre ${r.number} · ${r.guestName ?? 'Guest'}'),
                        ),
                      )
                      .toList(),
                  onChanged: (v) =>
                      setState(() {
                        _roomId = v;
                        _roomError = null;
                      }),
                ),
              ],
              if (_showCustomerOptional || _needsDeliveryFields) ...[
                Text(
                  _needsDeliveryFields
                      ? 'Nom du client (facultatif)'
                      : 'Nom du client (facultatif)',
                  style: AppTextStyles.caption(),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                    hintText: 'Nom',
                  ),
                  onChanged: (_) {},
                ),
              ],
              if (_needsDeliveryFields) ...[
                const SizedBox(height: AppConstants.spacing12),
                PhoneField(
                  controller: _phoneCtrl,
                  label: 'Téléphone',
                  errorText: _phoneError,
                  onChanged: (_) => setState(() => _phoneError = null),
                ),
                const SizedBox(height: AppConstants.spacing12),
                Text('Adresse de livraison', style: AppTextStyles.caption()),
                const SizedBox(height: 6),
                TextField(
                  controller: _addressCtrl,
                  maxLines: 2,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    isDense: true,
                    hintText: 'Adresse complète',
                    errorText: _addressError,
                  ),
                  onChanged: (_) => setState(() => _addressError = null),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Suivant'),
        ),
      ],
    );
  }

  Widget _typeChip(String value, String label, bool isDark) {
    final sel = _type == value;
    final primary = isDark ? AppColors.skyBlue : AppColors.primaryBlue;
    return ChoiceChip(
      label: Text(label),
      selected: sel,
      onSelected: (_) => setState(() {
        _type = value;
        _tableError = null;
        _roomError = null;
        if (value != 'dine_in') {
          _tableName = null;
          _tableId = null;
        }
        if (value != 'room_service') {
          _roomId = null;
        }
      }),
      selectedColor: primary.withValues(alpha: 0.3),
    );
  }
}
