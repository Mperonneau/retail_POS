import 'dart:async';
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

const String checkPhotoAttachError =
    'La photo n\'a pas pu être ajoutée. Réessayez.';

/// Accepts a normal camera photo of a check and returns a readable JPEG.
/// Only an absurdly large file is refused. The stored copy is scaled down.
Future<PickedProductPhoto?> pickCheckPhoto() async {
  final file = await _chooseImageFile();
  if (file == null) return null;
  if (file.size > checkPhotoHardMaxBytes) {
    return const PickedProductPhoto(error: checkPhotoTooHeavyError);
  }

  try {
    // Let the button show its spinner before the image work starts.
    await Future<void>.delayed(Duration.zero);
    final bytes = await _compressCheckPhoto(
      file,
    ).timeout(const Duration(seconds: 20));
    if (bytes == null || bytes.isEmpty) {
      return const PickedProductPhoto(error: checkPhotoUnreadableError);
    }
    return PickedProductPhoto(bytes: bytes, mime: 'image/jpeg');
  } on TimeoutException {
    return const PickedProductPhoto(error: checkPhotoAttachError);
  } catch (_) {
    return const PickedProductPhoto(error: checkPhotoUnreadableError);
  }
}

class _CheckSource {
  _CheckSource(this.image, this.width, this.height, this.close);

  final web.CanvasImageSource image;
  final int width;
  final int height;
  final void Function() close;
}

Future<Uint8List?> _compressCheckPhoto(web.File file) async {
  final source = await _openCheckSource(file);
  if (source == null) return null;
  try {
    Uint8List? stored;
    for (final pass in checkPhotoPasses) {
      stored = await _jpegBytes(
        source.image,
        source.width,
        source.height,
        pass.maxEdge,
        pass.quality,
      );
      if (stored == null || stored.isEmpty) return null;
      if (stored.length <= checkPhotoStoredMaxBytes) break;
    }
    return stored;
  } finally {
    source.close();
  }
}

/// Decodes off the UI thread when the browser can, then falls back to an
/// image element. Either way the caller draws a small canvas, not the
/// original multi-megapixel photo.
Future<_CheckSource?> _openCheckSource(web.File file) async {
  try {
    final bitmap = await web.window
        .createImageBitmap(file)
        .toDart
        .timeout(const Duration(seconds: 15));
    if (bitmap.width > 0 && bitmap.height > 0) {
      return _CheckSource(
        bitmap,
        bitmap.width,
        bitmap.height,
        () => bitmap.close(),
      );
    }
    bitmap.close();
  } catch (_) {
    // Some phones still decode HEIC only through an image element.
  }

  final url = web.URL.createObjectURL(file);
  final image = web.HTMLImageElement()..src = url;
  try {
    await image.decode().toDart.timeout(const Duration(seconds: 15));
  } catch (_) {
    web.URL.revokeObjectURL(url);
    return null;
  }
  if (image.naturalWidth <= 0 || image.naturalHeight <= 0) {
    web.URL.revokeObjectURL(url);
    return null;
  }
  return _CheckSource(
    image,
    image.naturalWidth,
    image.naturalHeight,
    () => web.URL.revokeObjectURL(url),
  );
}

Future<Uint8List?> _jpegBytes(
  web.CanvasImageSource image,
  int sourceWidth,
  int sourceHeight,
  int maxEdge,
  double quality,
) async {
  final size = checkPhotoOutputSize(sourceWidth, sourceHeight, maxEdge);
  if (size.width <= 0 || size.height <= 0) return null;

  final canvas = web.HTMLCanvasElement()
    ..width = size.width
    ..height = size.height;
  final context = canvas.getContext('2d');
  if (context == null) return null;
  final ctx = context as web.CanvasRenderingContext2D;
  ctx.imageSmoothingEnabled = true;
  ctx.imageSmoothingQuality = 'medium';
  ctx.fillStyle = '#ffffff'.toJS;
  ctx.fillRect(0, 0, size.width.toDouble(), size.height.toDouble());
  ctx.drawImage(image, 0, 0, size.width.toDouble(), size.height.toDouble());

  try {
    final blob = await _jpegBlob(canvas, quality);
    if (blob == null) return null;
    final buffer = await blob.arrayBuffer().toDart;
    final bytes = buffer.toDart.asUint8List();
    if (bytes.isEmpty) return null;
    return bytes;
  } catch (_) {
    return null;
  }
}

Future<web.Blob?> _jpegBlob(web.HTMLCanvasElement canvas, double quality) {
  final done = Completer<web.Blob?>();
  canvas.toBlob(
    (web.Blob? blob) {
      if (!done.isCompleted) done.complete(blob);
    }.toJS,
    'image/jpeg',
    quality.toJS,
  );
  return done.future.timeout(
    const Duration(seconds: 12),
    onTimeout: () => null,
  );
}

web.File? _selectedFile(web.HTMLInputElement input) {
  final files = input.files;
  if (files == null || files.length == 0) return null;
  return files.item(0);
}

/// iOS drops the file when the input is not in the page, and it often
/// restores focus before `files` is filled. Keep the input mounted and
/// wait briefly after the picker closes before treating it as a cancel.
Future<web.File?> _chooseImageFile() {
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = 'image/*';
  input.style
    ..position = 'fixed'
    ..left = '-1000px'
    ..top = '0'
    ..width = '1px'
    ..height = '1px'
    ..opacity = '0';
  web.document.body?.append(input);

  final selected = Completer<web.File?>();
  final openedAt = DateTime.now();
  var settled = false;
  var watching = false;
  web.EventListener? onReturn;

  void cleanup() {
    final listener = onReturn;
    if (listener != null) {
      web.window.removeEventListener('focus', listener);
      web.document.removeEventListener('visibilitychange', listener);
      onReturn = null;
    }
    input.remove();
  }

  void finish(web.File? file) {
    if (settled) return;
    settled = true;
    cleanup();
    selected.complete(file);
  }

  input.onchange = ((web.Event _) {
    final file = _selectedFile(input);
    // An empty change can arrive before iOS fills the list. Keep waiting.
    if (file != null) finish(file);
  }).toJS;
  input.oncancel = ((web.Event _) => finish(null)).toJS;

  onReturn = ((web.Event _) {
    if (settled || watching) return;
    if (web.document.visibilityState == 'hidden') return;
    // The picker can flicker focus as it opens. Wait until it has closed.
    if (DateTime.now().difference(openedAt) <
        const Duration(milliseconds: 400)) {
      return;
    }
    watching = true;
    Future<void>(() async {
      for (var i = 0; i < 16; i++) {
        if (settled) return;
        final file = _selectedFile(input);
        if (file != null) {
          finish(file);
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      finish(_selectedFile(input));
    });
  }).toJS;
  web.window.addEventListener('focus', onReturn!);
  web.document.addEventListener('visibilitychange', onReturn!);

  input.click();
  return selected.future;
}
