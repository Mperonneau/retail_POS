import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'check_photo_limits.dart';

class PickedProductPhoto {
  const PickedProductPhoto({this.bytes, this.mime = 'image/jpeg', this.error});

  final Uint8List? bytes;
  final String mime;
  final String? error;
}

const int _maxPhotoBytes = 1500000;

Future<PickedProductPhoto?> pickProductPhoto() async {
  final file = await _chooseImageFile();
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

/// Accepts a normal camera photo of a check and returns a readable JPEG.
/// Only an absurdly large file is refused. The stored copy is scaled down.
Future<PickedProductPhoto?> pickCheckPhoto() async {
  final file = await _chooseImageFile();
  if (file == null) return null;
  if (file.size > checkPhotoHardMaxBytes) {
    return const PickedProductPhoto(error: checkPhotoTooHeavyError);
  }

  final url = web.URL.createObjectURL(file);
  try {
    final image = web.HTMLImageElement()..src = url;
    try {
      await image.decode().toDart;
    } catch (_) {
      return const PickedProductPhoto(error: checkPhotoUnreadableError);
    }
    if (image.naturalWidth <= 0 || image.naturalHeight <= 0) {
      return const PickedProductPhoto(error: checkPhotoUnreadableError);
    }

    Uint8List? stored;
    for (final pass in checkPhotoPasses) {
      final encoded = _jpegBytes(image, pass.maxEdge, pass.quality);
      if (encoded == null || encoded.isEmpty) {
        return const PickedProductPhoto(error: checkPhotoUnreadableError);
      }
      stored = encoded;
      if (encoded.length <= checkPhotoStoredMaxBytes) break;
    }
    return PickedProductPhoto(bytes: stored, mime: 'image/jpeg');
  } finally {
    web.URL.revokeObjectURL(url);
  }
}

Uint8List? _jpegBytes(web.HTMLImageElement image, int maxEdge, double quality) {
  final size = checkPhotoOutputSize(
    image.naturalWidth,
    image.naturalHeight,
    maxEdge,
  );
  if (size.width <= 0 || size.height <= 0) return null;

  final canvas = web.HTMLCanvasElement()
    ..width = size.width
    ..height = size.height;
  final context = canvas.getContext('2d');
  if (context == null) return null;
  final ctx = context as web.CanvasRenderingContext2D;
  ctx.imageSmoothingEnabled = true;
  ctx.imageSmoothingQuality = 'high';
  ctx.fillStyle = '#ffffff'.toJS;
  ctx.fillRect(0, 0, size.width, size.height);
  ctx.drawImage(image, 0, 0, size.width, size.height);

  final dataUrl = canvas.toDataURL('image/jpeg', quality.toJS);
  final comma = dataUrl.indexOf(',');
  if (comma < 0 || comma >= dataUrl.length - 1) return null;
  try {
    final bytes = base64Decode(dataUrl.substring(comma + 1));
    if (bytes.isEmpty) return null;
    return bytes;
  } catch (_) {
    return null;
  }
}

Future<web.File?> _chooseImageFile() {
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
      Future<void>.delayed(
        const Duration(milliseconds: 400),
        () => finish(null),
      );
    }).toJS,
  );

  input.click();
  return selected.future;
}
