import 'dart:typed_data';

class PickedProductPhoto {
  const PickedProductPhoto({this.bytes, this.mime = 'image/jpeg', this.error});

  final Uint8List? bytes;
  final String mime;
  final String? error;
}

Future<PickedProductPhoto?> pickProductPhoto() async =>
    const PickedProductPhoto(
      error: 'Le choix d\'une photo est disponible dans le navigateur.',
    );

Future<PickedProductPhoto?> pickCheckPhoto() async => const PickedProductPhoto(
  error: 'Le choix d\'une photo est disponible dans le navigateur.',
);
