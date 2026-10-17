import 'package:intl/intl.dart';

class DateFormatter {
  DateFormatter._();

  /// e.g. "3 mars 2026"
  static String shortDate(DateTime dt) => DateFormat('d MMM y', 'fr').format(dt);

  /// e.g. "Aujourd'hui, 3 mars" — used in page subtitles
  static String todayLabel() =>
      "Aujourd'hui, ${DateFormat('d MMM', 'fr').format(DateTime.now())}";

  /// e.g. "mar. 3 mars" — used in the top bar
  static String topBarDate() =>
      DateFormat('EEE d MMM', 'fr').format(DateTime.now());

  /// e.g. "13:42"
  static String timeOfDay(DateTime dt) => DateFormat('HH:mm').format(dt);
}
