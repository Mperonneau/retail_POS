import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/paylink.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../utils/constants.dart';
import '../../utils/currency_formatter.dart';
import '../../widgets/app_bottom_sheet.dart';

// ─── Entry ────────────────────────────────────────────────────────────────────

Future<void> showPayLinkDetail(
  BuildContext context, {
  required PayLink link,
  required StateNotifierProvider<PayLinkNotifier, PayLinkState> payLinkProvider,
}) {
  return showAppBottomSheet(
    context: context,
    child: _PayLinkDetailSheet(
      link: link,
      payLinkProvider: payLinkProvider,
    ),
  );
}

// ─── Sheet ────────────────────────────────────────────────────────────────────

class _PayLinkDetailSheet extends ConsumerStatefulWidget {
  final PayLink link;
  final StateNotifierProvider<PayLinkNotifier, PayLinkState> payLinkProvider;

  const _PayLinkDetailSheet({
    required this.link,
    required this.payLinkProvider,
  });

  @override
  ConsumerState<_PayLinkDetailSheet> createState() =>
      _PayLinkDetailSheetState();
}

class _PayLinkDetailSheetState extends ConsumerState<_PayLinkDetailSheet> {
  late PayLink _link;
  bool _editingContact = false;

  late final TextEditingController _phoneCtrl;
  late final TextEditingController _emailCtrl;
  late PayLinkChannel _editChannel;

  @override
  void initState() {
    super.initState();
    _link = widget.link;
    _phoneCtrl = TextEditingController(
        text: _link.channel != PayLinkChannel.email ? _link.sentTo : _link.customerPhone);
    _emailCtrl = TextEditingController(
        text: _link.payerEmail ?? (_link.channel == PayLinkChannel.email ? _link.sentTo : ''));
    _editChannel = _link.channel;
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  /// Re-read latest state (in case it was updated from the list).
  PayLink get _current {
    final s = ref.read(widget.payLinkProvider);
    return s.links.firstWhere((l) => l.id == _link.id, orElse: () => _link);
  }

  void _saveContact() {
    final sentTo = _editChannel == PayLinkChannel.email
        ? _emailCtrl.text.trim()
        : _phoneCtrl.text.trim();
    if (sentTo.isEmpty) return;
    ref.read(widget.payLinkProvider.notifier).updateContact(
          _link.id,
          sentTo: sentTo,
          channel: _editChannel,
          payerEmail: _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
        );
    setState(() {
      _link = _current.copyWith(
        sentTo: sentTo,
        channel: _editChannel,
        payerEmail: _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
      );
      _editingContact = false;
    });
  }

  void _cancel(BuildContext ctx) {
    _showConfirmModal(
      ctx,
      title: 'Cancel this paylink?',
      message:
          'The payer will no longer be able to use this link. This action cannot be undone.',
      confirmLabel: 'Cancel Link',
      confirmColor: AppColors.boldRed,
      onConfirm: () {
        ref.read(widget.payLinkProvider.notifier).cancel(_link.id);
        Navigator.pop(ctx);
        _showSuccessModal(ctx, title: 'Link Canceled', message: 'The paylink has been canceled.');
      },
    );
  }

  void _resendFromSheet(BuildContext ctx) {
    final channel = _channelName(_link.channel);
    _showConfirmModal(
      ctx,
      title: 'Resend paylink?',
      message: 'Re-send the link to ${_link.sentTo} via $channel?',
      confirmLabel: 'Resend',
      confirmColor: AppColors.primaryBlue,
      onConfirm: () {
        Navigator.pop(ctx);
        _showSuccessModal(
          ctx,
          title: 'Link Resent',
          message: 'Paylink resent to ${_link.sentTo} via $channel.',
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppColors.warmWhite : AppColors.nearBlack;
    final mutedColor = isDark ? AppColors.coolGray : AppColors.darkGray;
    final surface = isDark ? AppColors.darkSurface : AppColors.white;
    final divColor = isDark ? AppColors.darkBorder : const Color(0xFFEEEEEE);

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        24, 0, 24, 24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header chip ───────────────────────────────────────────────────
          _SheetHeader(link: _link, isDark: isDark, textColor: textColor, mutedColor: mutedColor),
          const SizedBox(height: 20),

          // ── Amount block ──────────────────────────────────────────────────
          _AmountBlock(link: _link, isDark: isDark, surface: surface, textColor: textColor, mutedColor: mutedColor),
          const SizedBox(height: 20),

          // ── Status-specific sections ──────────────────────────────────────
          if (_link.status == PayLinkStatus.active)
            _ActiveSection(
              link: _link,
              isDark: isDark,
              textColor: textColor,
              mutedColor: mutedColor,
              surface: surface,
              divColor: divColor,
              editing: _editingContact,
              phoneCtrl: _phoneCtrl,
              emailCtrl: _emailCtrl,
              editChannel: _editChannel,
              onEditToggle: () => setState(() => _editingContact = !_editingContact),
              onChannelChanged: (c) => setState(() => _editChannel = c),
              onSaveContact: _saveContact,
              onResend: () => _resendFromSheet(context),
              onCancel: () => _cancel(context),
            ),

          if (_link.status == PayLinkStatus.paidUnused)
            _PaidSection(
              link: _link,
              isDark: isDark,
              textColor: textColor,
              mutedColor: mutedColor,
              surface: surface,
              divColor: divColor,
            ),

          if (_link.status == PayLinkStatus.inactive)
            _InactiveSection(
              link: _link,
              isDark: isDark,
              textColor: textColor,
              mutedColor: mutedColor,
              surface: surface,
            ),

          if (_link.note != null && _link.note!.isNotEmpty) ...[
            const SizedBox(height: 16),
            _NoteBox(note: _link.note!, isDark: isDark, mutedColor: mutedColor),
          ],
        ],
      ),
    );
  }
}

// ─── Sheet header ─────────────────────────────────────────────────────────────

class _SheetHeader extends StatelessWidget {
  final PayLink link;
  final bool isDark;
  final Color textColor;
  final Color mutedColor;

