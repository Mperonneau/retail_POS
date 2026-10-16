import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../permissions/default_role_permissions.dart';
import '../permissions/permission_id.dart';
import 'auth_provider.dart';
import 'staff_session_provider.dart';

class PermissionSettingsState {
  /// Editable defaults per module × role (Settings → Permissions).
  final Map<ActiveModule, Map<StaffRole, Map<PermissionId, bool>>> roleDefaults;

  /// Per-employee overrides; `null` value = inherit from role default.
  final Map<String, Map<PermissionId, bool?>> userOverrides;

  const PermissionSettingsState({
    required this.roleDefaults,
    required this.userOverrides,
  });

  factory PermissionSettingsState.initial() {
    final defaults = <ActiveModule, Map<StaffRole, Map<PermissionId, bool>>>{};
    for (final m in ActiveModule.values) {
      defaults[m] = {
        for (final r in StaffRole.values)
          r: Map<PermissionId, bool>.from(defaultPermissionsForRole(m, r)),
      };
    }
    return PermissionSettingsState(roleDefaults: defaults, userOverrides: {});
  }

  PermissionSettingsState copyWith({
    Map<ActiveModule, Map<StaffRole, Map<PermissionId, bool>>>? roleDefaults,
    Map<String, Map<PermissionId, bool?>>? userOverrides,
  }) =>
      PermissionSettingsState(
        roleDefaults: roleDefaults ?? this.roleDefaults,
        userOverrides: userOverrides ?? this.userOverrides,
      );
}

class PermissionSettingsNotifier extends StateNotifier<PermissionSettingsState> {
  PermissionSettingsNotifier() : super(PermissionSettingsState.initial());

  void setRoleDefault(
    ActiveModule module,
    StaffRole role,
    PermissionId id,
    bool value,
  ) {
    final next = Map<ActiveModule, Map<StaffRole, Map<PermissionId, bool>>>.from(
      state.roleDefaults,
    );
    final modMap = Map<StaffRole, Map<PermissionId, bool>>.from(next[module]!);
    final roleMap = Map<PermissionId, bool>.from(modMap[role]!);
    roleMap[id] = value;
    modMap[role] = roleMap;
    next[module] = modMap;
    state = state.copyWith(roleDefaults: next);
  }

  void setUserOverride(String employeeId, PermissionId id, bool? value) {
    final ov = Map<String, Map<PermissionId, bool?>>.from(state.userOverrides);
    final row = Map<PermissionId, bool?>.from(ov[employeeId] ?? {});
    if (value == null) {
      row.remove(id);
    } else {
      row[id] = value;
    }
    if (row.isEmpty) {
      ov.remove(employeeId);
    } else {
      ov[employeeId] = row;
    }
    state = state.copyWith(userOverrides: ov);
  }

  void clearUserOverrides(String employeeId) {
    final ov = Map<String, Map<PermissionId, bool?>>.from(state.userOverrides);
    ov.remove(employeeId);
    state = state.copyWith(userOverrides: ov);
  }
}

final permissionSettingsProvider =
    StateNotifierProvider<PermissionSettingsNotifier, PermissionSettingsState>(
  (ref) => PermissionSettingsNotifier(),
);

/// Effective permissions for the signed-in staff member (defaults + per-user overrides).
final effectivePermissionsProvider = Provider<Map<PermissionId, bool>>((ref) {
  final key = ref.watch(
    staffSessionProvider.select((s) {
      if (s == null) return null;
      return '${s.employeeId}|${s.role.index}';
    }),
  );
  final module = ref.watch(authProvider.select((a) => a.module));
  ref.watch(permissionSettingsProvider);

  if (key == null) {
    return {for (final p in PermissionId.values) p: false};
  }

  final session = ref.read(staffSessionProvider);
  if (session == null) {
    return {for (final p in PermissionId.values) p: false};
  }

  final settings = ref.read(permissionSettingsProvider);
  final base = settings.roleDefaults[module]![session.role]!;
  final ov = settings.userOverrides[session.employeeId];

  return {
    for (final p in PermissionId.values)
      p: (ov?[p] ?? base[p]) ?? false,
  };
});
