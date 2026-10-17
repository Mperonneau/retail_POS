import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../mock/mock_reservation_data.dart';
import '../../theme/app_colors.dart';
import '../../utils/constants.dart';
import '../../utils/currency_formatter.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Pre-order table — each item is a subtle card, notes toggled inline.
// ─────────────────────────────────────────────────────────────────────────────

class ReservationPreOrderTable extends StatelessWidget {
  const ReservationPreOrderTable({
    super.key,
    required this.items,
    required this.canEdit,
    required this.isDark,
    required this.primary,
    required this.onRemove,
    required this.onIncrementQty,
    required this.onDecrementQty,
    required this.onCatalogNoteChanged,
    required this.onCustomNoteChanged,
    required this.onCustomFoodChanged,
    required this.onEditCustomPrice,
    required this.onEditCustom,
  });

  final List<MockDiningReservationPreOrderItem> items;
  final bool canEdit;
  final bool isDark;
  final Color primary;
  final void Function(int index) onRemove;
  final void Function(int index) onIncrementQty;
  final void Function(int index) onDecrementQty;
  final void Function(int index, String? note) onCatalogNoteChanged;
  final void Function(int index, String? note) onCustomNoteChanged;
  final void Function(int index, bool isFood) onCustomFoodChanged;
  final void Function(int index) onEditCustomPrice;
  final void Function(int index) onEditCustom;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: EdgeInsets.only(
                bottom: i < items.length - 1 ? AppConstants.spacing4 : 0),
            child: _ItemCard(
              key: ValueKey('pre-$i-${items[i].isCustom}'),
              item: items[i],
              index: i,
              canEdit: canEdit,
              isDark: isDark,
              primary: primary,
              onRemove: onRemove,
              onIncrementQty: onIncrementQty,
              onDecrementQty: onDecrementQty,
              onNoteChanged: items[i].isCustom
                  ? onCustomNoteChanged
                  : onCatalogNoteChanged,
              onCustomFoodChanged: onCustomFoodChanged,
              onEditCustomPrice: onEditCustomPrice,
              onEditCustom: onEditCustom,
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Single item card
// ─────────────────────────────────────────────────────────────────────────────

class _ItemCard extends StatefulWidget {
  const _ItemCard({
    super.key,
    required this.item,
    required this.index,
    required this.canEdit,
    required this.isDark,
    required this.primary,
    required this.onRemove,
    required this.onIncrementQty,
    required this.onDecrementQty,
    required this.onNoteChanged,
    required this.onCustomFoodChanged,
    required this.onEditCustomPrice,
    required this.onEditCustom,
  });

  final MockDiningReservationPreOrderItem item;
  final int index;
  final bool canEdit;
  final bool isDark;
  final Color primary;
  final void Function(int) onRemove;
  final void Function(int) onIncrementQty;
  final void Function(int) onDecrementQty;
  final void Function(int, String?) onNoteChanged;
  final void Function(int, bool) onCustomFoodChanged;
  final void Function(int) onEditCustomPrice;
  final void Function(int) onEditCustom;

  @override
  State<_ItemCard> createState() => _ItemCardState();
}

class _ItemCardState extends State<_ItemCard> {
  bool _noteOpen = false;
  late TextEditingController _noteCtrl;

  @override
  void initState() {
    super.initState();
    final note = _currentNote;
    _noteCtrl = TextEditingController(text: note ?? '');
    if (note != null && note.trim().isNotEmpty) _noteOpen = true;
  }

  @override
  void didUpdateWidget(covariant _ItemCard old) {
    super.didUpdateWidget(old);
    final note = _currentNote ?? '';
    if (note != _noteCtrl.text) _noteCtrl.text = note;
    if (note.trim().isNotEmpty && !_noteOpen) {
      setState(() => _noteOpen = true);
    }
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  String? get _currentNote => widget.item.isCustom
      ? widget.item.customItem?.note
      : widget.item.catalogItem?.note;

  void _commitNote() {
    final v = _noteCtrl.text.trim();
    widget.onNoteChanged(widget.index, v.isEmpty ? null : v);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final isCustom = widget.item.isCustom;
    final ci = widget.item.customItem;
    final cat = widget.item.catalogItem;
    final name = isCustom ? ci!.name : cat!.name;
    final qty = isCustom ? ci!.quantity : cat!.quantity;
    final price = isCustom ? ci!.priceHtg : cat!.priceHtg;
    final hasNote = (_currentNote ?? '').trim().isNotEmpty;
    final canEdit = widget.canEdit;

    final cardBg = isDark
        ? Colors.white.withValues(alpha: 0.035)
        : Colors.black.withValues(alpha: 0.022);
    final border = isDark
        ? AppColors.darkBorder.withValues(alpha: 0.55)
        : const Color(0xFFE2E2EA);
    final textPrimary = isDark ? AppColors.warmWhite : AppColors.nearBlack;
    final muted = isDark ? AppColors.coolGray : AppColors.darkGray;

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Main row ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 5, 4, 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Leading icon
                Icon(
                  isCustom ? Icons.edit_note : Icons.restaurant_menu,
                  size: 14,
                  color: isCustom
                      ? AppColors.amber
                      : widget.primary.withValues(alpha: 0.85),
                ),
                const SizedBox(width: 6),

                // Name
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Poppins',
                    ).copyWith(color: textPrimary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

                // Kitchen sent dot
                if (widget.item.kitchenSent) ...[
                  const SizedBox(width: 4),
                  Tooltip(
                    message: 'Envoyé en cuisine',
                    child: Icon(Icons.check_circle,
                        size: 12, color: AppColors.deepGreen),
                  ),
                ],

                const SizedBox(width: 6),

                // Qty  − n +
                _QtyControl(
                  qty: qty,
                  enabled: canEdit,
                  primary: widget.primary,
                  textColor: textPrimary,
                  onMinus: () => widget.onDecrementQty(widget.index),
                  onPlus: () => widget.onIncrementQty(widget.index),
                ),

                const SizedBox(width: 6),

                // Price
                isCustom && canEdit
                    ? GestureDetector(
                        onTap: () => widget.onEditCustomPrice(widget.index),
                        child: Text(
                          CurrencyFormatter.local(context, price),
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.amber,
                            decoration: TextDecoration.underline,
                            decorationColor: AppColors.amber,
                            fontFamily: 'Poppins',
                          ),
                        ),
                      )
                    : Text(
                        CurrencyFormatter.local(context, price),
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: textPrimary,
                          fontFamily: 'Poppins',
                        ),
                      ),

                const SizedBox(width: 2),

                // Note toggle
                _IconTap(
                  onTap: () => setState(() => _noteOpen = !_noteOpen),
                  tooltip: hasNote ? 'Voir / modifier la note' : 'Ajouter une note',
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(
                        _noteOpen
                            ? Icons.speaker_notes
                            : Icons.speaker_notes_outlined,
                        size: 15,
                        color: hasNote ? widget.primary : muted,
                      ),
                      if (hasNote && !_noteOpen)
                        Positioned(
                          right: -1,
                          top: -1,
                          child: Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              color: widget.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                // Edit (custom only)
                if (isCustom && canEdit)
                  _IconTap(
                    onTap: () => widget.onEditCustom(widget.index),
                    tooltip: 'Modifier l\'article',
                    child: Icon(Icons.tune,
                        size: 14,
                        color: widget.primary.withValues(alpha: 0.75)),
                  ),

                // Delete
                if (canEdit)
                  _IconTap(
                    onTap: () => widget.onRemove(widget.index),
                    tooltip: 'Retirer',
                    child: const Icon(Icons.delete_outline,
                        size: 14, color: AppColors.error),
                  ),
              ],
            ),
          ),

          // ── Note row (collapsible) ────────────────────────────────────────
          AnimatedSize(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeInOut,
            child: _noteOpen
                ? Container(
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: border)),
                    ),
                    padding:
                        const EdgeInsets.fromLTRB(8, 5, 8, 6),
                    child: Row(
                      children: [
                        Icon(Icons.notes_outlined,
                            size: 12, color: muted),
                        const SizedBox(width: 4),
                        Expanded(
                          child: canEdit
                              ? TextField(
                                  controller: _noteCtrl,
                                  autofocus: false,
                                  maxLines: 1,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: textPrimary,
                                    fontFamily: 'Inter',
                                  ),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    hintText: 'p. ex. sans oignon, très épicé…',
                                    hintStyle: TextStyle(
                                        fontSize: 10.5, color: muted),
                                    contentPadding:
                                        const EdgeInsets.symmetric(
                                            horizontal: 0, vertical: 2),
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                  ),
                                  onEditingComplete: _commitNote,
                                  onSubmitted: (_) => _commitNote(),
                                )
                              : Text(
                                  _noteCtrl.text.trim().isEmpty
                                      ? '—'
                                      : _noteCtrl.text.trim(),
                                  style: TextStyle(
                                      fontSize: 10.5,
                                      color: muted,
                                      fontFamily: 'Inter'),
                                ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Micro helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Tight tappable icon with no extra padding waste.
class _IconTap extends StatelessWidget {
  const _IconTap({
    required this.child,
    required this.onTap,
    required this.tooltip,
  });

  final Widget child;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _QtyControl extends StatelessWidget {
  const _QtyControl({
    required this.qty,
    required this.enabled,
    required this.primary,
    required this.textColor,
    required this.onMinus,
    required this.onPlus,
  });

  final int qty;
  final bool enabled;
  final Color primary;
  final Color textColor;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    final dimmed = primary.withValues(alpha: 0.2);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Btn(
          icon: Icons.remove,
          color: enabled && qty > 1 ? primary : dimmed,
          onTap: enabled && qty > 1 ? onMinus : null,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5),
          child: Text(
            '$qty',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: textColor,
              fontFamily: 'Poppins',
            ),
          ),
        ),
        _Btn(
          icon: Icons.add,
          color: enabled ? primary : dimmed,
          onTap: enabled ? onPlus : null,
        ),
      ],
    );
  }
}

