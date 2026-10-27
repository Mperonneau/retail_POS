import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/local_store.dart';
import 'catalog_file.dart';
import 'catalog_import_client.dart';

const _jobKey = 'retail.catalog_import_job';

const catalogAnalyzeHeadline = 'Nous analysons vos documents.';

const _lostMessage =
    'L\'analyse a été interrompue par un redémarrage du serveur. '
    'Touchez Analyser pour recommencer.';

enum CatalogImportPhase { idle, running, ready, failed }

class CatalogImportWatchState {
  const CatalogImportWatchState({
    this.phase = CatalogImportPhase.idle,
    this.jobId = '',
    this.headline = catalogAnalyzeHeadline,
    this.error = '',
    this.job,
  });

  final CatalogImportPhase phase;
  final String jobId;
  final String headline;
  final String error;
  final CatalogJob? job;
}

class _Request {
  const _Request({
    required this.files,
    required this.ownerNote,
    required this.currencyMode,
    required this.usdRate,
    required this.knownCategories,
  });

  final List<CatalogFile> files;
  final String ownerNote;
  final String currencyMode;
  final int usdRate;
  final List<String> knownCategories;
}

/// Follows one catalogue analysis after the import screen is closed.
class CatalogImportWatch extends Notifier<CatalogImportWatchState> {
  final _client = CatalogImportClient();
  Timer? _poll;
  var _restored = false;
  var _disposed = false;
  _Request? _last;
  var _relaunched = false;

  bool get _alive => !_disposed;

  @override
  CatalogImportWatchState build() {
    ref.onDispose(() {
      _disposed = true;
      _poll?.cancel();
    });
    Future.microtask(_restore);
    return const CatalogImportWatchState();
  }

  Future<void> _restore() async {
    if (_restored) return;
    _restored = true;
    final id = await LocalStore.instance.getString(_jobKey);
    if (!_alive || id == null || id.isEmpty) return;
    if (state.phase != CatalogImportPhase.idle) return;
    state = CatalogImportWatchState(
      phase: CatalogImportPhase.running,
      jobId: id,
      headline: catalogAnalyzeHeadline,
    );
    _follow(id);
  }

  Future<void> begin({
    required List<CatalogFile> files,
    required String ownerNote,
    required String currencyMode,
    required int usdRate,
    required List<String> knownCategories,
  }) async {
    _relaunched = false;
    _last = _Request(
      files: files,
      ownerNote: ownerNote,
      currencyMode: currencyMode,
      usdRate: usdRate,
      knownCategories: knownCategories,
    );
    await _send(_last!, headline: 'Envoi de vos documents…');
  }

  Future<void> _send(_Request request, {required String headline}) async {
    _restored = true;
    _poll?.cancel();
    state = CatalogImportWatchState(
      phase: CatalogImportPhase.running,
      headline: headline,
    );
    try {
      final id = await _client.start(
        files: request.files,
        ownerNote: request.ownerNote,
        currencyMode: request.currencyMode,
        usdRate: request.usdRate,
        knownCategories: request.knownCategories,
      );
      await LocalStore.instance.setString(_jobKey, id);
      if (!_alive) return;
      state = CatalogImportWatchState(
        phase: CatalogImportPhase.running,
        jobId: id,
        headline: catalogAnalyzeHeadline,
      );
      _follow(id);
    } on CatalogImportException catch (error) {
      if (!_alive) return;
      state = CatalogImportWatchState(
        phase: CatalogImportPhase.failed,
        error: error.message,
      );
    }
  }

  void _follow(String id) {
    _poll?.cancel();
    if (state.jobId != id || state.phase != CatalogImportPhase.running) {
      state = CatalogImportWatchState(
        phase: CatalogImportPhase.running,
        jobId: id,
        headline: state.headline.isEmpty
            ? catalogAnalyzeHeadline
            : state.headline,
      );
    }
    _pull(id);
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _pull(id));
  }

  Future<void> _pull(String id) async {
    try {
      final job = await _client.fetch(id);
      if (!_alive || state.jobId != id) return;
      if (!job.isDone) {
        state = CatalogImportWatchState(
          phase: CatalogImportPhase.running,
          jobId: id,
          headline: catalogAnalyzeHeadline,
        );
        return;
      }
      _poll?.cancel();
      if (job.status == 'failed') {
        await LocalStore.instance.remove(_jobKey);
        if (!_alive) return;
        state = CatalogImportWatchState(
          phase: CatalogImportPhase.failed,
          error: job.error.isEmpty
              ? 'L\'analyse a échoué. Réessayez.'
              : job.error,
        );
        return;
      }
      state = CatalogImportWatchState(
        phase: CatalogImportPhase.ready,
        jobId: id,
        headline: 'L\'analyse est prête.',
        job: job,
      );
    } on CatalogImportException catch (error) {
      if (!_alive || state.jobId != id) return;
      // A network hiccup keeps polling. Only a lost analysis stops it.
      if (!error.isLost) return;
      _poll?.cancel();
      await LocalStore.instance.remove(_jobKey);
      if (!_alive) return;
      final last = _last;
      if (last != null && !_relaunched) {
        _relaunched = true;
        await _send(
          last,
          headline: 'Le serveur a redémarré. Nous relançons l\'analyse.',
        );
        return;
      }
      state = const CatalogImportWatchState(
        phase: CatalogImportPhase.failed,
        error: _lostMessage,
      );
    }
  }

  Future<void> dismiss() async {
    _poll?.cancel();
    _last = null;
    await LocalStore.instance.remove(_jobKey);
    if (!_alive) return;
    state = const CatalogImportWatchState();
  }
}

final catalogImportWatchProvider =
    NotifierProvider<CatalogImportWatch, CatalogImportWatchState>(
      CatalogImportWatch.new,
    );
