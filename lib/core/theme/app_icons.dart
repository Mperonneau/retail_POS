import 'package:flutter/widgets.dart';

/// Family registered in `main()` from the full Material Icons font.
const String kFullIconFamily = 'MaterialIconsFull';

/// Icons added after the first deploys. Phones that cached the old
/// `MaterialIcons` subset have no glyph for them, so they draw from the
/// full font under its own family name.
abstract final class AppIcons {
  static const IconData sync = IconData(0xe62f, fontFamily: kFullIconFamily);
  static const IconData devices = IconData(0xe1cb, fontFamily: kFullIconFamily);
  static const IconData systemUpdateAlt =
      IconData(0xe637, fontFamily: kFullIconFamily);
  static const IconData cloudUploadOutlined =
      IconData(0xef64, fontFamily: kFullIconFamily);
  static const IconData wifiOff = IconData(0xe6eb, fontFamily: kFullIconFamily);
}
