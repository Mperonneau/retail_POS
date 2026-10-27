import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/models/cash_control.dart';
import '../../core/printing/pdf_theme.dart';
import '../../core/theme/app_colors.dart';

/// Print or download a cash PDF. Currencies are printed as stored:
/// gourdes stay gourdes, dollars stay dollars.
Future<void> showCashPdfActions(
  BuildContext context, {
  required String filename,
  required String title,
  required Future<Uint8List> Function() build,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      var busy = false;
      return StatefulBuilder(
        builder: (context, setLocal) {
          Future<void> run(bool print) async {
            if (busy) return;
            setLocal(() => busy = true);
            try {
              final bytes = await build();
              if (!ctx.mounted) return;
              if (print) {
                await Printing.layoutPdf(
                  onLayout: (_) async => bytes,
                  name: filename,
                );
              } else {
                await Printing.sharePdf(bytes: bytes, filename: filename);
              }
              if (ctx.mounted) Navigator.pop(ctx);
            } catch (_) {
              if (context.mounted) {
                setLocal(() => busy = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Impossible de créer le PDF.'),
                    backgroundColor: AppColors.boldRed,
                  ),
                );
              }
            }
          }

          return AlertDialog(
            title: Text(title),
            content: const Text(
              'Imprimez le document ou téléchargez le PDF.',
            ),
            actions: [
              TextButton(
                onPressed: busy ? null : () => Navigator.pop(ctx),
                child: const Text('Fermer'),
              ),
              OutlinedButton.icon(
                onPressed: busy ? null : () => run(false),
                icon: const Icon(Icons.download_outlined, size: 18),
                label: const Text('Télécharger'),
              ),
              FilledButton.icon(
                onPressed: busy ? null : () => run(true),
                icon: const Icon(Icons.print_outlined, size: 18),
                label: const Text('Imprimer'),
              ),
            ],
          );
        },
      );
    },
  );
}

class CashReportFigures {
  const CashReportFigures({
    required this.shopName,
    required this.openedBy,
    required this.openedAt,
    required this.openingHtg,
    required this.openingUsd,
    required this.inHtg,
    required this.inUsd,
    required this.outHtg,
    required this.outUsd,
    required this.expectedHtg,
    required this.expectedUsd,
    required this.cardUsd,
    required this.moncashHtg,
    required this.checkHtg,
    required this.movements,
  });

  final String shopName;
  final String openedBy;
  final DateTime openedAt;
  final double openingHtg;
  final double openingUsd;
  final double inHtg;
  final double inUsd;
  final double outHtg;
  final double outUsd;
  final double expectedHtg;
  final double expectedUsd;
  final double cardUsd;
  final double moncashHtg;
  final double checkHtg;
  final List<CashMovement> movements;

  factory CashReportFigures.fromState(
    CashControlState state, {
    String shopName = 'Boutique',
  }) {
    final session = state.activeSession;
    return CashReportFigures(
      shopName: shopName,
      openedBy: session?.openedBy ?? '',
      openedAt: session?.openedAt ?? DateTime.now(),
      openingHtg: session?.openingBalanceHtg ?? 0,
      openingUsd: session?.openingBalanceUsd ?? 0,
      inHtg: state.drawerCashInHtg,
      inUsd: state.drawerCashInUsd,
      outHtg: state.drawerCashOutHtg,
      outUsd: state.drawerCashOutUsd,
      expectedHtg: state.drawerExpectedHtg,
      expectedUsd: state.drawerExpectedUsd,
      cardUsd: state.tenderNetUsd(PaymentTender.card),
      moncashHtg: state.tenderNetHtg(PaymentTender.moncash),
      checkHtg: state.tenderNetHtg(PaymentTender.check),
      movements: state.sessionMovements,
    );
  }
}

Future<Uint8List> buildSessionReportPdf(CashReportFigures figures) {
  return _document(
    title: 'Rapport de caisse',
    subtitle: 'Session ouverte le ${_stamp(figures.openedAt)} par ${figures.openedBy}',
    shopName: figures.shopName,
    blocks: [
      _section('Attendu dans le tiroir', [
        _kv('Attendu HTG', _htg(figures.expectedHtg)),
        _kv('Attendu USD', _usd(figures.expectedUsd)),
      ]),
      _section('Tiroir — gourdes', [
        _kv('Ouverture HTG', _htg(figures.openingHtg)),
        _kv('Entrées HTG', _htg(figures.inHtg)),
        _kv('Sorties HTG', _htg(figures.outHtg)),
      ]),
      _section('Tiroir — dollars', [
        _kv('Ouverture USD', _usd(figures.openingUsd)),
        _kv('Entrées USD', _usd(figures.inUsd)),
        _kv('Sorties USD', _usd(figures.outUsd)),
      ]),
      _section('Hors tiroir', [
        _kv('Carte (USD)', _usd(figures.cardUsd)),
        _kv('MonCash (HTG)', _htg(figures.moncashHtg)),
        _kv('Chèque (HTG)', _htg(figures.checkHtg)),
      ]),
      _section(
        'Mouvements',
        [
          for (final m in figures.movements)
            _kv(
              '${_when(m.timestamp)}  ${m.tender.label}  ${m.description}',
              tenderUsesUsd(m.tender) ? _usd(m.totalUsd) : _htg(m.totalHtg),
            ),
        ],
      ),
    ],
  );
}

