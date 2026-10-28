import 'dart:convert';

import 'package:share_plus/share_plus.dart';

/// What the system share sheet sends for a company vitrine.
///
/// Only the link is shared when there is one. Facebook, Instagram, WhatsApp
/// and the iPhone share sheet build the card (photo, name, details) from it.
class VitrineShare {
  const VitrineShare({required this.text, required this.subject, this.url});

  final String text;
  final String subject;
  final String? url;
}

typedef ShareVitrine = Future<void> Function(VitrineShare share);

/// Tests replace this so a tap can be checked without the platform share sheet.
ShareVitrine shareVitrineCard = _platformShareVitrine;

/// Caption for share targets that only take text: name, place, and link.
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

/// The shop link with a mark that changes whenever the vitrine changes.
///
/// Facebook keeps the first card it sees for a link. A new mark after an
/// update makes it read the page again instead of showing the old card.
String vitrineShareLink(String url, List<Object?> parts) {
  var hash = 0x811c9dc5;
  for (final byte in utf8.encode(parts.map((p) => '$p').join('\n'))) {
    hash = ((hash ^ byte) * 0x01000193) & 0xFFFFFFFF;
  }
  final mark = hash.toRadixString(36);
  return '$url${url.contains('?') ? '&' : '?'}v=$mark';
}

Future<void> _platformShareVitrine(VitrineShare share) async {
  final url = share.url;
  if (url != null && url.isNotEmpty) {
    try {
      await Share.shareUri(Uri.parse(url));
      return;
    } catch (_) {
      // No link sharing here (desktop browsers). The caption still goes.
    }
  }
  await Share.share(share.text, subject: share.subject);
}
