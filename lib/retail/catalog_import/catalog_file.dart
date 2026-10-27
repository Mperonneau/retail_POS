import 'dart:typed_data';

class CatalogFile {
  const CatalogFile({
    required this.name,
    required this.mime,
    required this.bytes,
  });

  final String name;
  final String mime;
  final Uint8List bytes;
}

class CatalogPick {
  const CatalogPick({this.files = const [], this.error});

  final List<CatalogFile> files;
  final String? error;
}
