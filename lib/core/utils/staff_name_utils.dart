/// First word of a display name, for "who is signed in" (e.g. `Jean-Marc Dupont` → `Jean-Marc`).
String firstNameFromDisplayName(String? fullName) {
  if (fullName == null || fullName.trim().isEmpty) return 'Staff';
  final s = fullName.trim();
  final space = s.indexOf(' ');
  if (space == -1) return s;
  return s.substring(0, space);
}

/// Whether [orderWaiter] (short label on mock orders) refers to [staffFullName] from the directory.
/// Matches full name, first name, or last name (case-insensitive).
bool orderWaiterMatchesStaffFullName(String orderWaiter, String staffFullName) {
  final o = orderWaiter.trim().toLowerCase();
  final s = staffFullName.trim().toLowerCase();
  if (o.isEmpty || s.isEmpty) return false;
  if (s == o) return true;
  final parts = s.split(RegExp(r'\s+'));
  if (parts.isNotEmpty && parts.first == o) return true;
  if (parts.length > 1 && parts.last == o) return true;
  return false;
}
