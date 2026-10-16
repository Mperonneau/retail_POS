import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/staff_role.dart';
import 'staff_directory_provider.dart';

export '../models/staff_role.dart';

class StaffSessionState {
  final String employeeId;
  final String employeeName;
  final StaffRole role;
  final DateTime lastActivityAt;

  const StaffSessionState({
    required this.employeeId,
    required this.employeeName,
    required this.role,
    required this.lastActivityAt,
  });

  StaffSessionState copyWith({
    String? employeeId,
    String? employeeName,
    StaffRole? role,
    DateTime? lastActivityAt,
  }) =>
      StaffSessionState(
        employeeId: employeeId ?? this.employeeId,
        employeeName: employeeName ?? this.employeeName,
        role: role ?? this.role,
        lastActivityAt: lastActivityAt ?? this.lastActivityAt,
      );
}

class StaffSessionNotifier extends StateNotifier<StaffSessionState?> {
  StaffSessionNotifier(this._ref) : super(null);

  final Ref _ref;

  Timer? _idleTimer;

  bool get hasActiveSession => state != null;

  @override
  void dispose() {
    _idleTimer?.cancel();
    super.dispose();
  }

  /// Fallback demo PINs when no directory row matches (dev convenience).
  StaffRole? _roleForDemoPin(String pin) {
    switch (pin) {
      case '1234':
        return StaffRole.cashier;
      case '1111':
        return StaffRole.waiter;
      case '2222':
        return StaffRole.manager;
      case '3333':
        return StaffRole.admin;
      case '4444':
        return StaffRole.kitchen;
      case '8888':
        return StaffRole.reception;
      default:
        return null;
    }
  }

  String _demoNameForRole(StaffRole role) {
    return switch (role) {
      StaffRole.waiter => 'Marie (Waiter)',
      StaffRole.cashier => 'Jean (Cashier)',
      StaffRole.reception => 'Sophie (Reception)',
      StaffRole.manager => 'Manager',
      StaffRole.admin => 'Admin',
      StaffRole.kitchen => 'Kitchen',
    };
  }

  /// Returns `null` if PIN is invalid.
  String? signInWithPin(String pin) {
    if (pin.length != 4) return 'Enter a 4-digit PIN.';

    final directory = _ref.read(staffDirectoryProvider.notifier);
    final fromDirectory = directory.findActiveByPin(pin);
    if (fromDirectory != null) {
      final now = DateTime.now();
      state = StaffSessionState(
        employeeId: fromDirectory.id,
        employeeName: fromDirectory.fullName,
        role: fromDirectory.role,
        lastActivityAt: now,
      );
      _scheduleIdleCheck();
      return null;
    }

    final role = _roleForDemoPin(pin);
    if (role == null) {
      return 'Invalid PIN. Use a staff PIN from Settings or a demo code (e.g. 1234, 1111, 8888 reception).';
    }
    final now = DateTime.now();
    state = StaffSessionState(
      employeeId: 'emp_${pin}_demo',
      employeeName: _demoNameForRole(role),
      role: role,
      lastActivityAt: now,
    );
    _scheduleIdleCheck();
    return null;
  }

  void recordActivity() {
    final s = state;
    if (s == null) return;
    state = s.copyWith(lastActivityAt: DateTime.now());
    _scheduleIdleCheck();
  }

  void _scheduleIdleCheck() {
    _idleTimer?.cancel();
    final s = state;
    if (s == null) return;

    if (isRoleExemptFromIdleLogout(s.role)) {
      _idleTimer = null;
      return;
    }

    final idle = effectiveIdleDuration(s.role);
    _idleTimer = Timer(idle, () {
      final current = state;
      if (current == null) return;
      final elapsed = DateTime.now().difference(current.lastActivityAt);
      if (elapsed >= idle) {
        clear();
      } else {
        _scheduleIdleCheck();
      }
    });
  }

  void clear() {
    _idleTimer?.cancel();
    _idleTimer = null;
    state = null;
  }
}

final staffSessionProvider =
    StateNotifierProvider<StaffSessionNotifier, StaffSessionState?>(
  (ref) => StaffSessionNotifier(ref),
);
