import 'dart:convert';

import 'package:share_plus/share_plus.dart';

import 'share_link.dart';

/// What the system share sheet sends for a company vitrine.
///
/// A short invitation and the link. Facebook, Instagram, WhatsApp and the
/// iPhone share sheet build the card (photo, name, details) from the link.
class VitrineShare {
  const VitrineShare({
    required this.message,
    required this.subject,
    this.url,
  });

  final String message;
  final String subject;
  final String? url;

  String get text => vitrineShareText(message, url);
}

typedef ShareVitrine = Future<void> Function(VitrineShare share);

/// Tests replace this so a tap can be checked without the platform share sheet.
ShareVitrine shareVitrineCard = _platformShareVitrine;

/// The invitation sent with the link. The card under it shows the details.
String vitrineShareMessage(String name) {
  final shop = name.trim().isEmpty ? 'Notre boutique' : name.trim();
  return '$shop est sur Tabkreyol ! '
      'Cliquez sur le lien pour commander chez nous, où que vous soyez.';
}

/// Message and link as one text, for targets that only take text.
String vitrineShareText(String message, String? url) =>
    [message, if (url != null && url.isNotEmpty) url].join('\n');

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
    if (await shareLinkWithMessage(share.message, url)) return;
  }
  // Apps and browsers without link sharing get the message with the link in it.
  await Share.share(share.text, subject: share.subject);
}
