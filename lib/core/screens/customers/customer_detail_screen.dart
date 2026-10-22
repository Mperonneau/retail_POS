import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/customer.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../utils/constants.dart';
import '../../utils/input_formatters.dart';
import '../../mock/mock_hotel_customer_data.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../utils/currency_formatter.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import 'customer_form_screen.dart';
import 'customer_payment_modal.dart';
import '../../widgets/app_close_button.dart';

// ─── Right-side Detail Panel ──────────────────────────────────────────────────

class CustomerDetailPanel extends ConsumerStatefulWidget {
  final Customer customer;
  final bool isDark;
  final bool showHotelSection;
  final VoidCallback onClose;

  const CustomerDetailPanel({
    super.key,
    required this.customer,
    required this.isDark,
    required this.onClose,
    this.showHotelSection = false,
  });

  @override
  ConsumerState<CustomerDetailPanel> createState() =>
      _CustomerDetailPanelState();
}

class _CustomerDetailPanelState extends ConsumerState<CustomerDetailPanel> {
  static const int _initialTxCount = 10;
  static const int _initialCreditCount = 8;
  int _transactionsShown = _initialTxCount;
  int _storeCreditShown = _initialCreditCount;

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(customerProvider);
    final customer = state.customers.firstWhere(
      (c) => c.id == widget.customer.id,
      orElse: () => widget.customer,
    );
    final allTransactions = state.transactionsFor(customer.id);
    final totalTxCount = state.transactionCountFor(customer.id);
    final transactions = allTransactions.take(_transactionsShown).toList();
    final hasMoreTx = _transactionsShown < totalTxCount;
    final balance = state.balanceFor(customer.id);
    final storeCreditBal = state.storeCreditBalanceFor(customer.id);
    final isDark = widget.isDark;

