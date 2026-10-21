import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'catalog_file.dart';

const int _maxFiles = 6;
const int _maxBytes = 4000000;

/// Extensions only, plus images. A long MIME list makes iPhone drop the file
/// after the user has chosen it.
const String _accept =
    'image/*,.pdf,.csv,.tsv,.txt,.xlsx,.xlsm,.xls,.docx,.doc,.ods,.odt';

Future<CatalogPick> pickCatalogFiles() async {
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..multiple = true
    ..accept = _accept;
  // iPhone only delivers the file when the input is in the page.
  input.style
    ..position = 'fixed'
    ..left = '0'
    ..top = '0'
    ..width = '48px'
    ..height = '48px'
    ..opacity = '0.01';
  web.document.body?.append(input);

  final selected = Completer<List<web.File>>();
  var settled = false;
  Timer? focusTimer;
  JSFunction? onFocus;

  List<web.File> currentFiles() {
    final list = input.files;
    if (list == null || list.length == 0) return const [];
    return [for (var i = 0; i < list.length; i++) list.item(i)!];
  }

  void finish(List<web.File> files) {
    if (settled) return;
    settled = true;
    focusTimer?.cancel();
    final focus = onFocus;
    if (focus != null) {
      web.window.removeEventListener('focus', focus);
      onFocus = null;
    }
    if (!selected.isCompleted) selected.complete(files);
  }

  input.onchange = ((web.Event _) {
    final files = currentFiles();
    // An empty change is the phone still copying the file. Wait for it.
    if (files.isNotEmpty) finish(files);
  }).toJS;
  input.addEventListener(
    'cancel',
    ((web.Event _) {
      finish(const []);
    }).toJS,
  );

  // The page regains focus when the picker closes. On iPhone the file can
  // arrive after that focus, so keep reading it instead of dropping the choice.
  onFocus = ((web.Event _) {
    focusTimer?.cancel();
    var tries = 0;
    focusTimer = Timer.periodic(const Duration(milliseconds: 300), (timer) {
      tries++;
      final files = currentFiles();
      if (files.isNotEmpty || tries >= 10) {
        timer.cancel();
        finish(files);
      }
    });
  }).toJS;
  web.window.addEventListener('focus', onFocus!);

  try {
    input.click();
    final chosen = await selected.future;
    if (chosen.isEmpty) return const CatalogPick();
    final files = <CatalogFile>[];
    final skipped = <String>[];
    final failed = <String>[];
    for (final file in chosen.take(_maxFiles)) {
      if (file.size > _maxBytes) {
        skipped.add(file.name);
        continue;
      }
      try {
        final buffer = await file.arrayBuffer().toDart;
        files.add(
          CatalogFile(
            name: file.name,
            mime: file.type.isEmpty ? 'application/octet-stream' : file.type,
            bytes: buffer.toDart.asUint8List(),
          ),
        );
      } catch (_) {
        failed.add(file.name);
      }
    }
    if (chosen.length > _maxFiles) {
      skipped.add('au-delà de $_maxFiles fichiers');
    }
    final messages = <String>[
      if (skipped.isNotEmpty)
        'Ignoré (plus de 4 Mo ou trop de fichiers) : ${skipped.join(', ')}.',
      if (failed.isNotEmpty)
        'Impossible de lire : ${failed.join(', ')}.',
    ];
    return CatalogPick(
      files: files,
      error: messages.isEmpty ? null : messages.join(' '),
    );
  } finally {
    finish(const []);
    input.remove();
  }
}
