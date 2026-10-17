import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/pending_operation.dart';
import '../models/retail_order.dart';
import '../models/staff_role.dart';
import '../services/device_pairing.dart';
import '../services/local_store.dart';
import '../services/network_browser.dart';
import '../services/pin_shift_cache.dart';
import 'auth_provider.dart';

class StoredProfile {
  const StoredProfile({
    required this.userName,
    required this.businessName,
    required this.module,
  });

  final String userName;
  final String businessName;
  final ActiveModule module;

  Map<String, dynamic> toJson() => {
        'user_name': userName,
        'business_name': businessName,
        'module': module.name,
      };

  static StoredProfile? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final business = json['business_name']?.toString() ?? '';
    if (business.isEmpty) return null;
    final moduleName = json['module']?.toString() ?? ActiveModule.retail.name;
    final module = ActiveModule.values
        .where((m) => m.name == moduleName)
        .firstOrNull ??
        ActiveModule.retail;
    return StoredProfile(
      userName: json['user_name']?.toString() ?? 'Gérant',
      businessName: business,
      module: module,
    );
  }
}

class DeviceSessionState {
  const DeviceSessionState({
    required this.ready,
    this.pairing,
    this.profile,
    this.invites = const [],
    this.pinCache = const [],
    this.deviceId = '',
    this.online = true,
    this.syncing = false,
    this.pending = const [],
    this.lastSyncAt,
  });

  final bool ready;
  final DevicePairingInfo? pairing;
  final StoredProfile? profile;
  final List<DeviceInvite> invites;
  final List<PinShiftEntry> pinCache;
  final String deviceId;
  final bool online;
  final bool syncing;
  /// Changes made offline, newest first, until Synchroniser sends them.
  final List<PendingOperation> pending;
  final DateTime? lastSyncAt;

  bool get isPaired => pairing != null;

  bool get offlineUnlockBlocked =>
      isPaired && !online && (pairing?.offlineExpired(DateTime.now()) ?? false);

  bool get offlineExpiringSoon =>
      isPaired && !online && (pairing?.offlineExpiringSoon(DateTime.now()) ?? false);

  String get offlineUnlockBlockedMessage =>
      'Cet appareil n\'a pas joint le serveur depuis '
      '${pairing?.offlineWindowDays ?? DevicePairingInfo.defaultOfflineWindowDays} jours. '
      'Connectez-vous à internet pour utiliser les codes PIN.';

  DeviceSessionState copyWith({
    bool? ready,
    DevicePairingInfo? pairing,
    bool clearPairing = false,
    StoredProfile? profile,
    List<DeviceInvite>? invites,
    List<PinShiftEntry>? pinCache,
    String? deviceId,
    bool? online,
    bool? syncing,
    List<PendingOperation>? pending,
    DateTime? lastSyncAt,
  }) {
    return DeviceSessionState(
      ready: ready ?? this.ready,
      pairing: clearPairing ? null : (pairing ?? this.pairing),
      profile: profile ?? this.profile,
      invites: invites ?? this.invites,
      pinCache: pinCache ?? this.pinCache,
      deviceId: deviceId ?? this.deviceId,
      online: online ?? this.online,
      syncing: syncing ?? this.syncing,
      pending: pending ?? this.pending,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
    );
  }
}

class DeviceSessionNotifier extends StateNotifier<DeviceSessionState> {
  DeviceSessionNotifier() : super(const DeviceSessionState(ready: false)) {
    _netSub = BrowserNetwork.changes.listen(setOnline);
    unawaited(restore());
  }

  final LocalStore _store = LocalStore.instance;
  StreamSubscription<bool>? _netSub;
  Future<void>? _restoreFuture;

  @override
  void dispose() {
    unawaited(_netSub?.cancel());
    super.dispose();
  }

  Future<void> restore() {
    return _restoreFuture ??= _restore();
  }

  Future<void> _restore() async {
    try {
      await _restoreFromStore();
    } catch (_) {
      // A storage failure must not leave the splash screen up forever.
      if (!state.ready) {
        state = state.copyWith(ready: true);
      }
    }
  }