    final bg = isDark ? AppColors.darkSurface : AppColors.white;
    final border = isDark
        ? AppColors.primaryBlue.withValues(alpha: 0.3)
        : AppColors.lightBlue;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        border: Border(left: BorderSide(color: border, width: 1.5)),
      ),
      child: Column(
        children: [
          // ── Header ──────────────────────────────────────────────────
          _PanelHeader(
            customer: customer,
            balance: balance,
            storeCreditBalance: storeCreditBal,
            isDark: isDark,
            onClose: widget.onClose,
            onEdit: () => showAppBottomSheet(
              context: context,
              child: CustomerFormSheet(isDark: isDark, existing: customer),
            ),
          ),

          // ── Blocked banner ──────────────────────────────────────────
          if (customer.isCreditBlocked)
            _BlockedBanner(customer: customer, isDark: isDark),

          // ── Scrollable body ─────────────────────────────────────────
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppConstants.spacing16,
                AppConstants.spacing12,
                AppConstants.spacing16,
                AppConstants.spacing24,
              ),
              children: [
                // Stats row
                _StatsRow(balance: balance, customer: customer, isDark: isDark),

                const SizedBox(height: AppConstants.spacing12),
                _StoreCreditSection(
                  customer: customer,
                  storeCreditBalance: storeCreditBal,
                  history: state.storeCreditHistoryFor(customer.id),
                  shown: _storeCreditShown,
                  onShowMore: () =>
                      setState(() => _storeCreditShown += _initialCreditCount),
                  isDark: isDark,
                ),

                // Payment terms note
                if (customer.notes != null) ...[
                  const SizedBox(height: AppConstants.spacing8),
                  _NoteBanner(text: customer.notes!, isDark: isDark),
                ],

                const SizedBox(height: AppConstants.spacing12),

                // Action buttons
                _ActionButtons(
                  customer: customer,
                  balance: balance,
                  isDark: isDark,
                  onTakePayment: () =>
                      _showPaymentModal(context, customer, balance),
                  onToggleBlock: () => customer.isCreditBlocked
                      ? ref
                            .read(customerProvider.notifier)
                            .unblockCustomer(customer.id)
                      : _showBlockModal(context, customer),
                  onAdjustment: () =>
                      _showAdjustmentModal(context, customer, balance),
                  onNotes: () => _showNotesModal(context, customer),
                  onSchedules: () => _showSchedulesModal(context, customer),
                ),

                // Hotel section
                if (widget.showHotelSection) ...[
                  const SizedBox(height: AppConstants.spacing16),
                  _HotelSection(customerId: customer.id, isDark: isDark),
                ],

                const SizedBox(height: AppConstants.spacing16),
                _SectionDivider(label: 'Transactions', count: totalTxCount),
                const SizedBox(height: AppConstants.spacing8),

                // Transaction rows
                if (transactions.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppConstants.spacing12,
                    ),
                    child: Text(
                      'Aucune transaction pour le moment.',
                      style: AppTextStyles.caption(
                        color: isDark ? AppColors.coolGray : AppColors.darkGray,
                      ),
                    ),
                  )
                else ...[
                  for (final tx in transactions) ...[
                    _CompactTxRow(tx: tx, isDark: isDark),
                    Divider(
                      height: 1,
                      color: (isDark ? AppColors.coolGray : AppColors.darkGray)
                          .withValues(alpha: 0.15),
                    ),
                  ],
                  if (hasMoreTx)
                    TextButton(
                      onPressed: () =>
                          setState(() => _transactionsShown += _initialTxCount),
                      style: TextButton.styleFrom(
                        minimumSize: Size.zero,
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        'Charger plus',
                        style: AppTextStyles.caption(
                          color: isDark
                              ? AppColors.skyBlue
                              : AppColors.primaryBlue,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showPaymentModal(BuildContext context, Customer c, double balance) {
    showDialog(
      context: context,
      builder: (_) => CustomerPaymentModal(
        customer: c,
        balance: balance,
        isDark: widget.isDark,
      ),
    );
  }

  void _showBlockModal(BuildContext context, Customer c) {
    showDialog(
      context: context,
      builder: (_) => _BlockDialog(
        customer: c,
        isDark: widget.isDark,
        onConfirm: (reason) => ref
            .read(customerProvider.notifier)
            .blockCustomer(c.id, reason: reason, blockedBy: 'Gérant'),
      ),
    );
  }

  void _showAdjustmentModal(BuildContext context, Customer c, double balance) {
    showDialog(
      context: context,
      builder: (_) => _AdjustmentDialog(
        customer: c,
        balance: balance,
        isDark: widget.isDark,
        onConfirm: (amount, description) => ref
            .read(customerProvider.notifier)
            .postAdjustment(
              customerId: c.id,
              amountHtg: amount,
              cashierName: 'Gérant',
              description: description,
            ),
      ),
    );
  }

  void _showNotesModal(BuildContext context, Customer c) {
    showDialog(
      context: context,
      builder: (_) => _NotesDialog(customer: c, isDark: widget.isDark),
    );
  }

  void _showSchedulesModal(BuildContext context, Customer c) {
    showDialog(
      context: context,
      builder: (_) => _SchedulesDialog(customer: c, isDark: widget.isDark),
    );
  }
}

// ── Modal dialogs ─────────────────────────────────────────────────────────────

/// Reusable styled dialog wrapper used by all customer action modals.
class _AppModal extends StatelessWidget {
  final bool isDark;
  final String title;
  final IconData icon;
  final Color? iconColor;
  final Widget child;

  const _AppModal({
    required this.isDark,
    required this.title,
    required this.icon,
    this.iconColor,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? AppColors.darkSurface : AppColors.white;
    final accent = iconColor ?? AppColors.primaryBlue;
    return Dialog(
      backgroundColor: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 20,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, size: 15, color: accent),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: AppTextStyles.body(
                        color: isDark
                            ? AppColors.warmWhite
                            : AppColors.nearBlack,
                      ).copyWith(fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                  ),
                  AppCloseButton(onPressed: () => Navigator.pop(context)),
                ],
              ),
              const SizedBox(height: 12),
              Divider(
                height: 1,
                color: (isDark ? AppColors.coolGray : AppColors.darkGray)
                    .withValues(alpha: 0.15),
              ),
              const SizedBox(height: 16),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact, dense text field for use inside modals.
class _DenseField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? prefixText;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final bool isDark;
  final int maxLines;
  final bool readOnly;
  final VoidCallback? onTap;

  const _DenseField({
    required this.controller,
    required this.label,
    this.prefixText,
    this.keyboardType,
    this.inputFormatters,
    required this.isDark,
    this.maxLines = 1,
    this.readOnly = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      maxLines: maxLines,
      readOnly: readOnly,
      onTap: onTap,
      style: AppTextStyles.body().copyWith(fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: AppTextStyles.caption(),
        prefixText: prefixText,
        isDense: true,
        filled: true,
        fillColor: isDark ? AppColors.darkBackground : AppColors.warmOffWhite,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusInput),
          borderSide: BorderSide(
            color: (isDark ? AppColors.coolGray : AppColors.darkGray)
                .withValues(alpha: 0.3),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusInput),
          borderSide: BorderSide(
            color: (isDark ? AppColors.coolGray : AppColors.darkGray)
                .withValues(alpha: 0.25),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusInput),
          borderSide: BorderSide(color: AppColors.primaryBlue),
        ),
      ),
    );
  }
}

/// Cancel + confirm button row for modals.
class _ModalActions extends StatelessWidget {
  final bool isDark;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;
  final String confirmLabel;
  final IconData? confirmIcon;
  final Color? confirmColor;

  const _ModalActions({
    required this.isDark,
    required this.onCancel,
    required this.onConfirm,
    required this.confirmLabel,
    this.confirmIcon,
    this.confirmColor,
  });

  @override
  Widget build(BuildContext context) {
    final btnColor = confirmColor ?? AppColors.amber;
    final fgColor =
        (confirmColor != null &&
            confirmColor != AppColors.amber &&
            confirmColor != const Color(0xFFFFB300))
        ? AppColors.white
        : AppColors.nearBlack;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: onCancel,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 10),
              side: BorderSide(
                color: (isDark ? AppColors.coolGray : AppColors.darkGray)
                    .withValues(alpha: 0.5),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppConstants.radiusButton),
              ),
            ),
            child: Text(
              'Annuler',
              style: AppTextStyles.caption().copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: ElevatedButton(
            onPressed: onConfirm,
            style: ElevatedButton.styleFrom(
              backgroundColor: btnColor,
              foregroundColor: fgColor,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppConstants.radiusButton),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (confirmIcon != null) ...[
                  Icon(confirmIcon, size: 14),
                  const SizedBox(width: 6),
                ],
                Text(
                  confirmLabel,
                  style: AppTextStyles.caption().copyWith(
                    fontWeight: FontWeight.w700,
                    color: fgColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Payment Dialog ────────────────────────────────────────────────────────────

// ── Block Dialog ──────────────────────────────────────────────────────────────

class _BlockDialog extends StatefulWidget {
  final Customer customer;
  final bool isDark;
  final void Function(String reason) onConfirm;

  const _BlockDialog({
    required this.customer,
    required this.isDark,
    required this.onConfirm,
  });

  @override
  State<_BlockDialog> createState() => _BlockDialogState();
}

class _BlockDialogState extends State<_BlockDialog> {
  final _reasonCtrl = TextEditingController();

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _AppModal(
      isDark: widget.isDark,
      title: 'Bloquer le crédit',
      icon: Icons.block_outlined,
      iconColor: AppColors.boldRed,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.boldRed.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(AppConstants.radiusCard),
              border: Border.all(
                color: AppColors.boldRed.withValues(alpha: 0.18),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.person_off_outlined,
                  color: AppColors.boldRed,
                  size: 15,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.customer.name,
                    style: AppTextStyles.body().copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _DenseField(
            controller: _reasonCtrl,
            label: 'Motif du blocage',
            isDark: widget.isDark,
            maxLines: 2,
          ),
          const SizedBox(height: 20),
          _ModalActions(
            isDark: widget.isDark,
            onCancel: () => Navigator.pop(context),
            onConfirm: () {
              final reason = _reasonCtrl.text.trim();
              if (reason.isEmpty) return;
              widget.onConfirm(reason);
              Navigator.pop(context);
            },
            confirmLabel: 'Confirmer le blocage',
            confirmIcon: Icons.block_outlined,
            confirmColor: AppColors.boldRed,
          ),
        ],
      ),
    );
  }
}

// ── Adjustment Dialog ─────────────────────────────────────────────────────────

class _AdjustmentDialog extends StatefulWidget {
  final Customer customer;
  final double balance;
  final bool isDark;
  final void Function(double amount, String description) onConfirm;

  const _AdjustmentDialog({
    required this.customer,
    required this.balance,
    required this.isDark,
    required this.onConfirm,
  });

  @override
  State<_AdjustmentDialog> createState() => _AdjustmentDialogState();
}

class _AdjustmentDialogState extends State<_AdjustmentDialog> {
  final _amtCtrl = TextEditingController();
  final _descCtrl = TextEditingController(text: 'Ajustement de solde');
  bool _isAdd = true;

  @override
  void dispose() {
    _amtCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final accentBlue = isDark ? AppColors.skyBlue : AppColors.primaryBlue;

    return _AppModal(
      isDark: isDark,
      title: 'Ajustement du solde',
      icon: Icons.tune_outlined,
      iconColor: accentBlue,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Choisissez d\'ajouter ou de retirer un montant du solde.',
            style: AppTextStyles.caption(),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _AdjustmentOptionChip(
                  label: 'Ajouter',
                  icon: Icons.add_circle_outline,
                  isSelected: _isAdd,
                  isDark: isDark,
                  onTap: () => setState(() => _isAdd = true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _AdjustmentOptionChip(
                  label: 'Retirer',
                  icon: Icons.remove_circle_outline,
                  isSelected: !_isAdd,
                  isDark: isDark,
                  onTap: () => setState(() => _isAdd = false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _DenseField(
            controller: _amtCtrl,
            label: 'Montant (HTG)',
            prefixText: 'HTG ',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: InputFormatters.decimalAmount,
            isDark: isDark,
          ),
          const SizedBox(height: 10),
          _DenseField(
            controller: _descCtrl,
            label: 'Motif / description',
            isDark: isDark,
          ),
          const SizedBox(height: 20),
          _ModalActions(
            isDark: isDark,
            onCancel: () => Navigator.pop(context),
            onConfirm: () {
              final amount = double.tryParse(_amtCtrl.text) ?? 0;
              if (amount <= 0) return;
              widget.onConfirm(
                _isAdd ? amount : -amount,
                _descCtrl.text.trim().isEmpty
                    ? 'Ajustement de solde'
                    : _descCtrl.text.trim(),
              );
              Navigator.pop(context);
            },
            confirmLabel: 'Appliquer l\'ajustement',
            confirmIcon: Icons.tune_outlined,
            confirmColor: accentBlue,
          ),
        ],
      ),
    );
  }
}

// ── Notes Dialog ──────────────────────────────────────────────────────────────

class _NotesDialog extends ConsumerStatefulWidget {
  final Customer customer;
  final bool isDark;

  const _NotesDialog({required this.customer, required this.isDark});

  @override
  ConsumerState<_NotesDialog> createState() => _NotesDialogState();
}

class _NotesDialogState extends ConsumerState<_NotesDialog> {
  final _textCtrl = TextEditingController();

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(customerProvider);
    final notes = state.notesFor(widget.customer.id);
    final isDark = widget.isDark;
    final bg = isDark ? AppColors.darkSurface : AppColors.white;
    final green = isDark ? const Color(0xFF6EE7B7) : const Color(0xFF059669);
    final dividerColor = (isDark ? AppColors.coolGray : AppColors.darkGray)
        .withValues(alpha: 0.15);

    return Dialog(
      backgroundColor: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 20,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 540),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ──────────────────────────────────────────────────
            _DialogHeader(
              title: 'Notes',
              subtitle: widget.customer.name,
              count: notes.length,
              icon: Icons.sticky_note_2_outlined,
              iconColor: green,
              isDark: isDark,
            ),

            // ── Notes list ───────────────────────────────────────────────
            Flexible(
              child: notes.isEmpty
                  ? _DialogEmptyState(
                      message: 'Aucune note',
                      icon: Icons.sticky_note_2_outlined,
                      isDark: isDark,
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                      itemCount: notes.length,
                      separatorBuilder: (_, __) =>
                          Divider(height: 16, color: dividerColor),
                      itemBuilder: (_, i) {
                        final n = notes.reversed.toList()[i];
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              n.text,
                              style: AppTextStyles.body().copyWith(
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${n.createdAt.day}/${n.createdAt.month}/${n.createdAt.year} · ${n.createdBy}',
                              style: AppTextStyles.caption(),
                            ),
                          ],
                        );
                      },
                    ),
            ),

            // ── Inline form ──────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: dividerColor)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Ajouter une note',
                    style: AppTextStyles.caption().copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _DenseField(
                    controller: _textCtrl,
                    label: 'p. ex. client appelé, injoignable',
                    isDark: isDark,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: SizedBox(
                      height: 32,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          final text = _textCtrl.text.trim();
                          if (text.isEmpty) return;
                          ref
                              .read(customerProvider.notifier)
                              .addNote(
                                customerId: widget.customer.id,
                                text: text,
                                createdBy: 'Gérant',
                              );
                          _textCtrl.clear();
                        },
                        icon: const Icon(Icons.add, size: 13),
                        label: Text(
                          'Ajouter une note',
                          style: AppTextStyles.caption().copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.nearBlack,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: green,
                          foregroundColor: AppColors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              AppConstants.radiusButton,
                            ),
                          ),
                        ),
                      ),
                    ),
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

// ── Schedules Dialog ──────────────────────────────────────────────────────────

class _SchedulesDialog extends ConsumerStatefulWidget {
  final Customer customer;
  final bool isDark;

  const _SchedulesDialog({required this.customer, required this.isDark});

  @override
  ConsumerState<_SchedulesDialog> createState() => _SchedulesDialogState();
}

class _SchedulesDialogState extends ConsumerState<_SchedulesDialog> {
  final _dateCtrl = TextEditingController();
  final _amtCtrl = TextEditingController();

  @override
  void dispose() {
    _dateCtrl.dispose();
    _amtCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(customerProvider);
    final schedules = state.schedulesFor(widget.customer.id);
    final isDark = widget.isDark;
    final bg = isDark ? AppColors.darkSurface : AppColors.white;
    final green = isDark ? const Color(0xFF6EE7B7) : const Color(0xFF059669);
    final dividerColor = (isDark ? AppColors.coolGray : AppColors.darkGray)
        .withValues(alpha: 0.15);

    final total = schedules.fold<double>(0, (s, e) => s + e.amountHtg);

    return Dialog(
      backgroundColor: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 20,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ──────────────────────────────────────────────────
            _DialogHeader(
              title: 'Échéanciers',
              subtitle: total > 0
                  ? '${widget.customer.name}  ·  ${CurrencyFormatter.local(context, total)} total'
                  : widget.customer.name,
              count: schedules.length,
              icon: Icons.event_outlined,
              iconColor: green,
              isDark: isDark,
            ),

            // ── Schedule list ─────────────────────────────────────────────
            Flexible(
              child: schedules.isEmpty
                  ? _DialogEmptyState(
                      message: 'Aucune échéance',
                      icon: Icons.event_outlined,
                      isDark: isDark,
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                      itemCount: schedules.length,
                      separatorBuilder: (_, __) =>
                          Divider(height: 12, color: dividerColor),
                      itemBuilder: (_, i) {
                        final s = schedules[i];
                        return Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: green.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Icon(
                                Icons.event_outlined,
                                size: 13,
                                color: green,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${s.scheduledDate.day}/${s.scheduledDate.month}/${s.scheduledDate.year}',
                                style: AppTextStyles.body().copyWith(
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            Text(
                              CurrencyFormatter.local(context, s.amountHtg),
                              style: AppTextStyles.body().copyWith(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
            ),

            // ── Inline form ──────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: dividerColor)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Ajouter une échéance',
                    style: AppTextStyles.caption().copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: _DenseField(
                          controller: _dateCtrl,
                          label: 'Date (touchez pour choisir)',
                          isDark: isDark,
                          readOnly: true,
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: DateTime.now(),
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now().add(
                                const Duration(days: 365),
                              ),
                            );
                            if (picked != null) {
                              _dateCtrl.text =
                                  '${picked.day}/${picked.month}/${picked.year}';
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _DenseField(
                          controller: _amtCtrl,
                          label: 'Montant',
                          prefixText: 'HTG ',
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: InputFormatters.decimalAmount,
                          isDark: isDark,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: SizedBox(
                      height: 32,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          final amount = double.tryParse(_amtCtrl.text) ?? 0;
                          if (amount <= 0) return;
                          DateTime? date;
                          final parts = _dateCtrl.text.trim().split('/');
                          if (parts.length == 3) {
                            final d = int.tryParse(parts[0]);
                            final m = int.tryParse(parts[1]);
                            final y = int.tryParse(parts[2]);
                            if (d != null && m != null && y != null) {
                              date = DateTime(y, m, d);
                            }
                          }
                          date ??= DateTime.now().add(const Duration(days: 7));
                          ref
                              .read(customerProvider.notifier)
                              .addSchedule(
                                customerId: widget.customer.id,
                                scheduledDate: date,
                                amountHtg: amount,
                              );
                          _amtCtrl.clear();
                          _dateCtrl.clear();
                        },
                        icon: const Icon(Icons.add, size: 13),
                        label: Text(
                          'Ajouter',
                          style: AppTextStyles.caption().copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.nearBlack,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: green,
                          foregroundColor: AppColors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              AppConstants.radiusButton,
                            ),
                          ),
                        ),
                      ),
                    ),
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

// ── Dialog sub-widgets ────────────────────────────────────────────────────────

class _DialogHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final int count;
  final IconData icon;
  final Color iconColor;
  final bool isDark;

  const _DialogHeader({
    required this.title,
    required this.subtitle,
    required this.count,
    required this.icon,
    required this.iconColor,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final divider = (isDark ? AppColors.coolGray : AppColors.darkGray)
        .withValues(alpha: 0.15);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: divider)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 15, color: iconColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: AppTextStyles.body(
                    color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
                  ).copyWith(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                Text(
                  subtitle,
                  style: AppTextStyles.caption(),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (count > 0) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$count',
                style: AppTextStyles.caption(
                  color: iconColor,
                ).copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 4),
          ],
          AppCloseButton(onPressed: () => Navigator.pop(context)),
        ],
      ),
    );
  }
}

class _DialogEmptyState extends StatelessWidget {
  final String message;
  final IconData icon;
  final bool isDark;

  const _DialogEmptyState({
    required this.message,
    required this.icon,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 28,
            color: (isDark ? AppColors.coolGray : AppColors.darkGray)
                .withValues(alpha: 0.4),
          ),
          const SizedBox(height: 8),
          Text(message, style: AppTextStyles.caption()),
        ],
      ),
    );
  }
}

// ── Panel sub-widgets ─────────────────────────────────────────────────────────

class _PanelHeader extends StatelessWidget {
  final Customer customer;
  final double balance;
  final double storeCreditBalance;
  final bool isDark;
  final VoidCallback onClose;
  final VoidCallback onEdit;

  const _PanelHeader({
    required this.customer,
    required this.balance,
    required this.storeCreditBalance,
    required this.isDark,
    required this.onClose,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final avatarBg = customer.isCreditBlocked
        ? AppColors.boldRed.withValues(alpha: 0.12)
        : (isDark
              ? AppColors.primaryBlue.withValues(alpha: 0.3)
              : AppColors.lightBlue);
    final avatarFg = customer.isCreditBlocked
        ? AppColors.boldRed
        : (isDark ? AppColors.skyBlue : AppColors.primaryBlue);

    return Container(
      padding: const EdgeInsets.fromLTRB(AppConstants.spacing16, 14, 8, 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: (isDark ? AppColors.coolGray : AppColors.darkGray)
                .withValues(alpha: 0.15),
          ),
        ),
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: avatarBg, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text(
              customer.name.isNotEmpty ? customer.name[0].toUpperCase() : '?',
              style: AppTextStyles.body(
                color: avatarFg,
              ).copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        customer.name,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.body(
                          color: isDark
                              ? AppColors.warmWhite
                              : AppColors.nearBlack,
                        ).copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (customer.isCreditBlocked) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.boldRed.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(
                            color: AppColors.boldRed.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Text(
                          'BLOQUÉ',
                          style: AppTextStyles.caption(
                            color: AppColors.boldRed,
                          ).copyWith(fontSize: 8, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  [
                    customer.phone,
                    if (customer.address != null) customer.address!,
                  ].join(' · '),
                  style: AppTextStyles.caption(),
                  overflow: TextOverflow.ellipsis,
                ),
                if (storeCreditBalance > 0.009) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Avoir magasin ${CurrencyFormatter.local(context, storeCreditBalance)}',
                    style: AppTextStyles.caption(
                      color: AppColors.deepGreen,
                    ).copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ],
            ),
          ),
          // Edit & close buttons
          SizedBox(
            width: 30,
            height: 30,
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: Icon(Icons.edit_outlined, size: 16),
              color: isDark ? AppColors.coolGray : AppColors.darkGray,
              onPressed: onEdit,
              tooltip: 'Modifier le client',
            ),
          ),
          AppCloseButton(onPressed: onClose),
        ],
      ),
    );
  }
}

