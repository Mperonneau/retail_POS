import 'dart:convert';
import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

/// What the system share sheet sends for a company vitrine.
class VitrineShare {
  const VitrineShare({
    required this.text,
    required this.subject,
    this.image,
    this.mime,
  });

  final String text;
  final String subject;
  final Uint8List? image;
  final String? mime;
}

typedef ShareVitrine = Future<void> Function(VitrineShare share);

/// Tests replace this so a tap can be checked without the platform share sheet.
ShareVitrine shareVitrineCard = _platformShareVitrine;

/// Caption for WhatsApp and the other share targets: name, place, and link.
String vitrineShareText({
  required String name,
  required String city,
  required String department,
  required List<String> categories,
  required String description,
  required int openHour,
  required int closeHour,
  required String? url,
}) {
  final place = [
    city,
    department,
  ].where((part) => part.trim().isNotEmpty).join(', ');
  return [
    name.trim(),
    place,
    if (categories.isNotEmpty) categories.join(' · '),
    description.trim(),
    'Ouvert ${openHour}h – ${closeHour}h',
    if (url != null && url.isNotEmpty) url,
  ].where((line) => line.isNotEmpty).join('\n');
}

/// Bytes and mime of a `data:image/...;base64,` cover, when it can be shared.
({Uint8List bytes, String mime})? vitrineCoverFile(String? dataUrl) {
  if (dataUrl == null || !dataUrl.startsWith('data:image/')) return null;
  final comma = dataUrl.indexOf(',');
  if (comma < 0) return null;
  final mime = dataUrl.substring('data:'.length, comma).split(';').first;
  try {
    final bytes = base64Decode(dataUrl.substring(comma + 1));
    if (bytes.isEmpty) return null;
    return (bytes: bytes, mime: mime);
  } catch (_) {
    return null;
  }
}

Future<void> _platformShareVitrine(VitrineShare share) async {
  final image = share.image;
  if (image != null && image.isNotEmpty) {
    final mime = share.mime ?? 'image/jpeg';
    final ext = mime.contains('png')
        ? 'png'
        : mime.contains('webp')
        ? 'webp'
        : 'jpg';
    final filename = 'vitrine.$ext';
    try {
      await Share.shareXFiles(
        [XFile.fromData(image, mimeType: mime, name: filename)],
        fileNameOverrides: [filename],
        text: share.text,
        subject: share.subject,
      );
      return;
    } catch (_) {
      // This browser can share text but not a picture. The caption still goes.
    }
  }
  await Share.share(share.text, subject: share.subject);
}