  const _SheetHeader({
    required this.link,
    required this.isDark,
    required this.textColor,
    required this.mutedColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                link.customerName,
                style: AppTextStyles.h2(color: textColor),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _StatusPill(status: link.status),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${link.reference}  ·  ${link.customerPhone}',
          style: AppTextStyles.caption(color: mutedColor),
        ),
      ],
    );
  }
}

// ─── Amount block ─────────────────────────────────────────────────────────────

class _AmountBlock extends StatelessWidget {
  final PayLink link;
  final bool isDark;
  final Color surface;
  final Color textColor;
  final Color mutedColor;

  const _AmountBlock({
    required this.link,
    required this.isDark,
    required this.surface,
    required this.textColor,
    required this.mutedColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkBackground : const Color(0xFFF5F7FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : const Color(0xFFE4E7EC),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Total Amount',
                    style: AppTextStyles.caption(color: mutedColor)
                        .copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(
                  CurrencyFormatter.local(context, link.amountHtg),
                  style: AppTextStyles.price(color: textColor)
                      .copyWith(fontSize: 22),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Active section ───────────────────────────────────────────────────────────

class _ActiveSection extends StatelessWidget {
  final PayLink link;
  final bool isDark;
  final Color textColor;
  final Color mutedColor;
  final Color surface;
  final Color divColor;
  final bool editing;
  final TextEditingController phoneCtrl;
  final TextEditingController emailCtrl;
  final PayLinkChannel editChannel;
  final VoidCallback onEditToggle;
  final void Function(PayLinkChannel) onChannelChanged;
  final VoidCallback onSaveContact;
  final VoidCallback onResend;
  final VoidCallback onCancel;

  const _ActiveSection({
    required this.link,
    required this.isDark,
    required this.textColor,
    required this.mutedColor,
    required this.surface,
    required this.divColor,
    required this.editing,
    required this.phoneCtrl,
    required this.emailCtrl,
    required this.editChannel,
    required this.onEditToggle,
    required this.onChannelChanged,
    required this.onSaveContact,
    required this.onResend,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel('LINK DETAILS', mutedColor: mutedColor),
        const SizedBox(height: 10),
        _InfoRow(
          icon: Icons.access_time_rounded,
          label: 'Sent',
          value: _formatDateTime(link.createdAt),
          mutedColor: mutedColor,
          textColor: textColor,
        ),
        const SizedBox(height: 8),
        _InfoRow(
          icon: _channelIcon(link.channel),
          label: 'Channel',
          value: _channelName(link.channel),
          mutedColor: mutedColor,
          textColor: textColor,
        ),
        const SizedBox(height: 8),
        _InfoRow(
          icon: Icons.send_rounded,
          label: 'Sent to',
          value: link.sentTo,
          mutedColor: mutedColor,
          textColor: textColor,
        ),
        if (link.payerEmail != null && link.payerEmail!.isNotEmpty &&
            link.channel != PayLinkChannel.email) ...[
          const SizedBox(height: 8),
          _InfoRow(
            icon: Icons.email_outlined,
            label: 'Email',
            value: link.payerEmail!,
            mutedColor: mutedColor,
            textColor: textColor,
          ),
        ],
        if (link.expiresAt != null) ...[
          const SizedBox(height: 8),
          _InfoRow(
            icon: Icons.event_outlined,
            label: 'Expires',
            value: _formatDate(link.expiresAt!),
            mutedColor: mutedColor,
            textColor: textColor,
            valueColor: link.isExpired ? AppColors.boldRed : null,
          ),
        ],

        const SizedBox(height: 20),
        Divider(height: 1, color: divColor),
        const SizedBox(height: 16),

        // ── Editable contact ──────────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: Text('PAYER CONTACT',
                  style: AppTextStyles.caption(color: mutedColor)
                      .copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.6, fontSize: 10)),
            ),
            GestureDetector(
              onTap: onEditToggle,
              child: Text(
                editing ? 'Cancel edit' : 'Edit',
                style: AppTextStyles.caption(
                    color: isDark ? AppColors.skyBlue : AppColors.primaryBlue)
                    .copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        if (!editing) ...[
          _InfoRow(
            icon: Icons.phone_outlined,
            label: 'Phone',
            value: phoneCtrl.text.isEmpty ? '—' : phoneCtrl.text,
            mutedColor: mutedColor,
            textColor: textColor,
          ),
          if (emailCtrl.text.isNotEmpty) ...[
            const SizedBox(height: 8),
            _InfoRow(
              icon: Icons.email_outlined,
              label: 'Email',
              value: emailCtrl.text,
              mutedColor: mutedColor,
              textColor: textColor,
            ),
          ],
        ] else ...[
          _EditableContactFields(
            isDark: isDark,
            phoneCtrl: phoneCtrl,
            emailCtrl: emailCtrl,
            channel: editChannel,
            onChannelChanged: onChannelChanged,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onSaveContact,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                foregroundColor: AppColors.white,
                minimumSize: const Size(double.infinity, 46),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Save & Update',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],

        const SizedBox(height: 20),
        Divider(height: 1, color: divColor),
        const SizedBox(height: 16),

        // ── Action buttons ────────────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onResend,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Resend Link'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: isDark ? AppColors.skyBlue : AppColors.primaryBlue,
                  minimumSize: const Size(0, 46),
                  side: BorderSide(
                    color: (isDark ? AppColors.skyBlue : AppColors.primaryBlue)
                        .withValues(alpha: 0.5),
                  ),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onCancel,
                icon: const Icon(Icons.cancel_outlined, size: 16),
                label: const Text('Cancel Link'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.boldRed,
                  minimumSize: const Size(0, 46),
                  side: BorderSide(
                      color: AppColors.boldRed.withValues(alpha: 0.45)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─── Paid section ─────────────────────────────────────────────────────────────

class _PaidSection extends StatelessWidget {
  final PayLink link;
  final bool isDark;
  final Color textColor;
  final Color mutedColor;
  final Color surface;
  final Color divColor;

  const _PaidSection({
    required this.link,
    required this.isDark,
    required this.textColor,
    required this.mutedColor,
    required this.surface,
    required this.divColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel('PAYMENT CONFIRMATION', mutedColor: mutedColor),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.deepGreen.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.deepGreen.withValues(alpha: 0.25)),
          ),
          child: Column(
            children: [
              _InfoRow(
                icon: Icons.check_circle_rounded,
                label: 'Status',
                value: 'Payment received',
                mutedColor: mutedColor,
                textColor: AppColors.deepGreen,
                valueColor: AppColors.deepGreen,
              ),
              if (link.paidAt != null) ...[
                const SizedBox(height: 8),
                _InfoRow(
                  icon: Icons.event_rounded,
                  label: 'Paid on',
                  value: _formatDateTime(link.paidAt!),
                  mutedColor: mutedColor,
                  textColor: textColor,
                ),
              ],
              if (link.paymentTransactionId != null) ...[
                const SizedBox(height: 8),
                _InfoRow(
                  icon: Icons.receipt_rounded,
                  label: 'Transaction ID',
                  value: link.paymentTransactionId!,
                  mutedColor: mutedColor,
                  textColor: textColor,
                ),
              ],
              if (link.paymentLast4 != null) ...[
                const SizedBox(height: 8),
                _InfoRow(
                  icon: Icons.credit_card_rounded,
                  label: 'Last 4 digits',
                  value: '•••• ${link.paymentLast4}',
                  mutedColor: mutedColor,
                  textColor: textColor,
                ),
              ],
              if (link.paymentMethod != null) ...[
                const SizedBox(height: 8),
                _InfoRow(
                  icon: Icons.payments_outlined,
                  label: 'Method',
                  value: link.paymentMethod!,
                  mutedColor: mutedColor,
                  textColor: textColor,
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 16),
        // Credit notice
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.deepGreen.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.deepGreen.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              const Icon(Icons.account_balance_wallet_outlined,
                  size: 15, color: AppColors.deepGreen),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Amount credited to client\'s store balance.',
                  style: AppTextStyles.caption(color: AppColors.deepGreen)
                      .copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),
        _SectionLabel('SENT TO', mutedColor: mutedColor),
        const SizedBox(height: 8),
        _InfoRow(
          icon: _channelIcon(link.channel),
          label: _channelName(link.channel),
          value: link.sentTo,
          mutedColor: mutedColor,
          textColor: textColor,
        ),
      ],
    );
  }
}

// ─── Inactive section ─────────────────────────────────────────────────────────

class _InactiveSection extends StatelessWidget {
  final PayLink link;
  final bool isDark;
  final Color textColor;
  final Color mutedColor;
  final Color surface;

  const _InactiveSection({
    required this.link,
    required this.isDark,
    required this.textColor,
    required this.mutedColor,
    required this.surface,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel('CANCELLATION', mutedColor: mutedColor),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.boldRed.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.boldRed.withValues(alpha: 0.2)),
          ),
          child: Column(
            children: [
              if (link.canceledAt != null)
                _InfoRow(icon: Icons.cancel_outlined, label: 'Canceled on',
                    value: _formatDateTime(link.canceledAt!), mutedColor: mutedColor,
                    textColor: textColor, valueColor: AppColors.boldRed),
              if (link.canceledBy != null) ...[
                const SizedBox(height: 8),
                _InfoRow(icon: Icons.person_outline_rounded, label: 'Canceled by',
                    value: link.canceledBy!, mutedColor: mutedColor, textColor: textColor),
              ],
              if (link.isExpired) ...[
                const SizedBox(height: 8),
                _InfoRow(icon: Icons.event_outlined, label: 'Expired on',
                    value: _formatDate(link.expiresAt!), mutedColor: mutedColor,
                    textColor: textColor, valueColor: AppColors.amber),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        _SectionLabel('ORIGINAL LINK', mutedColor: mutedColor),
        const SizedBox(height: 8),
        _InfoRow(icon: Icons.access_time_rounded, label: 'Created',
            value: _formatDateTime(link.createdAt), mutedColor: mutedColor, textColor: textColor),
        const SizedBox(height: 8),
        _InfoRow(icon: _channelIcon(link.channel), label: 'Was sent to',
            value: link.sentTo, mutedColor: mutedColor, textColor: textColor),
      ],
    );
  }
}

// ─── Editable contact fields ──────────────────────────────────────────────────

class _EditableContactFields extends StatelessWidget {
  final bool isDark;
  final TextEditingController phoneCtrl;
  final TextEditingController emailCtrl;
  final PayLinkChannel channel;
  final void Function(PayLinkChannel) onChannelChanged;

  const _EditableContactFields({
    required this.isDark,
    required this.phoneCtrl,
    required this.emailCtrl,
    required this.channel,
    required this.onChannelChanged,
  });

  InputDecoration _dec(String label, IconData icon) => InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 18),
        filled: true,
        fillColor: isDark ? AppColors.darkSurface : AppColors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: isDark ? AppColors.darkBorder : const Color(0xFFD0D5DD))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: isDark ? AppColors.darkBorder : const Color(0xFFD0D5DD))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.primaryBlue, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        isDense: true,
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: phoneCtrl,
          keyboardType: TextInputType.phone,
          decoration: _dec('Phone number', Icons.phone_outlined),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: emailCtrl,
          keyboardType: TextInputType.emailAddress,
          decoration: _dec('Email address (optional)', Icons.email_outlined),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _MiniChannelChip(
              label: 'WhatsApp',
              icon: Icons.chat_rounded,
              color: const Color(0xFF25D366),
              selected: channel == PayLinkChannel.whatsApp,
              onTap: () => onChannelChanged(PayLinkChannel.whatsApp),
            ),
            const SizedBox(width: 6),
            _MiniChannelChip(
              label: 'Email',
              icon: Icons.email_outlined,
              color: AppColors.primaryBlue,
              selected: channel == PayLinkChannel.email,
              onTap: () => onChannelChanged(PayLinkChannel.email),
            ),
            const SizedBox(width: 6),
            _MiniChannelChip(
              label: 'SMS',
              icon: Icons.sms_outlined,
              color: AppColors.amber,
              selected: channel == PayLinkChannel.sms,
              onTap: () => onChannelChanged(PayLinkChannel.sms),
            ),
          ],
        ),
      ],
    );
  }
}

class _MiniChannelChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _MiniChannelChip({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppConstants.animFast,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? color : const Color(0xFFD0D5DD),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: selected ? color : AppColors.coolGray),
            const SizedBox(width: 4),
            Text(label,
                style: AppTextStyles.caption(
                    color: selected ? color : AppColors.coolGray)
                    .copyWith(fontWeight: FontWeight.w600, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

// ─── Shared sub-widgets ───────────────────────────────────────────────────────

class _StatusPill extends StatelessWidget {
  final PayLinkStatus status;
  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      PayLinkStatus.active     => (AppColors.amber, 'Active'),
      PayLinkStatus.paidUnused => (AppColors.deepGreen, 'Paid'),
      PayLinkStatus.inactive   => (AppColors.coolGray, 'Inactive'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(label,
          style: AppTextStyles.caption(color: color)
              .copyWith(fontWeight: FontWeight.w700, fontSize: 11)),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final Color mutedColor;
  const _SectionLabel(this.text, {required this.mutedColor});

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: AppTextStyles.caption(color: mutedColor)
            .copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.7, fontSize: 10));
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color mutedColor;
  final Color textColor;
  final Color? valueColor;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.mutedColor,
    required this.textColor,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: mutedColor),
        const SizedBox(width: 8),
        SizedBox(
          width: 90,
          child: Text(label,
              style: AppTextStyles.caption(color: mutedColor)
                  .copyWith(fontWeight: FontWeight.w600)),
        ),
        Expanded(
          child: Text(value,
              style: AppTextStyles.body(color: valueColor ?? textColor)
                  .copyWith(fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

class _NoteBox extends StatelessWidget {
  final String note;
  final bool isDark;
  final Color mutedColor;

  const _NoteBox({required this.note, required this.isDark, required this.mutedColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkBackground : const Color(0xFFF5F7FA),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.sticky_note_2_outlined, size: 14, color: mutedColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(note,
                style: AppTextStyles.caption(color: mutedColor).copyWith(height: 1.4)),
          ),
        ],
      ),
    );
  }
}

// ─── Modals ───────────────────────────────────────────────────────────────────

void _showConfirmModal(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  required Color confirmColor,
  required VoidCallback onConfirm,
}) {
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: AppTextStyles.h3(color: null)),
      content: Text(message, style: AppTextStyles.body()),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Keep'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(ctx);
            onConfirm();
          },
          style: FilledButton.styleFrom(
            backgroundColor: confirmColor,
            foregroundColor: AppColors.white,
            minimumSize: const Size(0, 40),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
}

void _showSuccessModal(
  BuildContext context, {
  required String title,
  required String message,
}) {
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.deepGreen.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.check_circle_rounded,
                color: AppColors.deepGreen, size: 20),
          ),
          const SizedBox(width: 10),
          Text(title, style: AppTextStyles.h3(color: null)),
        ],
      ),
      content: Text(message, style: AppTextStyles.body()),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.deepGreen,
            foregroundColor: AppColors.white,
            minimumSize: const Size(0, 40),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

String _channelName(PayLinkChannel c) => switch (c) {
      PayLinkChannel.whatsApp => 'WhatsApp',
      PayLinkChannel.email    => 'Email',
      PayLinkChannel.sms      => 'SMS',
    };

IconData _channelIcon(PayLinkChannel c) => switch (c) {
      PayLinkChannel.whatsApp => Icons.chat_rounded,
      PayLinkChannel.email    => Icons.email_outlined,
      PayLinkChannel.sms      => Icons.sms_outlined,
    };

String _formatDate(DateTime d) {
  final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}

String _formatDateTime(DateTime d) {
  final h = d.hour.toString().padLeft(2, '0');
  final m = d.minute.toString().padLeft(2, '0');
  return '${_formatDate(d)} at $h:$m';
}
