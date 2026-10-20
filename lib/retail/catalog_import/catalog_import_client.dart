import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/payments/payments_client.dart';
import 'catalog_file.dart';

class CatalogImportException implements Exception {
  CatalogImportException(this.message);
  final String message;
}

class CatalogReportLine {
  const CatalogReportLine({required this.severity, required this.message});

  final String severity;
  final String message;

  factory CatalogReportLine.fromJson(Map<String, dynamic> json) =>
      CatalogReportLine(
        severity: json['severity']?.toString() ?? 'info',
        message: json['message']?.toString() ?? '',
      );
}

class CatalogDraftChoice {
  const CatalogDraftChoice({required this.name, required this.priceDeltaHtg});

  final String name;
  final int priceDeltaHtg;
}

class CatalogDraftGroup {
  const CatalogDraftGroup({
    required this.name,
    required this.kind,
    required this.requiredChoice,
    required this.multiple,
    required this.choices,
  });

  final String name;
  final String kind;
  final bool requiredChoice;
  final bool multiple;
  final List<CatalogDraftChoice> choices;

  factory CatalogDraftGroup.fromJson(Map<String, dynamic> json) =>
      CatalogDraftGroup(
        name: json['name']?.toString() ?? 'Options',
        kind: json['kind']?.toString() ?? 'other',
        requiredChoice: json['required'] == true,
        multiple: json['multiple'] == true,
        choices: [
          for (final row in (json['choices'] as List? ?? const []))
            if (row is Map)
              CatalogDraftChoice(
                name: row['name']?.toString() ?? '',
                priceDeltaHtg: _int(row['price_delta_htg']),
              ),
        ].where((choice) => choice.name.isNotEmpty).toList(),
      );
}

class CatalogDraftItem {
  const CatalogDraftItem({
    required this.name,
    required this.priceHtg,
    required this.costHtg,
    required this.barcode,
    required this.unit,
    required this.stock,
    required this.description,
    required this.groups,
  });

  final String name;
  final int priceHtg;
  final int costHtg;
  final String barcode;
  final String unit;
  final int? stock;
  final String description;
  final List<CatalogDraftGroup> groups;

  factory CatalogDraftItem.fromJson(Map<String, dynamic> json) {
    final stock = json['stock'];
    return CatalogDraftItem(
      name: json['name']?.toString() ?? '',
      priceHtg: _int(json['price_htg']),
      costHtg: _int(json['cost_htg']),
      barcode: json['barcode']?.toString() ?? '',
      unit: json['unit']?.toString() ?? 'u',
      stock: stock == null ? null : _int(stock),
      description: json['description']?.toString() ?? '',
      groups: [
        for (final row in (json['option_groups'] as List? ?? const []))
          if (row is Map)
            CatalogDraftGroup.fromJson(row.cast<String, dynamic>()),
      ],
    );
  }
}

class CatalogDraftCategory {
  const CatalogDraftCategory({required this.name, required this.items});

  final String name;
  final List<CatalogDraftItem> items;

  factory CatalogDraftCategory.fromJson(Map<String, dynamic> json) =>
      CatalogDraftCategory(
        name: json['name']?.toString() ?? 'Autre',
        items: [
          for (final row in (json['items'] as List? ?? const []))
            if (row is Map)
              CatalogDraftItem.fromJson(row.cast<String, dynamic>()),
        ],
      );
}

class CatalogJob {
  const CatalogJob({
    required this.id,
    required this.status,
    required this.progress,
    required this.error,
    required this.categories,
    required this.report,
  });

  final String id;
  final String status;
  final String progress;
  final String error;
  final List<CatalogDraftCategory> categories;
  final List<CatalogReportLine> report;

  bool get isDone => status == 'succeeded' || status == 'failed';

  factory CatalogJob.fromJson(Map<String, dynamic> json) {
    final draft = (json['draft'] as Map?)?.cast<String, dynamic>() ?? const {};
    return CatalogJob(
      id: json['id']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      progress: json['progress']?.toString() ?? '',
      error: json['error']?.toString() ?? '',
      categories: [
        for (final row in (draft['categories'] as List? ?? const []))
          if (row is Map)
            CatalogDraftCategory.fromJson(row.cast<String, dynamic>()),
      ],
      report: [
        for (final row in (json['report'] as List? ?? const []))
          if (row is Map)
            CatalogReportLine.fromJson(row.cast<String, dynamic>()),
      ].where((line) => line.message.isNotEmpty).toList(),
    );
  }
}

class CatalogImportClient {
  CatalogImportClient({http.Client? httpClient, String? baseUrl})
    : _http = httpClient ?? http.Client(),
      _base = (baseUrl ?? PaymentsClient.apiBase).replaceAll(
        RegExp(r'/+$'),
        '',
      );

  final http.Client _http;
  final String _base;

  Future<String> start({
    required List<CatalogFile> files,
    required String ownerNote,
    required String currencyMode,
    required int usdRate,
  }) async {
    final body = await _send(
      () => _http.post(
        Uri.parse('$_base/catalog/imports'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'owner_note': ownerNote,
          'currency_mode': currencyMode,
          'usd_rate': usdRate,
          'files': [
            for (final file in files)
              {
                'name': file.name,
                'content_type': file.mime,
                'data_base64': base64Encode(file.bytes),
              },
          ],
        }),
      ),
    );
    final id = body['id']?.toString() ?? '';
    if (id.isEmpty) {
      throw CatalogImportException('Le serveur n\'a pas démarré l\'analyse.');
    }
    return id;
  }

  Future<CatalogJob> fetch(String id) async {
    final body = await _send(
      () => _http.get(Uri.parse('$_base/catalog/imports/$id')),
    );
    return CatalogJob.fromJson(body);
  }

  Future<Map<String, dynamic>> _send(
    Future<http.Response> Function() call,
  ) async {
    final http.Response response;
    try {
      response = await call().timeout(const Duration(seconds: 45));
    } catch (_) {
      throw CatalogImportException(
        'Impossible de joindre le serveur. Réessayez.',
      );
    }
    Map<String, dynamic> body = const {};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) body = decoded;
    } catch (_) {}
    if (response.statusCode >= 400) {
      final message = body['error']?.toString().trim() ?? '';
      throw CatalogImportException(
        message.isEmpty
            ? 'L\'analyse a échoué (${response.statusCode}).'
            : message,
      );
    }
    return body;
  }
}

int _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse('$value') ?? 0;
}
