import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/staff_directory_entry.dart';
import '../models/staff_role.dart';

class StaffDirectoryNotifier extends StateNotifier<List<StaffDirectoryEntry>> {
  StaffDirectoryNotifier() : super(_seed);

  static final _seed = <StaffDirectoryEntry>[
    const StaffDirectoryEntry(
      id: 'seed_1',
      fullName: 'Jean-Marc Dupont',
      email: 'jm.dupont@karibe.ht',
      phone: '+509 3456-7890',
      role: StaffRole.admin,
      pinDigits: '3333',
      isActive: true,
    ),
    const StaffDirectoryEntry(
      id: 'seed_2',
      fullName: 'Marie-Carmel Joseph',
      email: 'marie.joseph@karibe.ht',
      phone: '+509 3789-1122',
      role: StaffRole.seller,
      pinDigits: '1111',
      isActive: true,
    ),
    const StaffDirectoryEntry(
      id: 'seed_3',
      fullName: 'Pierre Laguerre',
      email: 'pierre.l@karibe.ht',
      phone: '+509 3122-4455',
      role: StaffRole.seller,
      pinDigits: '5555',
      isActive: true,
    ),
    const StaffDirectoryEntry(
      id: 'seed_4',
      fullName: 'Roseline Janvier',
      email: 'roseline.j@karibe.ht',
      phone: '+509 3344-7788',
      role: StaffRole.cashier,
      pinDigits: '1234',
      isActive: true,
    ),
    const StaffDirectoryEntry(
      id: 'seed_5',
      fullName: 'Marcel Toussaint',
      email: 'marcel.t@karibe.ht',
      phone: '+509 3999-0001',
      role: StaffRole.cashier,
      pinDigits: '6666',
      isActive: false,
    ),
    const StaffDirectoryEntry(
      id: 'seed_6',
      fullName: 'Claudine Bernard',
      email: 'claudine.b@karibe.ht',
      phone: '+509 3555-6600',
      role: StaffRole.seller,
      pinDigits: '7777',
      isActive: true,
    ),
    const StaffDirectoryEntry(
      id: 'seed_7',
      fullName: 'Sophie Laurent',
      email: 'sophie.l@karibe.ht',
      phone: '+509 3888-2200',
      role: StaffRole.seller,
      pinDigits: '8888',
      isActive: true,
    ),
  ];

  /// First active employee with this 4-digit PIN, or null.
  StaffDirectoryEntry? findActiveByPin(String pin) {
    for (final e in state) {
      if (e.isActive && e.pinDigits == pin) return e;
    }
    return null;
  }

  /// Whether [pin] is already used by someone other than [excludeId].
  bool isPinTaken(String pin, {String? excludeId}) {
    for (final e in state) {
      if (e.pinDigits == pin && e.id != excludeId) return true;
    }
    return false;
  }

  /// Whether phone is used by another row.
  bool isPhoneTaken(String phone, {String? excludeId}) {
    final normalized = phone.trim();
    for (final e in state) {
      if (e.phone.trim() == normalized && e.id != excludeId) return true;
    }
    return false;
  }

  void add(StaffDirectoryEntry entry) {
    state = [...state, entry];
  }

  void update(StaffDirectoryEntry entry) {
    state = [
      for (final e in state)
        if (e.id == entry.id) entry else e,
    ];
  }

  void remove(String id) {
    state = [for (final e in state) if (e.id != id) e];
  }
}

final staffDirectoryProvider =
    StateNotifierProvider<StaffDirectoryNotifier, List<StaffDirectoryEntry>>(
  (ref) => StaffDirectoryNotifier(),
);