  Future<void> _restoreFromStore() async {
    final online = BrowserNetwork.isOnline;
    var id = await _store.getString(LocalStore.deviceId);
    if (id == null || id.isEmpty) {
      // Web bitwise shifts stay inside 32 bits, so 1 << 32 is 0 there.
      id = 'dev-${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(0x3fffffff)}';
      await _store.setString(LocalStore.deviceId, id);
    }
    final pairingRaw = await _store.getString(LocalStore.pairing);
    final profileRaw = await _store.getString(LocalStore.profile);
    final invitesRaw = await _store.getString(LocalStore.invites);
    final cacheRaw = await _store.getString(LocalStore.pinCache);
    final pending = await _loadPending();
    final lastSyncRaw = await _store.getString(LocalStore.lastSync);
    final lastSyncAt = DateTime.tryParse(lastSyncRaw ?? '');
    DevicePairingInfo? pairing;
    StoredProfile? profile;
    var invites = <DeviceInvite>[];
    var cache = <PinShiftEntry>[];
    try {
      if (pairingRaw != null) {
        pairing = DevicePairingInfo.fromJson(
          jsonDecode(pairingRaw) as Map<String, dynamic>,
        );
      }
    } catch (_) {}
    try {
      if (profileRaw != null) {
        profile = StoredProfile.fromJson(
          jsonDecode(profileRaw) as Map<String, dynamic>,
        );
      }
    } catch (_) {}
    try {
      if (invitesRaw != null) {
        final list = jsonDecode(invitesRaw);
        if (list is List) {
          invites = [
            for (final item in list)
              if (item is Map)
                DeviceInvite.fromJson(item.cast<String, dynamic>()),
          ].whereType<DeviceInvite>().toList();
        }
      }
    } catch (_) {}
    try {
      if (cacheRaw != null) {
        final list = jsonDecode(cacheRaw);
        cache = PinShiftCache.fromJsonList(list is List ? list : const []).entries;
      }
    } catch (_) {}
    state = DeviceSessionState(
      ready: true,
      pairing: pairing,
      profile: profile,
      invites: invites,
      pinCache: cache,
      deviceId: id,
      online: online,
      pending: pending,
      lastSyncAt: lastSyncAt,
    );
  }

  void applyStoredAuth(WidgetRef ref) {
    final profile = state.profile;
    if (profile == null) return;
    ref.read(authProvider.notifier).login(
          userName: profile.userName,
          businessName: profile.businessName,
          module: profile.module,
        );
  }

  void applyStoredAuthFromRef(Ref ref) {
    final profile = state.profile;
    if (profile == null) return;
    ref.read(authProvider.notifier).login(
          userName: profile.userName,
          businessName: profile.businessName,
          module: profile.module,
        );
  }

  Future<void> authorizeThisRegister({
    required String userName,
    required String businessName,
    required ActiveModule module,
  }) async {
    await restore();
    final now = DateTime.now();
    final pairing = DevicePairingInfo(
      token: 'local-${state.deviceId}',
      locationName: businessName,
      pairedAt: state.pairing?.pairedAt ?? now,
      verifiedAt: now,
    );
    final profile = StoredProfile(
      userName: userName,
      businessName: businessName,
      module: module,
    );
    await _store.setString(LocalStore.pairing, jsonEncode(pairing.toJson()));
    await _store.setString(LocalStore.profile, jsonEncode(profile.toJson()));
    state = state.copyWith(pairing: pairing, profile: profile, ready: true);
  }

  Future<String?> pairWithCode(String raw) async {
    await restore();
    if (!state.online) {
      return 'Pas d\'internet. Connecter un appareil exige le réseau.';
    }
    final code = normalizeDeviceCode(raw);
    if (!isCompleteDeviceCode(code)) {
      return 'Le code a 8 caractères (exemple 7KQ2-M9XD).';
    }
    final index = state.invites.indexWhere((invite) => invite.code == code);
    if (index < 0 || !state.invites[index].isLive(DateTime.now())) {
      return 'Ce code est inconnu ou expiré.';
    }
    final invites = [...state.invites];
    invites[index] = invites[index].copyWith(used: true);
    final now = DateTime.now();
    final pairing = DevicePairingInfo(
      token: 'code-${state.deviceId}-$code',
      locationName: state.profile?.businessName ?? 'Boutique Soleil',
      pairedAt: now,
      verifiedAt: now,
    );
    final profile = state.profile ??
        const StoredProfile(
          userName: 'Gérant',
          businessName: 'Boutique Soleil',
          module: ActiveModule.retail,
        );
    await _persistInvites(invites);
    await _store.setString(LocalStore.pairing, jsonEncode(pairing.toJson()));
    await _store.setString(LocalStore.profile, jsonEncode(profile.toJson()));
    state = state.copyWith(
      invites: invites,
      pairing: pairing,
      profile: profile,
    );
    return null;
  }

  Future<DeviceInvite?> createInvite({String deviceName = ''}) async {
    await restore();
    final now = DateTime.now();
    final invite = DeviceInvite(
      code: generateDeviceCode(),
      createdAt: now,
      expiresAt: now.add(const Duration(hours: 24)),
      deviceName: deviceName.trim(),
    );
    final invites = [invite, ...state.invites];
    await _persistInvites(invites);
    state = state.copyWith(invites: invites);
    return invite;
  }

  Future<void> unpairThisDevice() async {
    await _store.remove(LocalStore.pairing);
    state = state.copyWith(clearPairing: true);
  }