class _BlockedBanner extends StatelessWidget {
  final Customer customer;
  final bool isDark;

  const _BlockedBanner({required this.customer, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppConstants.spacing16,
        AppConstants.spacing8,
        AppConstants.spacing16,
        0,
      ),
      padding: const EdgeInsets.all(AppConstants.spacing10),
      decoration: BoxDecoration(
        color: AppColors.boldRed.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppConstants.radiusCard),
        border: Border.all(color: AppColors.boldRed.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.block_outlined, color: AppColors.boldRed, size: 14),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Crédit bloqué',
                  style: AppTextStyles.caption(
                    color: AppColors.boldRed,
                  ).copyWith(fontWeight: FontWeight.w700),
                ),
                if (customer.blockedReason != null)
                  Text(customer.blockedReason!, style: AppTextStyles.caption()),
                if (customer.blockedBy != null && customer.blockedAt != null)
                  Text(
                    'Par ${customer.blockedBy} · ${customer.blockedAt!.day}/${customer.blockedAt!.month}/${customer.blockedAt!.year}',
                    style: AppTextStyles.caption(),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  final double balance;
  final Customer customer;
  final bool isDark;

  const _StatsRow({
    required this.balance,
    required this.customer,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final balanceColor = balance > 0 ? AppColors.boldRed : AppColors.deepGreen;
    final limitColor = isDark ? AppColors.skyBlue : AppColors.primaryBlue;
    final bg = isDark ? AppColors.darkBackground : AppColors.warmOffWhite;
    final radius = BorderRadius.circular(AppConstants.radiusCard);

    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: balanceColor.withValues(alpha: 0.08),
              borderRadius: radius,
              border: Border.all(color: balanceColor.withValues(alpha: 0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Impayé',
                  style: AppTextStyles.caption(color: balanceColor),
                ),
                const SizedBox(height: 2),
                Text(
                  CurrencyFormatter.local(context, balance),
                  style: AppTextStyles.body(
                    color: balanceColor,
                  ).copyWith(fontWeight: FontWeight.w700, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: AppConstants.spacing8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: radius,
              border: Border.all(
                color: (isDark ? AppColors.coolGray : AppColors.darkGray)
                    .withValues(alpha: 0.2),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Limite de crédit', style: AppTextStyles.caption()),
                const SizedBox(height: 2),
                Text(
                  customer.creditLimitHtg != null
                      ? CurrencyFormatter.local(
                          context,
                          customer.creditLimitHtg!,
                        )
                      : 'Sans limite',
                  style: AppTextStyles.body(
                    color: limitColor,
                  ).copyWith(fontWeight: FontWeight.w700, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StoreCreditSection extends StatelessWidget {
  final Customer customer;
  final double storeCreditBalance;
  final List<StoreCreditLedgerEntry> history;
  final int shown;
  final VoidCallback onShowMore;
  final bool isDark;

  const _StoreCreditSection({
    required this.customer,
    required this.storeCreditBalance,
    required this.history,
    required this.shown,
    required this.onShowMore,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final primary = isDark ? AppColors.warmWhite : AppColors.nearBlack;
    final secondary = isDark ? AppColors.coolGray : AppColors.darkGray;
    final visible = history.take(shown).toList();
    final hasMore = history.length > shown;

    if (!customer.hasStoreCreditIdentity &&
        storeCreditBalance <= 0.009 &&
        history.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppConstants.spacing12),
        decoration: BoxDecoration(
          color: (isDark ? AppColors.darkBackground : AppColors.warmOffWhite),
          borderRadius: BorderRadius.circular(AppConstants.radiusCard),
          border: Border.all(color: secondary.withValues(alpha: 0.15)),
        ),
        child: Text(
          'Ajoutez une pièce d\'identité ou la date de naissance (avec prénom et nom) pour utiliser le crédit magasin.',
          style: AppTextStyles.caption(color: secondary),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.spacing12),
      decoration: BoxDecoration(
        color: AppColors.deepGreen.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppConstants.radiusCard),
        border: Border.all(color: AppColors.deepGreen.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Crédit magasin',
            style: AppTextStyles.caption(
              color: AppColors.deepGreen,
            ).copyWith(fontWeight: FontWeight.w800, letterSpacing: 0.4),
          ),
          const SizedBox(height: 4),
          Text(
            CurrencyFormatter.local(context, storeCreditBalance),
            style: AppTextStyles.body(
              color: AppColors.deepGreen,
            ).copyWith(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          if (history.isNotEmpty) ...[
            const SizedBox(height: AppConstants.spacing12),
            Text(
              'Historique',
              style: AppTextStyles.caption(
                color: secondary,
              ).copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            for (final e in visible) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    e.kind == StoreCreditEntryKind.issued
                        ? Icons.add_circle_outline
                        : Icons.remove_circle_outline,
                    size: 14,
                    color: e.kind == StoreCreditEntryKind.issued
                        ? AppColors.deepGreen
                        : AppColors.boldRed,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e.description,
                          style: AppTextStyles.caption(color: primary),
                        ),
                        Text(
                          '${e.kind == StoreCreditEntryKind.issued ? '+' : '−'} ${CurrencyFormatter.local(context, e.amountHtg)} · ${_fmt(e.createdAt)}',
                          style: AppTextStyles.caption(color: secondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Divider(height: 12, color: secondary.withValues(alpha: 0.12)),
            ],
            if (hasMore)
              TextButton(
                onPressed: onShowMore,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'Charger plus',
                  style: AppTextStyles.caption(
                    color: isDark ? AppColors.skyBlue : AppColors.primaryBlue,
                  ).copyWith(fontWeight: FontWeight.w600),
                ),
              ),
          ],
        ],
      ),
    );
  }

  String _fmt(DateTime d) =>
      '${d.day}/${d.month}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class _NoteBanner extends StatelessWidget {
  final String text;
  final bool isDark;

  const _NoteBanner({required this.text, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: (isDark ? AppColors.skyBlue : AppColors.primaryBlue).withValues(
          alpha: 0.06,
        ),
        borderRadius: BorderRadius.circular(AppConstants.radiusInput),
        border: Border.all(
          color: (isDark ? AppColors.skyBlue : AppColors.primaryBlue)
              .withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            size: 13,
            color: isDark ? AppColors.skyBlue : AppColors.primaryBlue,
          ),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: AppTextStyles.caption())),
        ],
      ),
    );
  }
}

class _ActionButtons extends StatelessWidget {
  final Customer customer;
  final double balance;
  final bool isDark;
  final VoidCallback onTakePayment;
  final VoidCallback onToggleBlock;
  final VoidCallback onAdjustment;
  final VoidCallback onNotes;
  final VoidCallback onSchedules;

  const _ActionButtons({
    required this.customer,
    required this.balance,
    required this.isDark,
    required this.onTakePayment,
    required this.onToggleBlock,
    required this.onAdjustment,
    required this.onNotes,
    required this.onSchedules,
  });

  @override
  Widget build(BuildContext context) {
    const h = 30.0;
    final textStyle = AppTextStyles.caption().copyWith(
      fontWeight: FontWeight.w600,
      fontSize: 11,
    );
    final accentBlue = isDark ? AppColors.skyBlue : AppColors.primaryBlue;
    final accentGreen = isDark
        ? const Color(0xFF6EE7B7)
        : const Color(0xFF059669);

    return Wrap(
      spacing: AppConstants.spacing6,
      runSpacing: AppConstants.spacing6,
      children: [
        if (balance > 0)
          _CompactBtn(
            label: 'Paiement',
            icon: Icons.payments_outlined,
            height: h,
            textStyle: textStyle,
            onPressed: onTakePayment,
            isPrimary: true,
          ),
        _CompactBtn(
          label: customer.isCreditBlocked ? 'Unblock' : 'Block',
          icon: customer.isCreditBlocked
              ? Icons.lock_open_outlined
              : Icons.block_outlined,
          height: h,
          textStyle: textStyle,
          onPressed: onToggleBlock,
          isPrimary: false,
          color: accentBlue,
        ),
        _CompactBtn(
          label: 'Ajuster',
          icon: Icons.tune_outlined,
          height: h,
          textStyle: textStyle,
          onPressed: onAdjustment,
          isPrimary: false,
          color: accentBlue,
        ),
        _CompactBtn(
          label: 'Notes',
          icon: Icons.sticky_note_2_outlined,
          height: h,
          textStyle: textStyle,
          onPressed: onNotes,
          isPrimary: false,
          color: accentGreen,
        ),
        _CompactBtn(
          label: 'Échéances',
          icon: Icons.event_outlined,
          height: h,
          textStyle: textStyle,
          onPressed: onSchedules,
          isPrimary: false,
          color: accentGreen,
        ),
      ],
    );
  }
}

class _CompactBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final double height;
  final TextStyle textStyle;
  final VoidCallback onPressed;
  final bool isPrimary;
  final Color? color;

  const _CompactBtn({
    required this.label,
    required this.icon,
    required this.height,
    required this.textStyle,
    required this.onPressed,
    required this.isPrimary,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    if (isPrimary) {
      return SizedBox(
        height: height,
        child: ElevatedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 13),
          label: Text(
            label,
            style: textStyle.copyWith(color: AppColors.nearBlack),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.amber,
            foregroundColor: AppColors.nearBlack,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppConstants.radiusButton),
            ),
          ),
        ),
      );
    }
    final c = color ?? AppColors.primaryBlue;
    return SizedBox(
      height: height,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 13, color: c),
        label: Text(label, style: textStyle.copyWith(color: c)),
        style: OutlinedButton.styleFrom(
          foregroundColor: c,
          side: BorderSide(color: c.withValues(alpha: 0.5)),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.radiusButton),
          ),
        ),
      ),
    );
  }
}

