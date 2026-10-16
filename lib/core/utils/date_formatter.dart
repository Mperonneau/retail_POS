import 'package:intl/intl.dart';

class DateFormatter {
  DateFormatter._();

  /// e.g. "Mar 3, 2026"
  static String shortDate(DateTime dt) => DateFormat('MMM d, y').format(dt);

  /// e.g. "Today, Mar 3"  — used in page subtitles
  static String todayLabel() =>
      'Today, ${DateFormat('MMM d').format(DateTime.now())}';

  /// e.g. "Tue, Mar 3"  — used in the top bar
  static String topBarDate() =>
      DateFormat('EEE, MMM d').format(DateTime.now());

  /// e.g. "13:42"
  static String timeOfDay(DateTime dt) => DateFormat('HH:mm').format(dt);
}
