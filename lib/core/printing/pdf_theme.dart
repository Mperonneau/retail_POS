import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;

pw.Font? _regular;
pw.Font? _bold;

/// Liberation Sans is bundled so printed documents keep accents offline.
Future<pw.ThemeData> shopPdfTheme() async {
  _regular ??= pw.Font.ttf(
    await rootBundle.load('assets/fonts/LiberationSans-Regular.ttf'),
  );
  _bold ??= pw.Font.ttf(
    await rootBundle.load('assets/fonts/LiberationSans-Bold.ttf'),
  );
  return pw.ThemeData.withFont(base: _regular, bold: _bold);
}