class _SectionDivider extends StatelessWidget {
  final String label;
  final int count;

  const _SectionDivider({required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: AppTextStyles.caption().copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(width: 6),
        Text('($count)', style: AppTextStyles.caption()),
        const SizedBox(width: 8),
        const Expanded(child: Divider(height: 1)),
      ],
    );
  }
}

class _CompactTxRow extends StatelessWidget {
  final CustomerTransaction tx;
  final bool isDark;

  const _CompactTxRow({required this.tx, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final isPayment = tx.type == CustomerTransactionType.payment;
    final isAdjustment = tx.type == CustomerTransactionType.adjustment;
    final isCharge = tx.type == CustomerTransactionType.charge;
    final color = isPayment
        ? AppColors.deepGreen
        : isCharge
        ? AppColors.boldRed
        : AppColors.amber;
    final icon = isPayment
        ? Icons.south_rounded
        : isCharge
        ? Icons.receipt_outlined
        : Icons.tune_outlined;
    final amountStr = isPayment
        ? '-${CurrencyFormatter.local(context, tx.amountHtg)}'
        : isAdjustment
        ? '${tx.amountHtg >= 0 ? '+' : ''}${CurrencyFormatter.local(context, tx.amountHtg.abs())}'
        : '+${CurrencyFormatter.local(context, tx.creditedHtg)}';

    final meta = <String>[
      if (tx.linkedTableName != null) tx.linkedTableName!,
      if (tx.serverName != null) tx.serverName!,
      '${tx.timestamp.day}/${tx.timestamp.month}/${tx.timestamp.year}',
      tx.cashierName,
    ].join(' · ');

    return Container(
      color: isAdjustment
          ? AppColors.amber.withValues(alpha: 0.08)
          : Colors.transparent,
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, size: 13, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        tx.description,
                        style: AppTextStyles.caption(
                          color: isDark
                              ? AppColors.warmWhite
                              : AppColors.nearBlack,
                        ).copyWith(fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isPayment && tx.paymentMethodLabel != null) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.deepGreen.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          tx.paymentMethodLabel!,
                          style: AppTextStyles.caption(
                            color: AppColors.deepGreen,
                          ).copyWith(fontSize: 9, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  meta,
                  style: AppTextStyles.caption(
                    color: isDark ? AppColors.coolGray : AppColors.darkGray,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                amountStr,
                style: AppTextStyles.caption(
                  color: color,
                ).copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                'Bal: ${CurrencyFormatter.local(context, tx.balanceAfterHtg)}',
                style: AppTextStyles.caption(
                  color: isDark ? AppColors.coolGray : AppColors.darkGray,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Bottom Sheet (legacy – used on narrow screens and hotel) ─────────────────

class CustomerDetailSheet extends ConsumerStatefulWidget {
  final Customer customer;
  final bool isDark;
  final String formRoute;
  final bool showHotelSection;

  const CustomerDetailSheet({
    super.key,
    required this.customer,
    required this.isDark,
    required this.formRoute,
    this.showHotelSection = false,
  });

  @override
  ConsumerState<CustomerDetailSheet> createState() =>
      _CustomerDetailSheetState();
}

class _CustomerDetailSheetState extends ConsumerState<CustomerDetailSheet> {
  bool _showBlockForm = false;
  final _blockReasonCtrl = TextEditingController();
  static const int _initialTxCount = 10;
  static const int _initialCreditCount = 8;
  int _transactionsShown = _initialTxCount;
  int _storeCreditShown = _initialCreditCount;
  bool _notesExpanded = false;
  bool _schedulesExpanded = false;

  @override
  void dispose() {
    _blockReasonCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(customerProvider);
    // Refresh from state (may have been updated)
    final customer = state.customers.firstWhere(
      (c) => c.id == widget.customer.id,
      orElse: () => widget.customer,
    );
    final allTransactions = state.transactionsFor(customer.id);
    final totalTxCount = state.transactionCountFor(customer.id);
    final transactions = allTransactions.take(_transactionsShown).toList();
    final hasMoreTx = _transactionsShown < totalTxCount;
    final balance = state.balanceFor(customer.id);
    final storeCreditBal = state.storeCreditBalanceFor(customer.id);
    final isDark = widget.isDark;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (_, sc) => Column(
        children: [
          // Header row
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.spacing24,
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: customer.isCreditBlocked
                        ? AppColors.boldRed.withValues(alpha: 0.12)
                        : (isDark
                              ? AppColors.primaryBlue.withValues(alpha: 0.25)
                              : AppColors.lightBlue),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      customer.name[0].toUpperCase(),
                      style: AppTextStyles.h2(
                        color: customer.isCreditBlocked
                            ? AppColors.boldRed
                            : (isDark
                                  ? AppColors.skyBlue
                                  : AppColors.primaryBlue),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppConstants.spacing12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        customer.name,
                        style: AppTextStyles.h2(
                          color: isDark
                              ? AppColors.warmWhite
                              : AppColors.nearBlack,
                        ),
                      ),
                      Text(customer.phone, style: AppTextStyles.caption()),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  color: isDark ? AppColors.coolGray : AppColors.darkGray,
                  onPressed: () {
                    Navigator.pop(context);
                    showAppBottomSheet(
                      context: context,
                      child: CustomerFormSheet(
                        isDark: isDark,
                        existing: customer,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          // Blocked banner
          if (customer.isCreditBlocked)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppConstants.spacing24,
                AppConstants.spacing12,
                AppConstants.spacing24,
                0,
              ),
              child: Container(
                padding: const EdgeInsets.all(AppConstants.spacing12),
                decoration: BoxDecoration(
                  color: AppColors.boldRed.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppConstants.radiusCard),
                  border: Border.all(
                    color: AppColors.boldRed.withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.block_outlined,
                      color: AppColors.boldRed,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Crédit bloqué',
                            style: AppTextStyles.body(
                              color: AppColors.boldRed,
                            ).copyWith(fontWeight: FontWeight.w700),
                          ),
                          if (customer.blockedReason != null)
                            Text(
                              customer.blockedReason!,
                              style: AppTextStyles.caption(),
                            ),
                          if (customer.blockedBy != null)
                            Text(
                              'Par ${customer.blockedBy} le ${_dateStr(customer.blockedAt!)}',
                              style: AppTextStyles.caption(),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

          Expanded(
            child: ListView(
              controller: sc,
              padding: const EdgeInsets.all(AppConstants.spacing24),
              children: [
                // Balance card
                Row(
                  children: [
                    _StatCard(
                      label: 'Impayé',
                      value: CurrencyFormatter.local(context, balance),
                      color: balance > 0
                          ? AppColors.boldRed
                          : AppColors.deepGreen,
                      isDark: isDark,
                    ),
                    const SizedBox(width: AppConstants.spacing12),
                    _StatCard(
                      label: 'Limite de crédit',
                      value: customer.creditLimitHtg != null
                          ? CurrencyFormatter.local(
                              context,
                              customer.creditLimitHtg!,
                            )
                          : 'Sans limite',
                      color: isDark ? AppColors.skyBlue : AppColors.primaryBlue,
                      isDark: isDark,
                    ),
                  ],
                ),

                const SizedBox(height: AppConstants.spacing12),
                _StoreCreditSection(
                  customer: customer,
                  storeCreditBalance: storeCreditBal,
                  history: state.storeCreditHistoryFor(customer.id),
                  shown: _storeCreditShown,
                  onShowMore: () =>
                      setState(() => _storeCreditShown += _initialCreditCount),
                  isDark: isDark,
                ),

                // Hotel section (when opened from hotel customers)
                if (widget.showHotelSection) ...[
                  const SizedBox(height: AppConstants.spacing24),
                  _HotelSection(customerId: customer.id, isDark: isDark),
                ],

                // Payment terms (legacy notes)
                if (customer.notes != null) ...[
                  const SizedBox(height: AppConstants.spacing16),
                  AppCard(
                    child: Row(
                      children: [
                        Icon(
                          Icons.schedule_outlined,
                          size: 16,
                          color: isDark
                              ? AppColors.coolGray
                              : AppColors.darkGray,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            customer.notes!,
                            style: AppTextStyles.body(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: AppConstants.spacing24),

                // Actions — same row, responsive
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isNarrow = constraints.maxWidth < 400;
                    final takePayment = AppButton(
                      label: 'Encaisser',
                      onPressed: () =>
                          _showTakePayment(context, customer, balance, isDark),
                      icon: Icons.payments_outlined,
                      fullWidth: true,
                    );
                    final blockBtn = AppButton(
                      label: customer.isCreditBlocked
                          ? 'Débloquer le crédit'
                          : 'Bloquer le crédit',
                      onPressed: () {
                        if (customer.isCreditBlocked) {
                          ref
                              .read(customerProvider.notifier)
                              .unblockCustomer(customer.id);
                        } else {
                          setState(() => _showBlockForm = !_showBlockForm);
                        }
                      },
                      variant: AppButtonVariant.secondary,
                      icon: customer.isCreditBlocked
                          ? Icons.lock_open_outlined
                          : Icons.block_outlined,
                      fullWidth: true,
                    );
                    final adjustmentBtn = AppButton(
                      label: 'Ajustement',
                      onPressed: () =>
                          _showAdjustment(context, customer, balance, isDark),
                      variant: AppButtonVariant.secondary,
                      icon: Icons.tune_outlined,
                      fullWidth: true,
                    );
                    if (isNarrow) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (balance > 0) ...[
                            takePayment,
                            const SizedBox(height: AppConstants.spacing8),
                          ],
                          blockBtn,
                          const SizedBox(height: AppConstants.spacing8),
                          adjustmentBtn,
                        ],
                      );
                    }
                    return Row(
                      children: [
                        if (balance > 0) ...[
                          Expanded(child: takePayment),
                          const SizedBox(width: AppConstants.spacing8),
                        ],
                        Expanded(child: blockBtn),
                        const SizedBox(width: AppConstants.spacing8),
                        Expanded(child: adjustmentBtn),
                      ],
                    );
                  },
                ),

                if (_showBlockForm && !customer.isCreditBlocked) ...[
                  const SizedBox(height: AppConstants.spacing12),
                  TextField(
                    controller: _blockReasonCtrl,
                    decoration: InputDecoration(
                      labelText: 'Motif du blocage (obligatoire)',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                          AppConstants.radiusInput,
                        ),
                      ),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: AppConstants.spacing8),
                  AppButton(
                    label: 'Confirmer le blocage',
                    onPressed: () {
                      final reason = _blockReasonCtrl.text.trim();
                      if (reason.isEmpty) return;
                      ref
                          .read(customerProvider.notifier)
                          .blockCustomer(
                            customer.id,
                            reason: reason,
                            blockedBy: 'Gérant',
                          );
                      setState(() => _showBlockForm = false);
                      _blockReasonCtrl.clear();
                    },
                    variant: AppButtonVariant.secondary,
                    icon: Icons.check_outlined,
                  ),
                ],

                const SizedBox(height: AppConstants.spacing24),

                // Transaction history
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Historique des transactions',
                        style: AppTextStyles.h2(
                          color: isDark
                              ? AppColors.warmWhite
                              : AppColors.nearBlack,
                        ),
                      ),
                    ),
                    Text(
                      '$totalTxCount records',
                      style: AppTextStyles.caption(),
                    ),
                  ],
                ),
                const SizedBox(height: AppConstants.spacing12),

                if (transactions.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppConstants.spacing24),
                      child: Text(
                        'Aucune transaction pour le moment.',
                        style: AppTextStyles.body(
                          color: isDark
                              ? AppColors.coolGray
                              : AppColors.darkGray,
                        ),
                      ),
                    ),
                  )
                else ...[
                  for (final tx in transactions) ...[
                    _TransactionRow(tx: tx, isDark: isDark),
                    const Divider(height: 1),
                  ],
                  if (hasMoreTx)
                    Padding(
                      padding: const EdgeInsets.only(
                        top: AppConstants.spacing12,
                      ),
                      child: Center(
                        child: TextButton(
                          onPressed: () {
                            setState(
                              () => _transactionsShown += _initialTxCount,
                            );
                          },
                          child: const Text('Charger plus'),
                        ),
                      ),
                    ),
                ],

                const SizedBox(height: AppConstants.spacing24),

                // Notes (lazy loaded)
                _NotesSection(
                  isDark: isDark,
                  isExpanded: _notesExpanded,
                  onToggle: () =>
                      setState(() => _notesExpanded = !_notesExpanded),
                  onAddNote: () => _showAddNote(context, customer, isDark),
                  notes: state.notesFor(customer.id),
                ),

                const SizedBox(height: AppConstants.spacing16),

                // Payment schedules (lazy loaded)
                _SchedulesSection(
                  isDark: isDark,
                  isExpanded: _schedulesExpanded,
                  onToggle: () =>
                      setState(() => _schedulesExpanded = !_schedulesExpanded),
                  onAddSchedule: () =>
                      _showAddSchedule(context, customer, isDark),
                  schedules: state.schedulesFor(customer.id),
                ),

                const SizedBox(height: AppConstants.spacing24),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showTakePayment(
    BuildContext context,
    Customer c,
    double balance,
    bool isDark,
  ) {
    final amtCtrl = TextEditingController();
    showAppBottomSheet(
      context: context,
      child: Padding(
        padding: EdgeInsets.only(
          left: AppConstants.spacing24,
          right: AppConstants.spacing24,
          top: AppConstants.spacing8,
          bottom:
              MediaQuery.of(context).viewInsets.bottom + AppConstants.spacing24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Outstanding amount
            Container(
              padding: const EdgeInsets.all(AppConstants.spacing24),
              decoration: BoxDecoration(
                color: AppColors.boldRed.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppConstants.radiusCard),
                border: Border.all(
                  color: AppColors.boldRed.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.account_balance_wallet_outlined,
                    color: AppColors.boldRed,
                    size: 24,
                  ),
                  const SizedBox(width: AppConstants.spacing12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Impayé',
                          style: AppTextStyles.caption(
                            color: AppColors.boldRed,
                          ),
                        ),
                        Text(
                          CurrencyFormatter.local(context, balance),
                          style: AppTextStyles.h2(
                            color: AppColors.boldRed,
                          ).copyWith(fontWeight: FontWeight.w700, fontSize: 22),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppConstants.spacing24),
            TextField(
              controller: amtCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: InputFormatters.decimalAmount,
              decoration: InputDecoration(
                labelText: 'Montant reçu (HTG)',
                prefixText: 'HTG ',
                filled: true,
                fillColor: isDark
                    ? AppColors.darkBackground
                    : AppColors.warmOffWhite,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusInput),
                ),
              ),
            ),
            const SizedBox(height: AppConstants.spacing24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: isDark ? AppColors.coolGray : AppColors.darkGray,
                      ),
                    ),
                    child: const Text('Annuler'),
                  ),
                ),
                const SizedBox(width: AppConstants.spacing12),
                Expanded(
                  flex: 2,
                  child: AppButton(
                    label: 'Confirmer le paiement',
                    onPressed: () {
                      final amount = double.tryParse(amtCtrl.text) ?? 0;
                      if (amount <= 0) return;
                      ref
                          .read(customerProvider.notifier)
                          .postPayment(
                            customerId: c.id,
                            amountHtg: amount.clamp(0, balance),
                            cashierName: 'Caissier',
                          );
                      Navigator.pop(context);
                    },
                    icon: Icons.check_circle_outline,
                    fullWidth: true,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showAdjustment(
    BuildContext context,
    Customer c,
    double balance,
    bool isDark,
  ) {
    final amtCtrl = TextEditingController();
    final descCtrl = TextEditingController(text: 'Ajustement de solde');
    bool isAdd = true; // true = add, false = subtract
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return AppBottomSheet(
            child: Padding(
              padding: EdgeInsets.only(
                left: AppConstants.spacing24,
                right: AppConstants.spacing24,
                top: AppConstants.spacing8,
                bottom:
                    MediaQuery.of(ctx).viewInsets.bottom +
                    AppConstants.spacing24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Ajustement',
                    style: AppTextStyles.h2(
                      color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Choisissez d\'ajouter ou de retirer un montant du solde.',
                    style: AppTextStyles.caption(),
                  ),
                  const SizedBox(height: AppConstants.spacing24),
                  Row(
                    children: [
                      Expanded(
                        child: _AdjustmentOptionChip(
                          label: 'Ajouter un montant',
                          icon: Icons.add_circle_outline,
                          isSelected: isAdd,
                          isDark: isDark,
                          onTap: () => setModalState(() => isAdd = true),
                        ),
                      ),
                      const SizedBox(width: AppConstants.spacing12),
                      Expanded(
                        child: _AdjustmentOptionChip(
                          label: 'Retirer un montant',
                          icon: Icons.remove_circle_outline,
                          isSelected: !isAdd,
                          isDark: isDark,
                          onTap: () => setModalState(() => isAdd = false),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppConstants.spacing16),
                  TextField(
                    controller: amtCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: InputFormatters.decimalAmount,
                    decoration: InputDecoration(
                      labelText: 'Montant (HTG)',
                      prefixText: 'HTG ',
                      filled: true,
                      fillColor: isDark
                          ? AppColors.darkBackground
                          : AppColors.warmOffWhite,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                          AppConstants.radiusInput,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppConstants.spacing16),
                  TextField(
                    controller: descCtrl,
                    decoration: InputDecoration(
                      labelText: 'Motif / description',
                      filled: true,
                      fillColor: isDark
                          ? AppColors.darkBackground
                          : AppColors.warmOffWhite,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                          AppConstants.radiusInput,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppConstants.spacing24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                              color: isDark
                                  ? AppColors.coolGray
                                  : AppColors.darkGray,
                            ),
                          ),
                          child: const Text('Annuler'),
                        ),
                      ),
                      const SizedBox(width: AppConstants.spacing12),
                      Expanded(
                        flex: 2,
                        child: AppButton(
                          label: 'Appliquer l\'ajustement',
                          onPressed: () {
                            final amount = double.tryParse(amtCtrl.text) ?? 0;
                            if (amount <= 0) return;
                            final signedAmount = isAdd ? amount : -amount;
                            ref
                                .read(customerProvider.notifier)
                                .postAdjustment(
                                  customerId: c.id,
                                  amountHtg: signedAmount,
                                  cashierName: 'Gérant',
                                  description: descCtrl.text.trim().isEmpty
                                      ? 'Ajustement de solde'
                                      : descCtrl.text.trim(),
                                );
                            Navigator.pop(ctx);
                          },
                          icon: Icons.tune_outlined,
                          fullWidth: true,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showAddNote(BuildContext context, Customer c, bool isDark) {
    final textCtrl = TextEditingController();
    showAppBottomSheet(
      context: context,
      child: Padding(
        padding: EdgeInsets.only(
          left: AppConstants.spacing24,
          right: AppConstants.spacing24,
          top: AppConstants.spacing8,
          bottom:
              MediaQuery.of(context).viewInsets.bottom + AppConstants.spacing24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Ajouter une note',
              style: AppTextStyles.h2(
                color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
              ),
            ),
            const SizedBox(height: AppConstants.spacing24),
            TextField(
              controller: textCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Note (ex. client appelé, injoignable)',
                filled: true,
                fillColor: isDark
                    ? AppColors.darkBackground
                    : AppColors.warmOffWhite,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusInput),
                ),
              ),
            ),
            const SizedBox(height: AppConstants.spacing24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: isDark ? AppColors.coolGray : AppColors.darkGray,
                      ),
                    ),
                    child: const Text('Annuler'),
                  ),
                ),
                const SizedBox(width: AppConstants.spacing12),
                Expanded(
                  flex: 2,
                  child: AppButton(
                    label: 'Enregistrer la note',
                    onPressed: () {
                      final text = textCtrl.text.trim();
                      if (text.isEmpty) return;
                      ref
                          .read(customerProvider.notifier)
                          .addNote(
                            customerId: c.id,
                            text: text,
                            createdBy: 'Gérant',
                          );
                      Navigator.pop(context);
                    },
                    icon: Icons.note_add_outlined,
                    fullWidth: true,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showAddSchedule(BuildContext context, Customer c, bool isDark) {
    final dateCtrl = TextEditingController();
    final amtCtrl = TextEditingController();
    showAppBottomSheet(
      context: context,
      child: Padding(
        padding: EdgeInsets.only(
          left: AppConstants.spacing24,
          right: AppConstants.spacing24,
          top: AppConstants.spacing8,
          bottom:
              MediaQuery.of(context).viewInsets.bottom + AppConstants.spacing24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Ajouter une échéance',
              style: AppTextStyles.h2(
                color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Planifiez quand le client compte payer (date + montant).',
              style: AppTextStyles.caption(),
            ),
            const SizedBox(height: AppConstants.spacing24),
            TextField(
              controller: dateCtrl,
              readOnly: true,
              decoration: InputDecoration(
                labelText: 'Date (touchez pour choisir)',
                filled: true,
                fillColor: isDark
                    ? AppColors.darkBackground
                    : AppColors.warmOffWhite,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusInput),
                ),
              ),
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now(),
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (date != null) {
                  dateCtrl.text = '${date.day}/${date.month}/${date.year}';
                }
              },
            ),
            const SizedBox(height: AppConstants.spacing16),
            TextField(
              controller: amtCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: InputFormatters.decimalAmount,
              decoration: InputDecoration(
                labelText: 'Montant (HTG)',
                prefixText: 'HTG ',
                filled: true,
                fillColor: isDark
                    ? AppColors.darkBackground
                    : AppColors.warmOffWhite,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusInput),
                ),
              ),
            ),
            const SizedBox(height: AppConstants.spacing24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: isDark ? AppColors.coolGray : AppColors.darkGray,
                      ),
                    ),
                    child: const Text('Annuler'),
                  ),
                ),
                const SizedBox(width: AppConstants.spacing12),
                Expanded(
                  flex: 2,
                  child: AppButton(
                    label: 'Ajouter une échéance',
                    onPressed: () {
                      final amount = double.tryParse(amtCtrl.text) ?? 0;
                      if (amount <= 0) return;
                      DateTime? date;
                      final parts = dateCtrl.text.trim().split('/');
                      if (parts.length == 3) {
                        final d = int.tryParse(parts[0]);
                        final m = int.tryParse(parts[1]);
                        final y = int.tryParse(parts[2]);
                        if (d != null && m != null && y != null) {
                          date = DateTime(y, m, d);
                        }
                      }
                      date ??= DateTime.now().add(const Duration(days: 7));
                      ref
                          .read(customerProvider.notifier)
                          .addSchedule(
                            customerId: c.id,
                            scheduledDate: date,
                            amountHtg: amount,
                          );
                      Navigator.pop(context);
                    },
                    icon: Icons.calendar_today_outlined,
                    fullWidth: true,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _dateStr(DateTime dt) => '${dt.day}/${dt.month}/${dt.year}';
}

// ─── Hotel Section ───────────────────────────────────────────────────────────

class _HotelSection extends StatelessWidget {
  final String customerId;
  final bool isDark;

  const _HotelSection({required this.customerId, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final stays = mockHotelStaysByCustomerId[customerId];
    if (stays == null || stays.isEmpty) {
      return AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  Icons.hotel_outlined,
                  size: 20,
                  color: isDark ? AppColors.skyBlue : AppColors.primaryBlue,
                ),
                const SizedBox(width: 8),
                Text(
                  'Hôtel',
                  style: AppTextStyles.h2(
                    color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppConstants.spacing12),
            Text(
              'Aucun séjour',
              style: AppTextStyles.body(
                color: isDark ? AppColors.coolGray : AppColors.darkGray,
              ),
            ),
          ],
        ),
      );
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                Icons.hotel_outlined,
                size: 20,
                color: isDark ? AppColors.skyBlue : AppColors.primaryBlue,
              ),
              const SizedBox(width: 8),
              Text(
                'Hôtel',
                style: AppTextStyles.h2(
                  color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spacing16),
          for (final stay in stays) ...[
            _HotelStayRow(stay: stay, isDark: isDark),
            if (stay != stays.last)
              const Divider(height: AppConstants.spacing24),
          ],
        ],
      ),
    );
  }
}

class _HotelStayRow extends StatelessWidget {
  final MockHotelStay stay;
  final bool isDark;

  const _HotelStayRow({required this.stay, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(
              Icons.meeting_room_outlined,
              size: 16,
              color: isDark ? AppColors.coolGray : AppColors.darkGray,
            ),
            const SizedBox(width: 6),
            Text(
              stay.roomName,
              style: AppTextStyles.body(
                color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
              ).copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: AppConstants.spacing8),
        Text(
          '${stay.totalGuests} client${stay.totalGuests > 1 ? 's' : ''} · ${stay.totalDays} jour${stay.totalDays > 1 ? 's' : ''}',
          style: AppTextStyles.caption(
            color: isDark ? AppColors.coolGray : AppColors.darkGray,
          ),
        ),
        const SizedBox(height: AppConstants.spacing8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Montant',
              style: AppTextStyles.caption(
                color: isDark ? AppColors.coolGray : AppColors.darkGray,
              ),
            ),
            Text(
              '${CurrencyFormatter.local(context, stay.amountHtg)} / \$${stay.amountUsd.toStringAsFixed(0)}',
              style: AppTextStyles.body(
                color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
              ),
            ),
          ],
        ),
        if (stay.paidHtg > 0) ...[
          const SizedBox(height: AppConstants.spacing4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Payé',
                style: AppTextStyles.caption(
                  color: isDark ? AppColors.coolGray : AppColors.darkGray,
                ),
              ),
              Text(
                CurrencyFormatter.local(context, stay.paidHtg),
                style: AppTextStyles.body(color: AppColors.deepGreen),
              ),
            ],
          ),
        ],
        if (stay.balanceHtg > 0) ...[
          const SizedBox(height: AppConstants.spacing4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Solde',
                style: AppTextStyles.caption(
                  color: isDark ? AppColors.coolGray : AppColors.darkGray,
                ),
              ),
              Text(
                CurrencyFormatter.local(context, stay.balanceHtg),
                style: AppTextStyles.body(
                  color: AppColors.boldRed,
                ).copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

// ─── Transaction Row ──────────────────────────────────────────────────────────

class _TransactionRow extends StatelessWidget {
  final CustomerTransaction tx;
  final bool isDark;

  const _TransactionRow({required this.tx, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final isCharge = tx.type == CustomerTransactionType.charge;
    final isPayment = tx.type == CustomerTransactionType.payment;
    final isAdjustment = tx.type == CustomerTransactionType.adjustment;
    final color = isPayment
        ? AppColors.deepGreen
        : isCharge
        ? AppColors.boldRed
        : AppColors.amber;
    final icon = isPayment
        ? Icons.arrow_downward_rounded
        : isCharge
        ? Icons.receipt_long_outlined
        : Icons.tune_outlined;

    final amountStr = isPayment
        ? '-${CurrencyFormatter.local(context, tx.amountHtg)}'
        : isAdjustment
        ? '${tx.amountHtg >= 0 ? '+' : ''}${CurrencyFormatter.local(context, tx.amountHtg)}'
        : '+${CurrencyFormatter.local(context, tx.creditedHtg)}';

    final metaParts = <String>[
      if (tx.linkedTableName != null) tx.linkedTableName!,
      if (tx.serverName != null) tx.serverName!,
      _dateStr(tx.timestamp),
      'By ${tx.cashierName}',
    ];

    return Container(
      color: isAdjustment
          ? AppColors.amber.withValues(alpha: 0.12)
          : Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tx.description,
                    style: AppTextStyles.body(
                      color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
                    ).copyWith(fontWeight: FontWeight.w500),
                  ),
                  Text(metaParts.join(' · '), style: AppTextStyles.caption()),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  amountStr,
                  style: AppTextStyles.body(
                    color: color,
                  ).copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  'Bal: ${CurrencyFormatter.local(context, tx.balanceAfterHtg)}',
                  style: AppTextStyles.caption(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _dateStr(DateTime dt) => '${dt.day}/${dt.month}/${dt.year}';
}

// ─── Adjustment Option Chip ───────────────────────────────────────────────────

class _AdjustmentOptionChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;

  const _AdjustmentOptionChip({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppConstants.radiusInput),
        child: Container(
          padding: const EdgeInsets.symmetric(
            vertical: AppConstants.spacing12,
            horizontal: AppConstants.spacing12,
          ),
          decoration: BoxDecoration(
            color: isSelected
                ? (isDark
                      ? AppColors.skyBlue.withValues(alpha: 0.2)
                      : AppColors.primaryBlue.withValues(alpha: 0.12))
                : (isDark ? AppColors.darkBackground : AppColors.warmOffWhite),
            borderRadius: BorderRadius.circular(AppConstants.radiusInput),
            border: Border.all(
              color: isSelected
                  ? (isDark ? AppColors.skyBlue : AppColors.primaryBlue)
                  : (isDark ? AppColors.coolGray : AppColors.darkGray)
                        .withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: isSelected
                    ? (isDark ? AppColors.skyBlue : AppColors.primaryBlue)
                    : (isDark ? AppColors.coolGray : AppColors.darkGray),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style:
                      AppTextStyles.body(
                        color: isSelected
                            ? (isDark
                                  ? AppColors.skyBlue
                                  : AppColors.primaryBlue)
                            : (isDark
                                  ? AppColors.warmWhite
                                  : AppColors.nearBlack),
                      ).copyWith(
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Notes Section ─────────────────────────────────────────────────────────────

class _NotesSection extends StatelessWidget {
  final bool isDark;
  final bool isExpanded;
  final VoidCallback onToggle;
  final VoidCallback onAddNote;
  final List<CustomerNote> notes;

  const _NotesSection({
    required this.isDark,
    required this.isExpanded,
    required this.onToggle,
    required this.onAddNote,
    required this.notes,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InkWell(
                onTap: onToggle,
                borderRadius: BorderRadius.circular(AppConstants.radiusCard),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 6,
                    horizontal: 4,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isExpanded ? Icons.expand_less : Icons.expand_more,
                        size: 20,
                        color: isDark ? AppColors.coolGray : AppColors.darkGray,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Notes',
                        style: AppTextStyles.body(
                          color: isDark
                              ? AppColors.warmWhite
                              : AppColors.nearBlack,
                        ).copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 6),
                      Text('(${notes.length})', style: AppTextStyles.caption()),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: onAddNote,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Ajouter une note'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          if (isExpanded) ...[
            const Divider(height: 1),
            if (notes.isEmpty)
              Padding(
                padding: const EdgeInsets.all(AppConstants.spacing16),
                child: Text(
                  'Aucune note pour le moment.',
                  style: AppTextStyles.body(
                    color: isDark ? AppColors.coolGray : AppColors.darkGray,
                  ),
                ),
              )
            else
              ...notes.reversed.map(
                (n) => Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(n.text, style: AppTextStyles.body()),
                      Text(
                        '${n.createdAt.day}/${n.createdAt.month}/${n.createdAt.year} · Par ${n.createdBy}',
                        style: AppTextStyles.caption(),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// ─── Schedules Section ───────────────────────────────────────────────────────

class _SchedulesSection extends StatelessWidget {
  final bool isDark;
  final bool isExpanded;
  final VoidCallback onToggle;
  final VoidCallback onAddSchedule;
  final List<CustomerPaymentSchedule> schedules;

  const _SchedulesSection({
    required this.isDark,
    required this.isExpanded,
    required this.onToggle,
    required this.onAddSchedule,
    required this.schedules,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InkWell(
                onTap: onToggle,
                borderRadius: BorderRadius.circular(AppConstants.radiusCard),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 6,
                    horizontal: 4,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isExpanded ? Icons.expand_less : Icons.expand_more,
                        size: 20,
                        color: isDark ? AppColors.coolGray : AppColors.darkGray,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Échéanciers',
                        style: AppTextStyles.body(
                          color: isDark
                              ? AppColors.warmWhite
                              : AppColors.nearBlack,
                        ).copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '(${schedules.length})',
                        style: AppTextStyles.caption(),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: onAddSchedule,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Ajouter une échéance'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          if (isExpanded) ...[
            const Divider(height: 1),
            if (schedules.isEmpty)
              Padding(
                padding: const EdgeInsets.all(AppConstants.spacing16),
                child: Text(
                  'Aucun échéancier de paiement.',
                  style: AppTextStyles.body(
                    color: isDark ? AppColors.coolGray : AppColors.darkGray,
                  ),
                ),
              )
            else
              ...schedules.map(
                (s) => Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 0,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.calendar_today_outlined,
                        size: 16,
                        color: isDark ? AppColors.coolGray : AppColors.darkGray,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${s.scheduledDate.day}/${s.scheduledDate.month}/${s.scheduledDate.year}',
                        style: AppTextStyles.body(),
                      ),
                      const Spacer(),
                      Text(
                        CurrencyFormatter.local(context, s.amountHtg),
                        style: AppTextStyles.body(
                          color: isDark
                              ? AppColors.skyBlue
                              : AppColors.primaryBlue,
                        ).copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// ─── Stat Card ────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool isDark;

  const _StatCard({
    required this.label,
    required this.value,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppTextStyles.caption()),
            const SizedBox(height: 4),
            Text(
              value,
              style: AppTextStyles.body(
                color: color,
              ).copyWith(fontWeight: FontWeight.w700, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
