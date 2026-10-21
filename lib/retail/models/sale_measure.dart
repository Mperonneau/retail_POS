/// How a catalogue price is read.
///
/// [piece] is one price for one piece. [roll] is a price per inch, with a
/// separate price for the whole roll. [pack] is a case price plus a unit price.
enum SaleMode { piece, roll, pack }

SaleMode saleModeFromWire(String? raw) {
  return switch (raw) {
    'roll' => SaleMode.roll,
    'case' => SaleMode.pack,
    _ => SaleMode.piece,
  };
}

extension SaleModeWire on SaleMode {
  String get wire => switch (this) {
    SaleMode.piece => 'piece',
    SaleMode.roll => 'roll',
    SaleMode.pack => 'case',
  };
}

/// What the cashier or the customer chose for one line.
enum MeasureKind { plain, fullRoll, width, casePack, each }

class MeasureChoice {
  const MeasureChoice.plain() : this._(MeasureKind.plain, 0);
  const MeasureChoice.fullRoll() : this._(MeasureKind.fullRoll, 0);
  const MeasureChoice.width(int width) : this._(MeasureKind.width, width);
  const MeasureChoice.casePack() : this._(MeasureKind.casePack, 0);
  const MeasureChoice.each() : this._(MeasureKind.each, 0);
  const MeasureChoice._(this.kind, this.width);

  final MeasureKind kind;

  /// Inches, only for [MeasureKind.width].
  final int width;

  String get key => switch (kind) {
    MeasureKind.plain => '',
    MeasureKind.fullRoll => 'roll',
    MeasureKind.width => 'w:$width',
    MeasureKind.casePack => 'case',
    MeasureKind.each => 'unit',
  };

  /// Value sent to the vitrine so the server can reprice the line.
  String get wire => switch (kind) {
    MeasureKind.plain => '',
    MeasureKind.fullRoll => 'roll',
    MeasureKind.width => 'cut',
    MeasureKind.casePack => 'case',
    MeasureKind.each => 'unit',
  };

  int unitsEach({
    required int rollWidth,
    required int unitsPerCase,
  }) {
    return switch (kind) {
      MeasureKind.plain => 1,
      MeasureKind.fullRoll => rollWidth < 1 ? 1 : rollWidth,
      MeasureKind.width => width < 1 ? 1 : width,
      MeasureKind.casePack => unitsPerCase < 1 ? 1 : unitsPerCase,
      MeasureKind.each => 1,
    };
  }

  double baseHtg({
    required double priceHtg,
    required double rollPriceHtg,
    required double casePriceHtg,
  }) {
    return switch (kind) {
      MeasureKind.plain => priceHtg,
      MeasureKind.fullRoll => rollPriceHtg,
      MeasureKind.width => priceHtg * width,
      MeasureKind.casePack => casePriceHtg,
      MeasureKind.each => priceHtg,
    };
  }

  String label({required int unitsPerCase}) {
    return switch (kind) {
      MeasureKind.plain => '',
      MeasureKind.fullRoll => 'Rouleau entier',
      MeasureKind.width => '$width po',
      MeasureKind.casePack => 'Caisse de $unitsPerCase',
      MeasureKind.each => "À l'unité",
    };
  }

  /// Null when this choice can be sold for [mode].
  String? rejectReason({required SaleMode mode, required int minWidth}) {
    if (mode == SaleMode.roll) {
      if (kind == MeasureKind.fullRoll) return null;
      if (kind == MeasureKind.width) {
        if (width < 1) return 'Indiquez la largeur en pouces.';
        if (width < minWidth) return 'Le minimum est $minWidth po.';
        if (width > 10000) return 'Cette largeur est trop grande.';
        return null;
      }
      return 'Choisissez le rouleau entier ou une largeur.';
    }
    if (mode == SaleMode.pack) {
      if (kind == MeasureKind.casePack || kind == MeasureKind.each) return null;
      return 'Choisissez une caisse ou une unité.';
    }
    return null;
  }
}

/// Reads the first label written on a receipt ("36 po", "Rouleau entier"…).
MeasureChoice measureFromLabel(String label) {
  final first = label.split(',').first.trim();
  if (first == 'Rouleau entier') return const MeasureChoice.fullRoll();
  if (first == "À l'unité") return const MeasureChoice.each();
  if (first.startsWith('Caisse de ')) return const MeasureChoice.casePack();
  final match = RegExp(r'^(\d+) po$').firstMatch(first);
  if (match != null) {
    return MeasureChoice.width(int.parse(match.group(1)!));
  }
  return const MeasureChoice.plain();
}

/// Keeps a parsed label only when it matches the product's sale mode.
MeasureChoice measureForMode(SaleMode mode, String label) {
  final parsed = measureFromLabel(label);
  if (mode == SaleMode.roll &&
      (parsed.kind == MeasureKind.fullRoll || parsed.kind == MeasureKind.width)) {
    return parsed;
  }
  if (mode == SaleMode.pack &&
      (parsed.kind == MeasureKind.casePack || parsed.kind == MeasureKind.each)) {
    return parsed;
  }
  return const MeasureChoice.plain();
}