Future<Uint8List> buildShiftHandoffPdf({
  required String shopName,
  required CashierShiftHandoff handoff,
}) {
  return _document(
    title: 'Contrôle de fin de service',
    subtitle:
        '${_stamp(handoff.createdAt)}  ·  ${handoff.closedByName} → ${handoff.receivedByName}',
    shopName: shopName,
    blocks: [
      _section('Attendu et compté', [
        _kv('Attendu HTG', _htg(handoff.expectedHtg)),
        _kv('Compté HTG', _htg(handoff.countedHtg)),
        _kv('Écart HTG', _signedHtg(handoff.deltaHtg)),
        _kv('Attendu USD', _usd(handoff.expectedUsd)),
        _kv('Compté USD', _usd(handoff.countedUsd)),
        _kv('Écart USD', _signedUsd(handoff.deltaUsd)),
      ]),
      _section('Comment on y arrive', [
        _kv('Ouverture HTG', _htg(handoff.openingHtg)),
        _kv('Entrées HTG', _htg(handoff.inflowHtg)),
        _kv('Sorties HTG', _htg(handoff.outflowHtg)),
        _kv('Ouverture USD', _usd(handoff.openingUsd)),
        _kv('Entrées USD', _usd(handoff.inflowUsd)),
        _kv('Sorties USD', _usd(handoff.outflowUsd)),
      ]),
      if (handoff.note.isNotEmpty) _section('Note', [_kv('Note', handoff.note)]),
      pw.Padding(
        padding: const pw.EdgeInsets.only(top: 16),
        child: pw.Text(
          'La caisse reste ouverte. Le caissier suivant reprend le tiroir compté. '
          'Ce document n\'est pas une clôture de journée.',
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
        ),
      ),
    ],
  );
}

Future<Uint8List> buildClosurePdf({
  required String shopName,
  required SessionSummary summary,
  required double countedHtg,
  required double countedUsd,
  String note = '',
}) {
  final session = summary.session;
  final deltaHtg = countedHtg - summary.expectedHtg;
  final deltaUsd = countedUsd - summary.expectedUsd;
  return _document(
    title: 'Clôture de caisse',
    subtitle:
        'Fermée le ${_stamp(session.closedAt ?? DateTime.now())} par ${summary.closedBy}',
    shopName: shopName,
    blocks: [
      _section('Attendu et compté', [
        _kv('Attendu HTG', _htg(summary.expectedHtg)),
        _kv('Compté HTG', _htg(countedHtg)),
        _kv('Écart HTG', _signedHtg(deltaHtg)),
        _kv('Attendu USD', _usd(summary.expectedUsd)),
        _kv('Compté USD', _usd(countedUsd)),
        _kv('Écart USD', _signedUsd(deltaUsd)),
      ]),
      _section('Tiroir', [
        _kv('Ouverture HTG', _htg(session.openingBalanceHtg)),
        _kv('Entrées HTG', _htg(summary.totalInHtg)),
        _kv('Sorties HTG', _htg(summary.totalOutHtg)),
        _kv('Ouverture USD', _usd(session.openingBalanceUsd)),
        _kv('Entrées USD', _usd(summary.totalInUsd)),
        _kv('Sorties USD', _usd(summary.totalOutUsd)),
      ]),
      if (note.isNotEmpty) _section('Note', [_kv('Note', note)]),
    ],
  );
}

Future<Uint8List> _document({
  required String title,
  required String subtitle,
  required String shopName,
  required List<pw.Widget> blocks,
}) async {
  final theme = await shopPdfTheme();
  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      theme: theme,
      margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 40),
      build: (context) => [
        pw.Text(
          shopName,
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          title.toUpperCase(),
          style: pw.TextStyle(
            fontSize: 13,
            fontWeight: pw.FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        pw.SizedBox(height: 8),
        pw.Container(height: 1, color: PdfColors.grey600),
        pw.SizedBox(height: 8),
        pw.Text(
          subtitle,
          style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
        ),
        pw.SizedBox(height: 16),
        ...blocks,
      ],
    ),
  );
  return doc.save();
}

pw.Widget _section(String title, List<pw.Widget> rows) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 14),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(title, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 3),
        pw.Container(height: 0.6, color: PdfColors.grey400),
        pw.SizedBox(height: 6),
        ...rows,
      ],
    ),
  );
}

pw.Widget _kv(String label, String value) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 4),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(child: pw.Text(label, style: const pw.TextStyle(fontSize: 10))),
        pw.SizedBox(width: 12),
        pw.Text(
          value,
          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
        ),
      ],
    ),
  );
}

String _htg(double v) => '${v.toStringAsFixed(2)} HTG';
String _usd(double v) => '\$${v.toStringAsFixed(2)}';

String _signedHtg(double v) {
  if (v == 0) return _htg(0);
  return '${v > 0 ? '+' : '-'}${_htg(v.abs())}';
}

String _signedUsd(double v) {
  if (v == 0) return _usd(0);
  return '${v > 0 ? '+' : '-'}${_usd(v.abs())}';
}

String _stamp(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

String _when(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
