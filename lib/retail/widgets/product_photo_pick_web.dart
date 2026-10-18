import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

class PickedProductPhoto {
  const PickedProductPhoto({this.bytes, this.mime = 'image/jpeg', this.error});

  final Uint8List? bytes;
  final String mime;
  final String? error;
}

const int _maxPhotoBytes = 1500000;

Future<PickedProductPhoto?> pickProductPhoto() async {
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = 'image/*';
  final selected = Completer<web.File?>();
  var settled = false;

  void finish(web.File? file) {
    if (settled) return;
    settled = true;
    selected.complete(file);
  }

  input.onchange = ((web.Event _) {
    final files = input.files;
    if (files == null || files.length == 0) {
      finish(null);
      return;
    }
    finish(files.item(0));
  }).toJS;

  web.window.addEventListener(
    'focus',
    ((web.Event _) {
      Future<void>.delayed(const Duration(milliseconds: 400), () => finish(null));
    }).toJS,
  );

  input.click();
  final file = await selected.future;
  if (file == null) return null;
  if (file.size > _maxPhotoBytes) {
    return const PickedProductPhoto(
      error: 'La photo doit faire moins de 1,5 Mo.',
    );
  }
  final buffer = await file.arrayBuffer().toDart;
  final mime = file.type.isEmpty ? 'image/jpeg' : file.type;
  return PickedProductPhoto(bytes: buffer.toDart.asUint8List(), mime: mime);
}