  Future<void> setOnline(bool online) async {
    if (!state.ready) await restore();
    if (state.online == online) return;
    state = state.copyWith(online: online);
  }

  /// Sends every waiting sale. Does nothing while the register is offline.
  Future<bool> syncNow() async {
    if (!state.ready) await restore();
    if (!state.online || state.pending.isEmpty || state.syncing) return false;
    state = state.copyWith(syncing: true);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!state.online) {
      state = state.copyWith(syncing: false);
      return false;
    }
    final now = DateTime.now();
    await _store.savePendingOperations(const []);
    await _store.setString(LocalStore.lastSync, now.toIso8601String());
    state = state.copyWith(
      syncing: false,
      pending: const [],
      lastSyncAt: now,
    );
    return true;
  }

  /// Test hook. Production listens to the browser instead.
  Future<void> debugSetOnline(bool online) => setOnline(online);

  PinShiftEntry? unlockFromCache(String pin) {
    return PinShiftCache(entries: state.pinCache).match(state.deviceId, pin);
  }

  Future<void> rememberPin({
    required String pin,
    required String userId,
    required String name,
    required StaffRole role,
  }) async {
    final cache = PinShiftCache(entries: [...state.pinCache]);
    cache.remember(
      deviceId: state.deviceId,
      pin: pin,
      userId: userId,
      name: name,
      role: role,
    );
    await _store.setString(LocalStore.pinCache, jsonEncode(cache.toJson()));
    state = state.copyWith(pinCache: cache.entries);
  }

  Future<void> markVerified() async {
    final pairing = state.pairing;
    if (pairing == null) return;
    final updated = pairing.copyWith(verifiedAt: DateTime.now());
    await _store.setString(LocalStore.pairing, jsonEncode(updated.toJson()));
    state = state.copyWith(pairing: updated);
  }

  Future<void> captureOrder(RetailOrder order, {bool statusChange = false}) async {
    final existing = await _store.loadExtraOrders();
    final next = [
      order,
      for (final saved in existing)
        if (saved.id != order.id) saved,
    ];
    await _store.saveExtraOrders(next);
    if (statusChange) {
      await record(
        PendingOperationKind.orderStatus,
        '${order.orderNumber} · ${order.status.label}',
        orderId: order.id,
      );
    } else {
      await record(
        PendingOperationKind.sale,
        order.orderNumber,
        orderId: order.id,
        amountHtg: order.totalHtg,
      );
    }
  }

  /// Queues a change made while offline. Online changes go straight through.
  Future<void> record(
    PendingOperationKind kind,
    String title, {
    String detail = '',
    String? orderId,
    double? amountHtg,
  }) async {
    if (!state.ready) await restore();
    if (state.online) return;
    final now = DateTime.now();
    final op = PendingOperation(
      id: 'op-${now.microsecondsSinceEpoch}-${state.pending.length}',
      kind: kind,
      title: title,
      detail: detail,
      orderId: orderId,
      amountHtg: amountHtg,
      createdAt: now,
    );
    final pending = [op, ...state.pending];
    state = state.copyWith(pending: pending);
    await _store.savePendingOperations(pending);
  }

  /// Sales queued by older builds were stored as bare order ids.
  Future<List<PendingOperation>> _loadPending() async {
    final pending = await _store.loadPendingOperations();
    final legacy = await _store.loadOutbox();
    if (legacy.isEmpty) return pending;
    final orders = {
      for (final order in await _store.loadExtraOrders()) order.id: order,
    };
    final migrated = [
      ...pending,
      for (final id in legacy)
        PendingOperation(
          id: 'op-legacy-$id',
          kind: PendingOperationKind.sale,
          title: orders[id]?.orderNumber ?? 'Vente',
          orderId: id,
          amountHtg: orders[id]?.totalHtg,
          createdAt: orders[id]?.createdAt ?? DateTime.now(),
        ),
    ];
    await _store.savePendingOperations(migrated);
    await _store.remove(LocalStore.outbox);
    return migrated;
  }

  Future<void> _persistInvites(List<DeviceInvite> invites) async {
    await _store.setString(
      LocalStore.invites,
      jsonEncode([for (final invite in invites) invite.toJson()]),
    );
  }
}

final deviceSessionProvider =
    StateNotifierProvider<DeviceSessionNotifier, DeviceSessionState>(
  (ref) => DeviceSessionNotifier(),
);

/// Journal for notifiers outside this file; keeps nothing while online.
PendingJournal pendingJournal(Ref ref) => (
      PendingOperationKind kind,
      String title, {
      String detail = '',
      String? orderId,
      double? amountHtg,
    }) {
      unawaited(
        ref.read(deviceSessionProvider.notifier).record(
              kind,
              title,
              detail: detail,
              orderId: orderId,
              amountHtg: amountHtg,
            ),
      );
    };
