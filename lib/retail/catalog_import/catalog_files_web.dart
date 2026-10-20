import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'catalog_file.dart';

const int _maxFiles = 6;
const int _maxBytes = 4000000;

Future<CatalogPick> pickCatalogFiles() async {
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..multiple = true
    ..accept = 'image/*,.pdf,.csv,.tsv,.txt,.xlsx,.xlsm,.xls,.docx,.doc,.ods,.odt,'
        'application/pdf,text/csv,text/plain,'
        'application/vnd.ms-excel,'
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet,'
        'application/msword,'
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
  final selected = Completer<List<web.File>>();
  var settled = false;

  void finish(List<web.File> files) {
    if (settled) return;
    settled = true;
    selected.complete(files);
  }

  input.onchange = ((web.Event _) {
    final list = input.files;
    if (list == null || list.length == 0) {
      finish(const []);
      return;
    }
    finish([for (var i = 0; i < list.length; i++) list.item(i)!]);
  }).toJS;
  web.window.addEventListener(
    'focus',
    ((web.Event _) {
      Future<void>.delayed(const Duration(milliseconds: 400), () {
        finish(const []);
      });
    }).toJS,
  );
  input.click();
  final chosen = await selected.future;
  if (chosen.isEmpty) return const CatalogPick();
  final files = <CatalogFile>[];
  final skipped = <String>[];
  for (final file in chosen.take(_maxFiles)) {
    if (file.size > _maxBytes) {
      skipped.add(file.name);
      continue;
    }
    final buffer = await file.arrayBuffer().toDart;
    files.add(
      CatalogFile(
        name: file.name,
        mime: file.type.isEmpty ? 'application/octet-stream' : file.type,
        bytes: buffer.toDart.asUint8List(),
      ),
    );
  }
  if (chosen.length > _maxFiles) {
    skipped.add('au-delà de $_maxFiles fichiers');
  }
  return CatalogPick(
    files: files,
    error: skipped.isEmpty
        ? null
        : 'Ignoré (plus de 4 Mo ou trop de fichiers) : ${skipped.join(', ')}.',
  );
}
