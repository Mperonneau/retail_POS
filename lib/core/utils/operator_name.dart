/// The person at the register. A signed-in employee wins over the account name.
String currentOperatorName({String? staffName, String? accountName}) {
  final staff = staffName?.trim() ?? '';
  if (staff.isNotEmpty) return staff;
  final account = accountName?.trim() ?? '';
  if (account.isNotEmpty) return account;
  return 'Gérant';
}