class _Btn extends StatelessWidget {
  const _Btn({required this.icon, required this.color, this.onTap});

  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 12, color: color),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Print
// ─────────────────────────────────────────────────────────────────────────────

Future<void> printReservationPreOrderSlip(
  BuildContext context, {
  required MockDiningReservation reservation,
}) async {
  final fmt = NumberFormat.currency(
    locale: 'en_HT',
    symbol: 'HTG ',
    decimalDigits: 2,
  );
  final when =
      DateFormat.yMMMd().add_jm().format(reservation.reservationAt);

  pw.Widget lineRow(MockDiningReservationPreOrderItem p) {
    final isCustom = p.isCustom;
    final name = isCustom ? p.customItem!.name : p.catalogItem!.name;
    final qty =
        isCustom ? p.customItem!.quantity : p.catalogItem!.quantity;
    final price =
        isCustom ? p.customItem!.priceHtg : p.catalogItem!.priceHtg;
    final rawNote = isCustom ? p.customItem?.note : p.catalogItem?.note;
    final note = (rawNote != null && rawNote.trim().isNotEmpty)
        ? rawNote
        : '—';
    final sub = isCustom
        ? 'Custom · ${p.customItem!.isFood ? "Cuisine" : "Boisson"}'
        : 'Menu · ${p.catalogItem!.category}';

    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            flex: 3,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(name,
                    style:
                        pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                pw.Text(sub,
                    style: const pw.TextStyle(fontSize: 9)),
              ],
            ),
          ),
          pw.SizedBox(
              width: 36,
              child: pw.Text('$qty',
                  textAlign: pw.TextAlign.center)),
          pw.SizedBox(
              width: 72,
              child: pw.Text(fmt.format(price),
                  textAlign: pw.TextAlign.right)),
          pw.Expanded(
              flex: 2,
              child: pw.Text(note,
                  style: const pw.TextStyle(fontSize: 9))),
        ],
      ),
    );
  }

  final doc = pw.Document();
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('Bon de précommande',
              style: pw.TextStyle(
                  fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.Text('Client : ${reservation.guestName}'),
          pw.Text('Téléphone : ${reservation.phone}'),
          pw.Text(
              'Réservation : $when · ${reservation.partySize} personnes'),
          if (reservation.specialNotes != null &&
              reservation.specialNotes!.trim().isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 6),
              child: pw.Text(
                  'Notes : ${reservation.specialNotes}'),
            ),
          pw.SizedBox(height: 16),
          pw.Container(
            padding: const pw.EdgeInsets.only(bottom: 6),
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                  bottom: pw.BorderSide(width: 0.5)),
            ),
            child: pw.Row(children: [
              pw.Expanded(
                  flex: 3,
                  child: pw.Text('Article',
                      style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold))),
              pw.SizedBox(
                  width: 36,
                  child: pw.Text('Qté',
                      style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold),
                      textAlign: pw.TextAlign.center)),
              pw.SizedBox(
                  width: 72,
                  child: pw.Text('Prix',
                      style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold),
                      textAlign: pw.TextAlign.right)),
              pw.Expanded(
                  flex: 2,
                  child: pw.Text('Note',
                      style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold))),
            ]),
          ),
          ...reservation.preOrderItems.map(lineRow),
          pw.Spacer(),
          pw.Text(
            'Printed ${DateFormat.yMMMd().add_jm().format(DateTime.now())}',
            style: const pw.TextStyle(
                fontSize: 9, color: PdfColors.grey700),
          ),
        ],
      ),
    ),
  );

  await Printing.layoutPdf(
      onLayout: (PdfPageFormat f) async => doc.save());
}
