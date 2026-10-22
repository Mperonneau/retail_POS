import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

typedef ReceiptFileShare =
    Future<void> Function({
      required Uint8List bytes,
      required String filename,
      required String subject,
    });

/// Opens the phone share sheet with the receipt PDF so WhatsApp, e-mail,
/// or any other app can receive the file.
Future<void> shareReceiptPdfFile({
  required Uint8List bytes,
  required String filename,
  required String subject,
}) {
  return Share.shareXFiles(
    [XFile.fromData(bytes, mimeType: 'application/pdf', name: filename)],
    fileNameOverrides: [filename],
    subject: subject,
    text: subject,
  );
}

/// Tests replace this so a tap can be checked without the platform share sheet.
ReceiptFileShare shareReceiptFile = shareReceiptPdfFile;
