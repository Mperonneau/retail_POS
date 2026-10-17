import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../utils/order_add_items_policy.dart';
import '../utils/order_bill_estimate.dart';

class MockRoom {
  final int id;
  final String number;
  final String type;
  final int floor;
  final String
      status; // available, occupied, checkout_today, maintenance, cleaning
  final String? guestName;
  final String? checkInDate;
  final String? checkOutDate;
  final String? guestIdType; // Passport, Licence, ID, Other
  final String? guestIdNumber;

  /// When status is occupied: true = short stay, false = overnight, null = unknown (treated as overnight).
  final bool? isShortStay;
  // Overnight pricing (per night)
  final double priceHtg;
  final double priceUsd;
  // Short-stay: price per hour (HTG/USD) + min/max hours. Total = hours × price per hour.
  final double? shortStayPricePerHourHtg;
  final double? shortStayPricePerHourUsd;
  final int? shortStayMinHours;
  final int? shortStayMaxHours;
  final String? housekeeper;

  /// Parallel to occupancy: scheduled housekeeping work (stay-over or turnover).
  /// Pipe-separated service keys (see [kHotelCleaningServiceCatalog]), e.g. `full_cleaning|towel_change`.
  /// Null/empty = no housekeeping ticket.
  final String? cleaningTaskType;

  /// Staff assigned to the scheduled services.
  final String? cleaningAssignee;

  /// Extra instructions from front desk (specific guest requests, timing, etc.).
  final String? cleaningNotes;

  /// Contact captured at check-in (for guest list / checkout save).
  final String? guestPhone;
  final String? guestEmail;

  const MockRoom({
    required this.id,
    required this.number,
    required this.type,
    required this.floor,
    required this.status,
    this.guestName,
    this.checkInDate,
    this.checkOutDate,
    this.guestIdType,
    this.guestIdNumber,
    this.isShortStay,
    required this.priceHtg,
    required this.priceUsd,
    this.shortStayPricePerHourHtg,
    this.shortStayPricePerHourUsd,
    this.shortStayMinHours,
    this.shortStayMaxHours,
    this.housekeeper,
    this.cleaningTaskType,
    this.cleaningAssignee,
    this.cleaningNotes,
    this.guestPhone,
    this.guestEmail,
  });

  bool get hasCleaningTask => parseCleaningServiceKeys(cleaningTaskType).isNotEmpty;

  bool get supportsShortStay {
    if (shortStayPricePerHourHtg == null && shortStayPricePerHourUsd == null) {
      return false;
    }
    final min = shortStayMinHours ?? 0;
    final max = shortStayMaxHours ?? 0;
    return max >= min && min > 0;
  }

  /// Ordered list of allowed short-stay durations (min, min+1, ..., max).
  List<int> get shortStayDurationOptions {
    final min = shortStayMinHours ?? 1;
    final max = shortStayMaxHours ?? 3;
    if (max < min) return [];
    return List.generate(max - min + 1, (i) => min + i);
  }

  MockRoom copyWith({
    int? id,
    String? number,
    String? type,
    int? floor,
    String? status,
    Object? guestName = _sentinel,
    Object? checkInDate = _sentinel,
    Object? checkOutDate = _sentinel,
    Object? guestIdType = _sentinel,
    Object? guestIdNumber = _sentinel,
    Object? isShortStay = _sentinel,
    double? priceHtg,
    double? priceUsd,
    Object? shortStayPricePerHourHtg = _sentinel,
    Object? shortStayPricePerHourUsd = _sentinel,
    Object? shortStayMinHours = _sentinel,
    Object? shortStayMaxHours = _sentinel,
    Object? housekeeper = _sentinel,
    Object? cleaningTaskType = _sentinel,
    Object? cleaningAssignee = _sentinel,
    Object? cleaningNotes = _sentinel,
    Object? guestPhone = _sentinel,
    Object? guestEmail = _sentinel,
    bool clearCleaningFields = false,
  }) {
    if (clearCleaningFields) {
      return MockRoom(
        id: id ?? this.id,
        number: number ?? this.number,
        type: type ?? this.type,
        floor: floor ?? this.floor,
        status: status ?? this.status,
        guestName: guestName == _sentinel ? this.guestName : guestName as String?,
        checkInDate:
            checkInDate == _sentinel ? this.checkInDate : checkInDate as String?,
        checkOutDate: checkOutDate == _sentinel
            ? this.checkOutDate
            : checkOutDate as String?,
        guestIdType:
            guestIdType == _sentinel ? this.guestIdType : guestIdType as String?,
        guestIdNumber: guestIdNumber == _sentinel
            ? this.guestIdNumber
            : guestIdNumber as String?,
        isShortStay:
            isShortStay == _sentinel ? this.isShortStay : isShortStay as bool?,
        priceHtg: priceHtg ?? this.priceHtg,
        priceUsd: priceUsd ?? this.priceUsd,
        shortStayPricePerHourHtg: shortStayPricePerHourHtg == _sentinel
            ? this.shortStayPricePerHourHtg
            : shortStayPricePerHourHtg as double?,
        shortStayPricePerHourUsd: shortStayPricePerHourUsd == _sentinel
            ? this.shortStayPricePerHourUsd
            : shortStayPricePerHourUsd as double?,
        shortStayMinHours: shortStayMinHours == _sentinel
            ? this.shortStayMinHours
            : shortStayMinHours as int?,
        shortStayMaxHours: shortStayMaxHours == _sentinel
            ? this.shortStayMaxHours
            : shortStayMaxHours as int?,
        housekeeper: null,
        cleaningTaskType: null,
        cleaningAssignee: null,
        cleaningNotes: null,
        guestPhone: guestPhone == _sentinel ? this.guestPhone : guestPhone as String?,
        guestEmail: guestEmail == _sentinel ? this.guestEmail : guestEmail as String?,
      );
    }
    return MockRoom(
      id: id ?? this.id,
      number: number ?? this.number,
      type: type ?? this.type,
      floor: floor ?? this.floor,
      status: status ?? this.status,
      guestName: guestName == _sentinel ? this.guestName : guestName as String?,
      checkInDate:
          checkInDate == _sentinel ? this.checkInDate : checkInDate as String?,
      checkOutDate: checkOutDate == _sentinel
          ? this.checkOutDate
          : checkOutDate as String?,
      guestIdType:
          guestIdType == _sentinel ? this.guestIdType : guestIdType as String?,
      guestIdNumber: guestIdNumber == _sentinel
          ? this.guestIdNumber
          : guestIdNumber as String?,
      isShortStay:
          isShortStay == _sentinel ? this.isShortStay : isShortStay as bool?,
      priceHtg: priceHtg ?? this.priceHtg,
      priceUsd: priceUsd ?? this.priceUsd,
      shortStayPricePerHourHtg: shortStayPricePerHourHtg == _sentinel
          ? this.shortStayPricePerHourHtg
          : shortStayPricePerHourHtg as double?,
      shortStayPricePerHourUsd: shortStayPricePerHourUsd == _sentinel
          ? this.shortStayPricePerHourUsd
          : shortStayPricePerHourUsd as double?,
      shortStayMinHours: shortStayMinHours == _sentinel
          ? this.shortStayMinHours
          : shortStayMinHours as int?,
      shortStayMaxHours: shortStayMaxHours == _sentinel
          ? this.shortStayMaxHours
          : shortStayMaxHours as int?,
      housekeeper:
          housekeeper == _sentinel ? this.housekeeper : housekeeper as String?,
      cleaningTaskType: cleaningTaskType == _sentinel
          ? this.cleaningTaskType
          : cleaningTaskType as String?,
      cleaningAssignee: cleaningAssignee == _sentinel
          ? this.cleaningAssignee
          : cleaningAssignee as String?,
      cleaningNotes: cleaningNotes == _sentinel
          ? this.cleaningNotes
          : cleaningNotes as String?,
      guestPhone: guestPhone == _sentinel ? this.guestPhone : guestPhone as String?,
      guestEmail: guestEmail == _sentinel ? this.guestEmail : guestEmail as String?,
    );
  }
}

/// One selectable housekeeping service (key is stored, often several joined with `|`).
class HotelCleaningServiceDef {
  final String key;
  final String title;
  final String description;

  const HotelCleaningServiceDef({
    required this.key,
    required this.title,
    required this.description,
  });
}

/// Exhaustive catalog for scheduling UI — titles are short; descriptions explain what staff does.
const List<HotelCleaningServiceDef> kHotelCleaningServiceCatalog = [
  HotelCleaningServiceDef(
    key: 'full_cleaning',
    title: 'Nettoyage complet',
    description:
        'Complete room clean, change towels & bed linens, restock bathroom amenities, trash out.',
  ),
  HotelCleaningServiceDef(
    key: 'full_turnover',
    title: 'Remise en état après départ',
    description:
        'Défaire les lits, ménage complet après le départ, vérifier le minibar et les dégâts, préparer pour le client suivant.',
  ),
  HotelCleaningServiceDef(
    key: 'deep_clean',
    title: 'Nettoyage en profondeur',
    description:
        'Heavy clean: bathroom detail, floors, dusting, inside windows, under furniture when needed.',
  ),
  HotelCleaningServiceDef(
    key: 'light_tidy',
    title: 'Rangement léger',
    description:
        'Remise en ordre rapide, essuyer les surfaces, regonfler les oreillers — client encore dans la chambre.',
  ),
  HotelCleaningServiceDef(
    key: 'stayover_service',
    title: 'Service de séjour',
    description:
        'Client présent : respecter les affaires, changer les serviettes utilisées, rafraîchir la salle de bain.',
  ),
  HotelCleaningServiceDef(
    key: 'towel_change',
    title: 'Changement de linge',
    description:
        'Changer seulement les serviettes et/ou le linge de lit ; pas de ménage complet sauf si combiné à d\'autres tâches.',
  ),
  HotelCleaningServiceDef(
    key: 'bed_make',
    title: 'Faire les lits',
    description: 'Make beds, fluff pillows, align covers — may skip full linen change.',
  ),
  HotelCleaningServiceDef(
    key: 'bathroom_refresh',
    title: 'Rafraîchissement de la salle de bain',
    description:
        'Désinfecter les équipements, le miroir et la douche ; remplir le savon, le shampoing et le papier toilette.',
  ),
  HotelCleaningServiceDef(
    key: 'vacuum_mop',
    title: 'Aspirer et laver les sols',
    description: 'Tous les sols — aspirer les tapis, laver les sols durs.',
  ),
  HotelCleaningServiceDef(
    key: 'trash_recycling',
    title: 'Déchets et recyclage',
    description: 'Vider les poubelles, changer les sacs, trier selon la consigne de l\'hôtel.',
  ),
  HotelCleaningServiceDef(
    key: 'minibar_restock',
    title: 'Réassort minibar et snacks',
    description: 'Réapprovisionner le minibar, noter les consommations et vérifier les dates.',
  ),
  HotelCleaningServiceDef(
    key: 'amenities_restock',
    title: 'Réassort des commodités',
    description:
        'Soaps, shampoos, lotions, tissues, coffee/tea supplies, water bottles as needed.',
  ),
  HotelCleaningServiceDef(
    key: 'turn_down',
    title: 'Préparation du soir',
    description:
        'Tirer les rideaux, préparer la table de nuit, chocolat ou mot de bienvenue selon la norme.',
  ),
  HotelCleaningServiceDef(
    key: 'windows_glass',
    title: 'Fenêtres et miroirs',
    description: 'Interior glass: windows, mirrors, glass tables — streak-free finish.',
  ),
  HotelCleaningServiceDef(
    key: 'balcony_terrace',
    title: 'Balcon / terrasse',
    description: 'Sweep, wipe surfaces, tidy outdoor furniture if applicable.',
  ),
  HotelCleaningServiceDef(
    key: 'disinfect_high_touch',
    title: 'Désinfection des surfaces',
    description:
        'Remotes, phones, switches, handles, desk areas — hygiene-focused pass.',
  ),
  HotelCleaningServiceDef(
    key: 'laundry_coordination',
    title: 'Blanchisserie client',
    description:
        'Récupérer ou livrer le linge du client, ou coordonner avec la blanchisserie — voir les notes pour l\'horaire.',
  ),
  HotelCleaningServiceDef(
    key: 'lost_found_check',
    title: 'Vérification des objets trouvés',
    description:
        'Vérifier sous le lit, dans les placards et les tiroirs les objets oubliés après le départ.',
  ),
  HotelCleaningServiceDef(
    key: 'maintenance_report',
    title: 'Signaler un problème d\'entretien',
    description:
        'Signaler le matériel cassé, les fuites et les problèmes de clim ou de TV — détails dans les notes.',
  ),
];

/// Short labels for chips and compact UI (includes legacy keys not in [kHotelCleaningServiceCatalog]).
final Map<String, String> kHotelCleaningTaskLabels = {
  for (final d in kHotelCleaningServiceCatalog) d.key: d.title,
};

/// Decode pipe-separated keys from [MockRoom.cleaningTaskType].
List<String> parseCleaningServiceKeys(String? raw) {
  if (raw == null || raw.trim().isEmpty) return [];
  return raw
      .split('|')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

/// Encode selected keys for storage.
String encodeCleaningServiceKeys(List<String> keys) => keys.join('|');

/// Human-readable summary for lists and sheets (uses catalog titles; unknown keys shown as-is).
String formatCleaningServicesDisplay(String? raw) {
  final keys = parseCleaningServiceKeys(raw);
  if (keys.isEmpty) return '';
  return keys.map((k) => kHotelCleaningTaskLabels[k] ?? k).join(' · ');
}

/// Default cleaner names for mock assignment.
const List<String> kHotelHousekeeperNames = [
  'Josiane',
  'Marie-Rose',
  'Claudette',
  'Nadège',
  'Yolande',
];

class MockReservation {
  final int id;
  final String confirmationCode;
  final String guestName;
  final String phone;
  final String? email;
  final String? notes;

  /// Type of ID: Licence, ID, Passport, Other
  final String? idType;
  final String? idNumber;
  final String roomType;
  final String? roomNumber;
  final String checkInDate;
  final String checkOutDate;
  final int nights;
  final int guests;
  final double depositHtg;
  final bool isPaid;
  final String status; // confirmed, checked_in, checked_out, cancelled

  /// The specific [MockRoom.id] this reservation blocks for its date range.
  /// Null means no room assigned yet (legacy / type-only reservation).
  final int? roomId;

  const MockReservation({
    required this.id,
    required this.confirmationCode,
    required this.guestName,
    required this.phone,
    this.email,
    this.notes,
    this.idType,
    this.idNumber,
    required this.roomType,
    this.roomNumber,
    required this.checkInDate,
    required this.checkOutDate,
    required this.nights,
    required this.guests,
    required this.depositHtg,
    this.isPaid = false,
    required this.status,
    this.roomId,
  });

  /// Returns true when this reservation's period overlaps [checkIn, checkOut).
  /// Cancelled and checked_out reservations never conflict.
  bool overlapsWith(DateTime checkIn, DateTime checkOut) {
    if (status == 'cancelled' || status == 'checked_out') return false;
    final resIn = parseHotelCalendarDate(checkInDate);
    final resOut = parseHotelCalendarDate(checkOutDate);
    if (resIn == null || resOut == null) return false;
    final ci = DateTime(checkIn.year, checkIn.month, checkIn.day);
    final co = DateTime(checkOut.year, checkOut.month, checkOut.day);
    final ri = DateTime(resIn.year, resIn.month, resIn.day);
    final ro = DateTime(resOut.year, resOut.month, resOut.day);
    return ri.isBefore(co) && ro.isAfter(ci);
  }

  MockReservation copyWith({
    int? id,
    String? confirmationCode,
    String? guestName,
    String? phone,
    Object? email = _sentinel,
    Object? notes = _sentinel,
    Object? idType = _sentinel,
    Object? idNumber = _sentinel,
    String? roomType,
    Object? roomNumber = _sentinel,
    String? checkInDate,
    String? checkOutDate,
    int? nights,
    int? guests,
    double? depositHtg,
    bool? isPaid,
    String? status,
    Object? roomId = _sentinel,
  }) {
    return MockReservation(
      id: id ?? this.id,
      confirmationCode: confirmationCode ?? this.confirmationCode,
      guestName: guestName ?? this.guestName,
      phone: phone ?? this.phone,
      email: email == _sentinel ? this.email : email as String?,
      notes: notes == _sentinel ? this.notes : notes as String?,
      idType: idType == _sentinel ? this.idType : idType as String?,
      idNumber: idNumber == _sentinel ? this.idNumber : idNumber as String?,
      roomType: roomType ?? this.roomType,
      roomNumber:
          roomNumber == _sentinel ? this.roomNumber : roomNumber as String?,
      checkInDate: checkInDate ?? this.checkInDate,
      checkOutDate: checkOutDate ?? this.checkOutDate,
      nights: nights ?? this.nights,
      guests: guests ?? this.guests,
      depositHtg: depositHtg ?? this.depositHtg,
      isPaid: isPaid ?? this.isPaid,
      status: status ?? this.status,
      roomId: roomId == _sentinel ? this.roomId : roomId as int?,
    );
  }
}

class MockGuest {
  final int id;
  final String name;
  final String nationality;
  final String phone;
  final String email;
  final String? notes;
  final bool isBlacklisted;

  const MockGuest({
    required this.id,
    required this.name,
    required this.nationality,
    required this.phone,
    required this.email,
    this.notes,
    this.isBlacklisted = false,
  });

  MockGuest copyWith({
    int? id,
    String? name,
    String? nationality,
    String? phone,
    String? email,
    Object? notes = _sentinel,
    bool? isBlacklisted,
  }) {
    return MockGuest(
      id: id ?? this.id,
      name: name ?? this.name,
      nationality: nationality ?? this.nationality,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      notes: notes == _sentinel ? this.notes : notes as String?,
      isBlacklisted: isBlacklisted ?? this.isBlacklisted,
    );
  }
}

/// Normalize for duplicate detection.
String normalizeGuestPhone(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return '';
  return s.replaceAll(RegExp(r'[\s\-\.\(\)]'), '');
}

String normalizeGuestEmail(String raw) => raw.trim().toLowerCase();

enum GuestUpsertFromStayResult {
  needsPhoneOrEmail,
  merged,
  added,
}

// ──────────────── MOCK DATA ────────────────

final _mockRoomsSeed = [
  // Floor 1
  MockRoom(
      id: 1,
      number: '101',
      type: 'Simple',
      floor: 1,
      status: 'available',
      priceHtg: 5000,
      priceUsd: 50),
  MockRoom(
      id: 2,
      number: '102',
      type: 'Simple',
      floor: 1,
      status: 'occupied',
      guestName: 'Marie Toussaint',
      checkInDate: 'Feb 24',
      checkOutDate: 'Feb 27',
      priceHtg: 5000,
      priceUsd: 50,
      isShortStay: false),
  MockRoom(
      id: 3,
      number: '103',
      type: 'Double',
      floor: 1,
      status: 'checkout_today',
      guestName: 'James Williams',
      checkInDate: 'Feb 23',
      checkOutDate: 'Feb 26',
      priceHtg: 8500,
      priceUsd: 85),
  MockRoom(
      id: 4,
      number: '104',
      type: 'Double',
      floor: 1,
      status: 'cleaning',
      housekeeper: 'Josiane',
      cleaningTaskType: 'full_turnover',
      cleaningAssignee: 'Josiane',
      priceHtg: 8500,
      priceUsd: 85),
  MockRoom(
      id: 5,
      number: '105',
      type: 'Double',
      floor: 1,
      status: 'occupied',
      guestName: 'Claudette Pierre',
      checkInDate: 'Mar 9, 2026 2:00 PM',
      checkOutDate: 'Mar 9, 2026 5:00 PM',
      priceHtg: 8500,
      priceUsd: 85,
      isShortStay: true),
  MockRoom(
      id: 6,
      number: '106',
      type: 'Simple',
      floor: 1,
      status: 'available',
      priceHtg: 5000,
      priceUsd: 50),
  // Floor 2
  MockRoom(
      id: 7,
      number: '201',
      type: 'Double',
      floor: 2,
      status: 'occupied',
      guestName: 'François Dubois',
      checkInDate: 'Feb 22',
      checkOutDate: 'Feb 28',
      priceHtg: 9000,
      priceUsd: 90,
      isShortStay: false),
  MockRoom(
      id: 8,
      number: '202',
      type: 'Double',
      floor: 2,
      status: 'available',
      priceHtg: 9000,
      priceUsd: 90),
  MockRoom(
      id: 9,
      number: '203',
      type: 'Deluxe',
      floor: 2,
      status: 'occupied',
      guestName: 'Sandra Moreau',
      checkInDate: 'Feb 24',
      checkOutDate: 'Feb 27',
      priceHtg: 14000,
      priceUsd: 140,
      isShortStay: false),
  MockRoom(
      id: 10,
      number: '204',
      type: 'Deluxe',
      floor: 2,
      status: 'maintenance',
      priceHtg: 14000,
      priceUsd: 140),
  MockRoom(
      id: 11,
      number: '205',
      type: 'Deluxe',
      floor: 2,
      status: 'occupied',
      guestName: 'Robert Johnson',
      checkInDate: 'Feb 25',
      checkOutDate: 'Mar 1',
      priceHtg: 14000,
      priceUsd: 140,
      isShortStay: false),
  MockRoom(
      id: 12,
      number: '206',
      type: 'Deluxe',
      floor: 2,
      status: 'checkout_today',
      guestName: 'Isabelle Petit',
      checkInDate: 'Feb 24',
      checkOutDate: 'Feb 26',
      priceHtg: 14000,
      priceUsd: 140),
  // Floor 3 — Suites
  MockRoom(
      id: 13,
      number: '301',
      type: 'Suite',
      floor: 3,
      status: 'available',
      priceHtg: 25000,
      priceUsd: 250),
  MockRoom(
      id: 14,
      number: '302',
      type: 'Suite',
      floor: 3,
      status: 'occupied',
      guestName: 'Dr. Emmanuel Charles',
      checkInDate: 'Feb 20',
      checkOutDate: 'Feb 28',
      priceHtg: 25000,
      priceUsd: 250,
      isShortStay: false),
  MockRoom(
      id: 15,
      number: '303',
      type: 'Suite',
      floor: 3,
      status: 'available',
      priceHtg: 28000,
      priceUsd: 280),
  MockRoom(
      id: 16,
      number: 'VIP-1',
      type: 'Presidential Suite',
      floor: 3,
      status: 'available',
      priceHtg: 50000,
      priceUsd: 500),
];

List<MockReservation> _buildMockReservationsSeed() {
  final fmt = DateFormat('MMM d, yyyy');
  final now = DateTime.now();
  final todayStr = fmt.format(now);
  final tomorrowStr = fmt.format(now.add(const Duration(days: 1)));
  final plus2 = fmt.format(now.add(const Duration(days: 2)));
  final plus4 = fmt.format(now.add(const Duration(days: 4)));
  return [
    MockReservation(
        id: 1,
        confirmationCode: 'BM-2026-001',
        guestName: 'Jean-Paul Duval',
        phone: '+509 3456-7890',
        roomType: 'Double',
        checkInDate: todayStr,
        checkOutDate: plus2,
        nights: 2,
        guests: 2,
        depositHtg: 8500,
        status: 'confirmed',
        roomId: 8, // Room 202 (Double)
        idType: 'Passeport',
        idNumber: 'P-789456'),
    MockReservation(
        id: 2,
        confirmationCode: 'BM-2026-002',
        guestName: 'Sarah Mitchell',
        phone: '+1 305-555-0134',
        roomType: 'Suite',
        checkInDate: todayStr,
        checkOutDate: plus4,
        nights: 4,
        guests: 1,
        depositHtg: 25000,
        isPaid: true,
        status: 'confirmed',
        roomId: 13, // Room 301 (Suite)
        idType: 'ID',
        idNumber: 'DL-123456'),
    MockReservation(
        id: 3,
        confirmationCode: 'BM-2026-003',
        guestName: 'Pierre Alexandre',
        phone: '+509 4890-1234',
        roomType: 'Simple',
        checkInDate: todayStr,
        checkOutDate: tomorrowStr,
        nights: 1,
        guests: 1,
        depositHtg: 5000,
        status: 'confirmed',
        roomId: 1), // Room 101 (Single)
    MockReservation(
        id: 4,
        confirmationCode: 'BM-2026-004',
        guestName: 'Monique Leblanc',
        phone: '+509 3671-4523',
        roomType: 'Deluxe',
        checkInDate: tomorrowStr,
        checkOutDate: plus4,
        nights: 3,
        guests: 2,
        depositHtg: 14000,
        status: 'confirmed',
        roomId: 12, // Room 206 (Deluxe, checkout_today → free tomorrow)
        idType: 'Licence',
        idNumber: 'LIC-445566'),
    MockReservation(
        id: 5,
        confirmationCode: 'BM-2026-005',
        guestName: 'Thomas Becker',
        phone: '+49 30 555 0178',
        roomType: 'Double',
        roomNumber: '201',
        checkInDate: fmt.format(now.subtract(const Duration(days: 5))),
        checkOutDate: plus2,
        nights: 6,
        guests: 2,
        depositHtg: 9000,
        status: 'checked_in',
        roomId: 7, // Room 201 (Double)
        idType: 'Passeport',
        idNumber: 'DE-998877'),
  ];
}

final mockGuests = [
  MockGuest(
      id: 1,
      name: 'Marie Toussaint',
      nationality: 'Haïtienne',
      phone: '+509 3234-5678',
      email: 'marie.t@gmail.com',
      notes: 'Préfère une chambre calme, 2e étage'),
  MockGuest(
      id: 2,
      name: 'James Williams',
      nationality: 'American',
      phone: '+1 212-555-0156',
      email: 'j.williams@outlook.com'),
  MockGuest(
      id: 3,
      name: 'Dr. Emmanuel Charles',
      nationality: 'Haïtien',
      phone: '+509 4567-8901',
      email: 'dr.charles@uniofhaiti.edu',
      notes: 'Client habituel, préfère la 302'),
  MockGuest(
      id: 4,
      name: 'Robert Johnson',
      nationality: 'Canadian',
      phone: '+1 514-555-0189',
      email: 'rjohnson@ngo.ca'),
  MockGuest(
      id: 5,
      name: 'Isabelle Petit',
      nationality: 'Française',
      phone: '+33 6 12 34 56 78',
      email: 'i.petit@gmail.com'),
];

// ──────────────── HOTEL RESTAURANT ORDERS ────────────────

// ──────────────── HOTEL KITCHEN BATCH ────────────────

class MockHotelKitchenBatch {
  final int batchNumber;
  final List<MockHotelOrderItem> items;
  final String status; // pending, in_progress, ready, complete, delivered
  final DateTime placedAt;
  final DateTime? kitchenCompletedAt;

  bool get isAddon => batchNumber > 1;

  MockHotelKitchenBatch({
    required this.batchNumber,
    required this.items,
    required this.status,
    required this.placedAt,
    this.kitchenCompletedAt,
  });

  MockHotelKitchenBatch copyWith({
    int? batchNumber,
    List<MockHotelOrderItem>? items,
    String? status,
    DateTime? placedAt,
    Object? kitchenCompletedAt = _sentinel,
  }) =>
      MockHotelKitchenBatch(
        batchNumber: batchNumber ?? this.batchNumber,
        items: items ?? this.items,
        status: status ?? this.status,
        placedAt: placedAt ?? this.placedAt,
        kitchenCompletedAt: kitchenCompletedAt == _sentinel
            ? this.kitchenCompletedAt
            : kitchenCompletedAt as DateTime?,
      );
}

class MockHotelOrderItem {
  final String name;
  final int quantity;
  final double priceHtg;
  final double priceUsd;
  final String? note;
  /// Menu category (e.g. 'Boissons', 'Plats'). Used to decide whether the item
  /// goes to a kitchen batch (food) or is merged directly (drinks).
  final String category;
  final bool isCustom;
  final bool sendToKitchen;
  final String customStatus;

  const MockHotelOrderItem({
    required this.name,
    required this.quantity,
    required this.priceHtg,
    required this.priceUsd,
    this.note,
    this.category = 'Plats',
    this.isCustom = false,
    this.sendToKitchen = false,
    this.customStatus = 'pending',
  });

  bool get isDrink => category == 'Boissons';

  MockHotelOrderItem copyWith({
    String? name,
    int? quantity,
    double? priceHtg,
    double? priceUsd,
    Object? note = _sentinel,
    String? category,
    bool? isCustom,
    bool? sendToKitchen,
    String? customStatus,
  }) =>
      MockHotelOrderItem(
        name: name ?? this.name,
        quantity: quantity ?? this.quantity,
        priceHtg: priceHtg ?? this.priceHtg,
        priceUsd: priceUsd ?? this.priceUsd,
        note: note == _sentinel ? this.note : note as String?,
        category: category ?? this.category,
        isCustom: isCustom ?? this.isCustom,
        sendToKitchen: sendToKitchen ?? this.sendToKitchen,
        customStatus: customStatus ?? this.customStatus,
      );
}

class MockHotelRestaurantOrder {
  final int id;
  final String? roomNumber;
  final String? guestName;
  final String? tableName;
  final List<MockHotelOrderItem> items;
  final DateTime placedAt;
  // pending, in_progress, ready, charged, delivered, complete, cancelled
  final String status;
  final String waiter;
  final bool isPaid;
  final String? paymentMethod;
  final double? paidAmountHtg;
  /// Delivery contact — required for delivery orders in UI.
  final String? customerPhone;
  final String? deliveryAddress;
  /// Order type: dine_in, takeout, delivery, room_service, reservation
  final String orderType;
  /// Kitchen dispatch batches. Batch 1 = original order; add-ons append.
  final List<MockHotelKitchenBatch> kitchenBatches;
  final String? reservationGuestName;
  final int? reservationPartySize;
  final String? reservationNotes;
  /// True after a payment link has been sent for this order.
  final bool paymentLinkSent;
  /// True when kitchen should wait for remote payment before preparing.
  final bool kitchenHeldForPayment;
  /// Recipient info for the sent payment link.
  final String? paymentLinkRecipient;
  /// Channel used: whatsApp, email, sms.
  final String? paymentLinkChannel;
  /// When the link was sent.
  final DateTime? paymentLinkSentAt;
  /// Gateway / customer payment captured; staff still confirms [isPaid] when a link was sent.
  final bool paymentLinkRemotePaid;
  /// Prepaid spending cap (HTG) for dine-in / reservation payment links; null = no cap.
  final double? prepaidCapHtg;
  /// Staff closed a prepaid table visit — removes order from active list when [prepaidCapHtg] is set.
  final bool visitCompleted;
  /// Store credit applied to this bill (HTG), for receipt / audit.
  final double customerCreditAppliedHtg;

  // ── Merge fields ────────────────────────────────────────────────────────────
  /// Snapshot of the absorbed order (table merged into this one).
  final MergedHotelTableSnapshot? mergedSnapshot;

  MockHotelRestaurantOrder({
    required this.id,
    this.roomNumber,
    this.guestName,
    this.tableName,
    required this.items,
    required this.placedAt,
    required this.status,
    required this.waiter,
    this.isPaid = false,
    this.paymentMethod,
    this.paidAmountHtg,
    this.customerPhone,
    this.deliveryAddress,
    this.paymentLinkSent = false,
    this.kitchenHeldForPayment = false,
    this.paymentLinkRecipient,
    this.paymentLinkChannel,
    this.paymentLinkSentAt,
    this.paymentLinkRemotePaid = false,
    this.prepaidCapHtg,
    this.visitCompleted = false,
    this.customerCreditAppliedHtg = 0,
    this.mergedSnapshot,
    String? orderType,
    List<MockHotelKitchenBatch>? kitchenBatches,
    this.reservationGuestName,
    this.reservationPartySize,
    this.reservationNotes,
  })  : orderType =
            orderType ?? (roomNumber != null ? 'room_service' : 'dine_in'),
        kitchenBatches = kitchenBatches ??
            [
              MockHotelKitchenBatch(
                batchNumber: 1,
                items: items,
                status: status,
                placedAt: placedAt,
              )
            ];

  bool get isRoomService => orderType == 'room_service';

  double get totalHtg =>
      items.fold(0.0, (s, i) => s + i.priceHtg * i.quantity);
  double get totalUsd =>
      items.fold(0.0, (s, i) => s + i.priceUsd * i.quantity);

  /// Flat list of all items — the authoritative source for billing.
  List<MockHotelOrderItem> get allItems => items;
  double get allItemsTotalHtg =>
      items.fold(0, (s, i) => s + i.priceHtg * i.quantity);

  MockHotelRestaurantOrder copyWith({
    int? id,
    Object? roomNumber = _sentinel,
    Object? guestName = _sentinel,
    Object? tableName = _sentinel,
    List<MockHotelOrderItem>? items,
    DateTime? placedAt,
    String? status,
    String? waiter,
    bool? isPaid,
    Object? paymentMethod = _sentinel,
    Object? paidAmountHtg = _sentinel,
    Object? customerPhone = _sentinel,
    Object? deliveryAddress = _sentinel,
    bool? paymentLinkSent,
    bool? kitchenHeldForPayment,
    Object? paymentLinkRecipient = _sentinel,
    Object? paymentLinkChannel = _sentinel,
    Object? paymentLinkSentAt = _sentinel,
    bool? paymentLinkRemotePaid,
    Object? prepaidCapHtg = _sentinel,
    bool? visitCompleted,
    double? customerCreditAppliedHtg,
    String? orderType,
    List<MockHotelKitchenBatch>? kitchenBatches,
    Object? reservationGuestName = _sentinel,
    Object? reservationPartySize = _sentinel,
    Object? reservationNotes = _sentinel,
    Object? mergedSnapshot = _sentinel,
  }) =>
      MockHotelRestaurantOrder(
        id: id ?? this.id,
        roomNumber:
            roomNumber == _sentinel ? this.roomNumber : roomNumber as String?,
        guestName:
            guestName == _sentinel ? this.guestName : guestName as String?,
        tableName:
            tableName == _sentinel ? this.tableName : tableName as String?,
        items: items ?? this.items,
        placedAt: placedAt ?? this.placedAt,
        status: status ?? this.status,
        waiter: waiter ?? this.waiter,
        isPaid: isPaid ?? this.isPaid,
        paymentMethod: paymentMethod == _sentinel
            ? this.paymentMethod
            : paymentMethod as String?,
        paidAmountHtg: paidAmountHtg == _sentinel
            ? this.paidAmountHtg
            : paidAmountHtg as double?,
        customerPhone: customerPhone == _sentinel
            ? this.customerPhone
            : customerPhone as String?,
        deliveryAddress: deliveryAddress == _sentinel
            ? this.deliveryAddress
            : deliveryAddress as String?,
        paymentLinkSent: paymentLinkSent ?? this.paymentLinkSent,
        kitchenHeldForPayment: kitchenHeldForPayment ?? this.kitchenHeldForPayment,
        paymentLinkRecipient: paymentLinkRecipient == _sentinel
            ? this.paymentLinkRecipient
            : paymentLinkRecipient as String?,
        paymentLinkChannel: paymentLinkChannel == _sentinel
            ? this.paymentLinkChannel
            : paymentLinkChannel as String?,
        paymentLinkSentAt: paymentLinkSentAt == _sentinel
            ? this.paymentLinkSentAt
            : paymentLinkSentAt as DateTime?,
        paymentLinkRemotePaid:
            paymentLinkRemotePaid ?? this.paymentLinkRemotePaid,
        prepaidCapHtg: prepaidCapHtg == _sentinel
            ? this.prepaidCapHtg
            : prepaidCapHtg as double?,
        visitCompleted: visitCompleted ?? this.visitCompleted,
        customerCreditAppliedHtg:
            customerCreditAppliedHtg ?? this.customerCreditAppliedHtg,
        orderType: orderType ?? this.orderType,
        kitchenBatches: kitchenBatches ?? this.kitchenBatches,
        reservationGuestName: reservationGuestName == _sentinel
            ? this.reservationGuestName
            : reservationGuestName as String?,
        reservationPartySize: reservationPartySize == _sentinel
            ? this.reservationPartySize
            : reservationPartySize as int?,
        reservationNotes: reservationNotes == _sentinel
            ? this.reservationNotes
            : reservationNotes as String?,
        mergedSnapshot: mergedSnapshot == _sentinel
            ? this.mergedSnapshot
            : mergedSnapshot as MergedHotelTableSnapshot?,
      );

  /// True when this order absorbed another table via merge.
  bool get hasMerge => mergedSnapshot != null;
}

extension MockHotelRestaurantOrderAddItemsPolicy on MockHotelRestaurantOrder {
  bool get allowsAddingItems => orderAllowsAddingItems(
        isPaid: isPaid,
        visitCompleted: visitCompleted,
        orderType: orderType,
        prepaidCapHtg: prepaidCapHtg,
      );
}

/// Orders still in the kitchen/service workflow (shown as active in Room Service & KDS).
bool isHotelRestaurantOrderActive(MockHotelRestaurantOrder o) =>
    o.status == 'pending' || o.status == 'in_progress' || o.status == 'ready';

/// Fulfilled / billable at checkout (legacy delivered/charged + complete).
bool isHotelRestaurantOrderBilled(MockHotelRestaurantOrder o) =>
    o.status == 'charged' || o.status == 'delivered' || o.status == 'complete';

final _hNow = DateTime.now();

final mockHotelRestaurantOrders = [
  MockHotelRestaurantOrder(
    id: 201,
    roomNumber: '102',
    guestName: 'Marie Toussaint',
    items: const [
      MockHotelOrderItem(
          name: 'Griot avec Riz Collé',
          quantity: 1,
          priceHtg: 1200,
          priceUsd: 12.00,
          category: 'Plats'),
      MockHotelOrderItem(
          name: 'Jus de Corossol',
          quantity: 1,
          priceHtg: 200,
          priceUsd: 2.00,
          category: 'Boissons'),
      MockHotelOrderItem(
          name: 'Eau Minérale',
          quantity: 2,
          priceHtg: 100,
          priceUsd: 1.00,
          category: 'Boissons'),
    ],
    placedAt: DateTime(
        _hNow.year, _hNow.month, _hNow.day, _hNow.hour, _hNow.minute - 18),
    status: 'in_progress',
    waiter: 'Joseph',
  ),
  MockHotelRestaurantOrder(
    id: 202,
    roomNumber: '203',
    guestName: 'Sandra Moreau',
    items: const [
      MockHotelOrderItem(
          name: 'Accra (beignets de malanga)',
          quantity: 1,
          priceHtg: 350,
          priceUsd: 3.50,
          category: 'Entrées'),
      MockHotelOrderItem(
          name: 'Poulet en Sauce',
          quantity: 2,
          priceHtg: 950,
          priceUsd: 9.50,
          category: 'Plats'),
      MockHotelOrderItem(
          name: 'Prestige Beer',
          quantity: 2,
          priceHtg: 300,
          priceUsd: 3.00,
          category: 'Boissons'),
    ],
    placedAt: DateTime(
        _hNow.year, _hNow.month, _hNow.day, _hNow.hour, _hNow.minute - 35),
    status: 'charged',
    waiter: 'Marie-Carmel',
    isPaid: true,
  ),
  MockHotelRestaurantOrder(
    id: 203,
    roomNumber: '302',
    guestName: 'Dr. Emmanuel Charles',
    items: const [
      MockHotelOrderItem(
          name: "Special du Jour: Lambi en Sauce",
          quantity: 1,
          priceHtg: 2200,
          priceUsd: 22.00,
          category: 'Suggestions'),
      MockHotelOrderItem(
          name: 'Rhum Barbancourt',
          quantity: 1,
          priceHtg: 450,
          priceUsd: 4.50,
          note: 'Sur glace',
          category: 'Boissons'),
      MockHotelOrderItem(
          name: 'Dous Makos',
          quantity: 1,
          priceHtg: 250,
          priceUsd: 2.50,
          category: 'Desserts'),
    ],
    placedAt: DateTime(
        _hNow.year, _hNow.month, _hNow.day, _hNow.hour, _hNow.minute - 50),
    status: 'delivered',
    waiter: 'Pierre',
    isPaid: true,
  ),
  MockHotelRestaurantOrder(
    id: 204,
    roomNumber: '205',
    guestName: 'Robert Johnson',
    items: const [
      MockHotelOrderItem(
          name: 'Café Haïtien',
          quantity: 2,
          priceHtg: 180,
          priceUsd: 1.80,
          category: 'Boissons'),
      MockHotelOrderItem(
          name: 'Pain Patate',
          quantity: 2,
          priceHtg: 200,
          priceUsd: 2.00,
          category: 'Desserts'),
    ],
    placedAt: DateTime(
        _hNow.year, _hNow.month, _hNow.day, _hNow.hour, _hNow.minute - 8),
    status: 'pending',
    waiter: 'Claudine',
  ),
  MockHotelRestaurantOrder(
    id: 205,
    tableName: 'Table 1',
    items: const [
      MockHotelOrderItem(
          name: 'Bouillon de Crabe',
          quantity: 2,
          priceHtg: 650,
          priceUsd: 6.50,
          category: 'Entrées'),
      MockHotelOrderItem(
          name: 'Lanbi (lambi)',
          quantity: 2,
          priceHtg: 1800,
          priceUsd: 18.00,
          category: 'Suggestions'),
      MockHotelOrderItem(
          name: 'Prestige Beer',
          quantity: 4,
          priceHtg: 300,
          priceUsd: 3.00,
          category: 'Boissons'),
    ],
    placedAt: DateTime(
        _hNow.year, _hNow.month, _hNow.day, _hNow.hour, _hNow.minute - 25),
    status: 'in_progress',
    waiter: 'Marie-Carmel',
  ),
  MockHotelRestaurantOrder(
    id: 206,
    tableName: 'Terrasse A',
    items: const [
      MockHotelOrderItem(
          name: 'Tassot de Cabrit',
          quantity: 2,
          priceHtg: 1600,
          priceUsd: 16.00,
          category: 'Plats'),
      MockHotelOrderItem(
          name: 'Bannann peze',
          quantity: 2,
          priceHtg: 200,
          priceUsd: 2.00,
          category: 'Accompagnements'),
      MockHotelOrderItem(
          name: 'Rhum Barbancourt',
          quantity: 2,
          priceHtg: 450,
          priceUsd: 4.50,
          category: 'Boissons'),
    ],
    placedAt: DateTime(
        _hNow.year, _hNow.month, _hNow.day, _hNow.hour, _hNow.minute - 12),
    status: 'ready',
    waiter: 'Joseph',
  ),
  MockHotelRestaurantOrder(
    id: 207,
    tableName: 'Table 3',
    items: const [
      MockHotelOrderItem(
          name: 'Salade de Chou',
          quantity: 2,
          priceHtg: 250,
          priceUsd: 2.50,
          category: 'Entrées'),
      MockHotelOrderItem(
          name: 'Poisson Gros Sel',
          quantity: 1,
          priceHtg: 1400,
          priceUsd: 14.00,
          category: 'Plats'),
      MockHotelOrderItem(
          name: 'Akasan',
          quantity: 2,
          priceHtg: 150,
          priceUsd: 1.50,
          category: 'Boissons'),
    ],
    placedAt: DateTime(
        _hNow.year, _hNow.month, _hNow.day, _hNow.hour, _hNow.minute - 6),
    status: 'pending',
    waiter: 'Pierre',
  ),
  MockHotelRestaurantOrder(
    id: 208,
    orderType: 'takeout',
    guestName: 'Jean-Baptiste Pierre',
    items: const [
      MockHotelOrderItem(
          name: 'Griot avec Riz Collé',
          quantity: 2,
          priceHtg: 1200,
          priceUsd: 12.00,
          category: 'Plats'),
      MockHotelOrderItem(
          name: 'Prestige Beer',
          quantity: 2,
          priceHtg: 300,
          priceUsd: 3.00,
          category: 'Boissons'),
    ],
    placedAt: DateTime(
        _hNow.year, _hNow.month, _hNow.day, _hNow.hour, _hNow.minute - 4),
    status: 'pending',
    waiter: 'Claudine',
    customerPhone: '+509 4410-2233',
  ),
  MockHotelRestaurantOrder(
    id: 209,
    orderType: 'delivery',
    guestName: 'Monique Laguerre',
    items: const [
      MockHotelOrderItem(
          name: 'Poulet en Sauce',
          quantity: 1,
          priceHtg: 950,
          priceUsd: 9.50,
          category: 'Plats'),
      MockHotelOrderItem(
          name: 'Diri Djondjon',
          quantity: 1,
          priceHtg: 300,
          priceUsd: 3.00,
          category: 'Accompagnements'),
      MockHotelOrderItem(
          name: 'Jus de Grenadine',
          quantity: 1,
          priceHtg: 200,
          priceUsd: 2.00,
          category: 'Boissons'),
    ],
    placedAt: DateTime(
        _hNow.year, _hNow.month, _hNow.day, _hNow.hour, _hNow.minute - 2),
    status: 'pending',
    waiter: 'Joseph',
    customerPhone: '+509 5566-7788',
    deliveryAddress: '12 Rue Panaméricaine, Delmas 75',
  ),
  MockHotelRestaurantOrder(
    id: 210,
    tableName: 'Table 1',
    items: const [
      MockHotelOrderItem(
          name: 'Poisson Gros Sel',
          quantity: 1,
          priceHtg: 1400,
          priceUsd: 14.00,
          category: 'Plats'),
      MockHotelOrderItem(
          name: 'Eau Minérale',
          quantity: 1,
          priceHtg: 100,
          priceUsd: 1.00,
          category: 'Boissons'),
    ],
    placedAt: DateTime(
        _hNow.year, _hNow.month, _hNow.day, _hNow.hour, _hNow.minute - 20),
    status: 'complete',
    waiter: 'Marie-Carmel',
    isPaid: true, // closed sample — avoids duplicate Table 1 on active list
    kitchenBatches: [
      MockHotelKitchenBatch(
        batchNumber: 1,
        items: const [
          MockHotelOrderItem(
              name: 'Poisson Gros Sel',
              quantity: 1,
              priceHtg: 1400,
              priceUsd: 14.00,
              category: 'Plats'),
        ],
        status: 'complete',
        placedAt: DateTime(
            _hNow.year, _hNow.month, _hNow.day, _hNow.hour, _hNow.minute - 20),
        kitchenCompletedAt: DateTime.now().subtract(const Duration(hours: 2)),
      ),
    ],
  ),
  MockHotelRestaurantOrder(
    id: 211,
    tableName: 'Table 8',
    items: const [
      MockHotelOrderItem(
          name: 'Griot avec Riz Collé',
          quantity: 1,
          priceHtg: 1200,
          priceUsd: 12.00,
          category: 'Plats'),
    ],
    placedAt: DateTime(
        _hNow.year, _hNow.month, _hNow.day, _hNow.hour, _hNow.minute - 30),
    status: 'complete',
    waiter: 'Joseph',
    isPaid: true, // closed kitchen-history sample
    kitchenBatches: [
      MockHotelKitchenBatch(
        batchNumber: 1,
        items: const [
          MockHotelOrderItem(
              name: 'Griot avec Riz Collé',
              quantity: 1,
              priceHtg: 1200,
              priceUsd: 12.00,
              category: 'Plats'),
        ],
        status: 'complete',
        placedAt: DateTime(
            _hNow.year, _hNow.month, _hNow.day, _hNow.hour, _hNow.minute - 30),
        kitchenCompletedAt: DateTime.now().subtract(const Duration(hours: 4, minutes: 5)),
      ),
    ],
  ),
  MockHotelRestaurantOrder(
    id: 212,
    orderType: 'takeout',
    guestName: 'Client — ancienne commande',
    items: const [
      MockHotelOrderItem(
          name: 'Salade de Chou',
          quantity: 1,
          priceHtg: 250,
          priceUsd: 2.50,
          category: 'Entrées'),
    ],
    placedAt: () {
      final y = DateTime.now().subtract(const Duration(days: 1));
      return DateTime(y.year, y.month, y.day, 18, 0);
    }(),
    status: 'delivered',
    waiter: 'Pierre',
    kitchenBatches: [
      MockHotelKitchenBatch(
        batchNumber: 1,
        items: const [
          MockHotelOrderItem(
              name: 'Salade de Chou',
              quantity: 1,
              priceHtg: 250,
              priceUsd: 2.50,
              category: 'Entrées'),
        ],
        status: 'delivered',
        placedAt: () {
          final y = DateTime.now().subtract(const Duration(days: 1));
          return DateTime(y.year, y.month, y.day, 18, 0);
        }(),
        kitchenCompletedAt: () {
          final y = DateTime.now().subtract(const Duration(days: 1));
          return DateTime(y.year, y.month, y.day, 18, 20);
        }(),
      ),
    ],
  ),
];

// ──────────────── STATE NOTIFIERS ────────────────

class RoomsNotifier extends StateNotifier<List<MockRoom>> {
  RoomsNotifier() : super(_mockRoomsSeed);
  int get _nextId => state.isEmpty
      ? 1
      : state.map((r) => r.id).reduce((a, b) => a > b ? a : b) + 1;
  void add(MockRoom r) => state = [...state, r.copyWith(id: _nextId)];
  void update(MockRoom r) =>
      state = [for (final x in state) x.id == r.id ? r : x];
  void remove(int id) => state = state.where((r) => r.id != id).toList();
}

class ReservationsNotifier extends StateNotifier<List<MockReservation>> {
  ReservationsNotifier() : super(_buildMockReservationsSeed());
  int get _nextId => state.isEmpty
      ? 1
      : state.map((r) => r.id).reduce((a, b) => a > b ? a : b) + 1;
  void add(MockReservation r) => state = [...state, r.copyWith(id: _nextId)];
  void update(MockReservation r) =>
      state = [for (final x in state) x.id == r.id ? r : x];
  void remove(int id) => state = state.where((r) => r.id != id).toList();
}

class GuestsNotifier extends StateNotifier<List<MockGuest>> {
  GuestsNotifier() : super(mockGuests);
  int get _nextId => state.isEmpty
      ? 1
      : state.map((g) => g.id).reduce((a, b) => a > b ? a : b) + 1;
  void add(MockGuest g) => state = [...state, g.copyWith(id: _nextId)];
  void update(MockGuest g) =>
      state = [for (final x in state) x.id == g.id ? g : x];
  void toggleBlacklist(int id) => state = [
        for (final x in state)
          x.id == id ? x.copyWith(isBlacklisted: !x.isBlacklisted) : x,
      ];

  /// Match by normalized email first, then phone. Requires at least one non-empty.
  GuestUpsertFromStayResult upsertFromStay({
    required String name,
    required String phone,
    required String email,
    String nationality = 'Unknown',
  }) {
    final p = phone.trim();
    final e = email.trim();
    if (p.isEmpty && e.isEmpty) {
      return GuestUpsertFromStayResult.needsPhoneOrEmail;
    }
    final np = normalizeGuestPhone(p);
    final ne = normalizeGuestEmail(e);

    MockGuest? existing;
    for (final g in state) {
      if (ne.isNotEmpty && normalizeGuestEmail(g.email) == ne) {
        existing = g;
        break;
      }
      if (np.isNotEmpty && normalizeGuestPhone(g.phone) == np) {
        existing = g;
        break;
      }
    }

    final mergedName = name.trim().isNotEmpty ? name.trim() : (existing?.name ?? 'Client');
    final nat = nationality.trim().isEmpty ? 'Unknown' : nationality.trim();

    if (existing != null) {
      update(
        existing.copyWith(
          name: mergedName,
          phone: p.isNotEmpty ? p : existing.phone,
          email: e.isNotEmpty ? e : existing.email,
          nationality: nat,
        ),
      );
      return GuestUpsertFromStayResult.merged;
    }

    add(
      MockGuest(
        id: 0,
        name: mergedName,
        nationality: nat,
        phone: p,
        email: e,
      ),
    );
    return GuestUpsertFromStayResult.added;
  }
}

class HotelRestaurantOrdersNotifier
    extends StateNotifier<List<MockHotelRestaurantOrder>> {
  HotelRestaurantOrdersNotifier() : super(mockHotelRestaurantOrders);

  int get _nextId => state.isEmpty
      ? 300
      : state.map((o) => o.id).reduce((a, b) => a > b ? a : b) + 1;

  /// Returns the id of the newly added order.
  int add(MockHotelRestaurantOrder order) {
    final id = _nextId;
    state = [...state, order.copyWith(id: id, isPaid: false)];
    return id;
  }

  void updateStatus(int id, String newStatus) => state = [
        for (final o in state) o.id == id ? o.copyWith(status: newStatus) : o,
      ];

  void setOrderPaid(int id, {String? paymentMethod, double? paidAmountHtg}) =>
      state = [
        for (final o in state)
          o.id == id
              ? o.copyWith(
                  isPaid: true,
                  paymentMethod: paymentMethod ?? o.paymentMethod,
                  paidAmountHtg: paidAmountHtg ?? o.paidAmountHtg,
                )
              : o,
      ];

  void markPaymentLinkSent(
    int id, {
    required String recipient,
    required String channel,
    double? prepaidCapHtg,
  }) {
    state = [
      for (final o in state)
        if (o.id == id)
          o.copyWith(
            paymentLinkSent: true,
            paymentLinkRecipient: recipient,
            paymentLinkChannel: channel,
            paymentLinkSentAt: DateTime.now(),
            prepaidCapHtg: prepaidCapHtg ?? o.prepaidCapHtg,
          )
        else
          o,
    ];
  }

  void holdKitchenForPayment(int id) {
    state = [
      for (final o in state)
        if (o.id == id) o.copyWith(kitchenHeldForPayment: true) else o,
    ];
  }

  /// Simulates payment-link webhook: funds received but staff still confirms [isPaid]
  /// when [paymentLinkSent] is true.
  void confirmPaymentAndRelease(int id) {
    state = [
      for (final o in state)
        if (o.id == id)
          o.paymentLinkSent
              ? o.copyWith(
                  paymentLinkRemotePaid: true,
                  kitchenHeldForPayment: false,
                )
              : o.copyWith(isPaid: true, kitchenHeldForPayment: false)
        else
          o,
    ];
  }

  void setStaffPaymentConfirmed(int id, bool paid) {
    state = [
      for (final o in state)
        if (o.id == id)
          o.copyWith(
            isPaid: paid,
            kitchenHeldForPayment:
                paid ? false : o.kitchenHeldForPayment,
          )
        else
          o,
    ];
  }

  void setVisitCompleted(int id, {bool completed = true}) {
    state = [
      for (final o in state)
        if (o.id == id) o.copyWith(visitCompleted: completed) else o,
    ];
  }

  void applyCustomerCredit(int id, double amountHtg) {
    if (amountHtg <= 0) return;
    state = [
      for (final o in state)
        if (o.id == id)
          o.copyWith(
            customerCreditAppliedHtg: o.customerCreditAppliedHtg + amountHtg,
          )
        else
          o,
    ];
  }

  void updateOrderItems(int id, List<MockHotelOrderItem> items) => state = [
        for (final o in state) o.id == id ? o.copyWith(items: items) : o,
      ];

  /// Adds items to an existing order. Food items create a new kitchen batch;
  /// drinks are merged into the existing flat item list.
  ///
  /// Returns `false` if [prepaidCapHtg] would be exceeded (state unchanged).
  bool addBatch(int orderId, List<MockHotelOrderItem> newItems) {
    var success = true;
    state = [
      for (final o in state)
        if (o.id == orderId)
          () {
            final foodItems = newItems.where((i) => !i.isDrink).toList();
            final drinkItems = newItems.where((i) => i.isDrink).toList();

            // Merge all new items into the flat authoritative list.
            var updatedItems = List<MockHotelOrderItem>.from(o.items);
            for (final ni in drinkItems) {
              final idx = updatedItems.indexWhere((i) => i.name == ni.name);
              if (idx >= 0) {
                updatedItems[idx] = updatedItems[idx]
                    .copyWith(quantity: updatedItems[idx].quantity + ni.quantity);
              } else {
                updatedItems.add(ni);
              }
            }
            for (final fi in foodItems) {
              updatedItems.add(fi);
            }

            // New kitchen batch only for food items.
            final updatedBatches =
                List<MockHotelKitchenBatch>.from(o.kitchenBatches);
            if (foodItems.isNotEmpty) {
              updatedBatches.add(MockHotelKitchenBatch(
                batchNumber: updatedBatches.length + 1,
                items: foodItems,
                status: 'pending',
                placedAt: DateTime.now(),
              ));
            }

            final subtotal =
                updatedItems.fold(0.0, (s, i) => s + i.priceHtg * i.quantity);
            final cap = o.prepaidCapHtg;
            if (cap != null) {
              final bill = estimatedBillTotalHtgFromSubtotal(subtotal);
              if (bill > cap + 0.009) {
                success = false;
                return o;
              }
            }

            return o.copyWith(
              items: updatedItems,
              kitchenBatches: updatedBatches,
            );
          }()
        else
          o,
    ];
    return success;
  }

  void updateBatchStatus(int orderId, int batchNumber, String newStatus) {
    state = [
      for (final o in state)
        if (o.id == orderId)
          o.copyWith(
            kitchenBatches: [
              for (final b in o.kitchenBatches)
                b.batchNumber == batchNumber
                    ? _hotelBatchWithNewStatus(b, newStatus)
                    : b,
            ],
          )
        else
          o,
    ];
  }

  static MockHotelKitchenBatch _hotelBatchWithNewStatus(
      MockHotelKitchenBatch b, String newStatus) {
    final norm = newStatus == 'preparing' ? 'in_progress' : newStatus;
    final terminal = norm == 'complete' || norm == 'delivered';
    return b.copyWith(
      status: newStatus,
      kitchenCompletedAt: terminal
          ? (b.kitchenCompletedAt ?? DateTime.now())
          : null,
    );
  }

  void removeItem(int orderId, String itemName) {
    state = [
      for (final o in state)
        if (o.id == orderId)
          o.copyWith(
            items: o.items.where((i) => i.name != itemName).toList(),
            kitchenBatches: o.kitchenBatches
                .map((b) => b.copyWith(
                      items:
                          b.items.where((i) => i.name != itemName).toList(),
                    ))
                .where((b) => b.items.isNotEmpty)
                .toList(),
          )
        else
          o,
    ];
  }

  void decreaseItemQty(int orderId, String itemName) {
    state = [
      for (final o in state)
        if (o.id == orderId)
          () {
            final updatedItems = o.items
                .map((i) => i.name == itemName
                    ? (i.quantity > 1 ? i.copyWith(quantity: i.quantity - 1) : null)
                    : i)
                .whereType<MockHotelOrderItem>()
                .toList();
            final updatedBatches = o.kitchenBatches
                .map((b) {
                  final bItems = b.items
                      .map((i) => i.name == itemName
                          ? (i.quantity > 1
                              ? i.copyWith(quantity: i.quantity - 1)
                              : null)
                          : i)
                      .whereType<MockHotelOrderItem>()
                      .toList();
                  return bItems.isEmpty ? null : b.copyWith(items: bItems);
                })
                .whereType<MockHotelKitchenBatch>()
                .toList();
            return o.copyWith(
              items: updatedItems,
              kitchenBatches: updatedBatches,
            );
          }()
        else
          o,
    ];
  }

  void cancelOrder(int id) {
    state = state.where((o) => o.id != id).toList();
  }

  /// Merge [absorbedId] into [survivorId].
  ///
  /// Returns `false` if either order has a pending payment link or prepaid cap.
  bool mergeOrders(int survivorId, int absorbedId) {
    final survivor = state.firstWhere((o) => o.id == survivorId,
        orElse: () => throw ArgumentError('Table conservée introuvable'));
    final absorbed = state.firstWhere((o) => o.id == absorbedId,
        orElse: () => throw ArgumentError('Table absorbée introuvable'));

    // One-time merge only — survivor cannot absorb a second table.
    if (survivor.mergedSnapshot != null) return false;

    final survivorBlocked =
        (survivor.paymentLinkSent && !survivor.paymentLinkRemotePaid) ||
            survivor.prepaidCapHtg != null;
    final absorbedBlocked =
        (absorbed.paymentLinkSent && !absorbed.paymentLinkRemotePaid) ||
            absorbed.prepaidCapHtg != null;
    if (survivorBlocked || absorbedBlocked) return false;

    final snapshot = MergedHotelTableSnapshot(
      orderId: absorbed.id,
      tableName: absorbed.tableName ?? 'Table',
      mergedAt: DateTime.now(),
      items: List.unmodifiable(absorbed.items),
      totalHtg: absorbed.allItemsTotalHtg,
      waiter: absorbed.waiter,
      guestName: absorbed.guestName,
    );

    state = [
      for (final o in state)
        if (o.id == survivorId)
          o.copyWith(
            items: [...o.items, ...absorbed.items],
            mergedSnapshot: snapshot,
          )
        else if (o.id == absorbedId)
          null
        else
          o,
    ].whereType<MockHotelRestaurantOrder>().toList();

    return true;
  }

  /// Advance custom line status: pending → ready → served (order + kitchen batches).
  void advanceCustomItemStatus(int orderId, String itemName) {
    state = [
      for (final o in state)
        if (o.id != orderId)
          o
        else
          _withHotelCustomItemStatus(o, itemName),
    ];
  }

  static String _nextHotelCustomStatus(String current) {
    switch (current) {
      case 'pending':
        return 'ready';
      case 'ready':
        return 'served';
      default:
        return 'served';
    }
  }

  static MockHotelRestaurantOrder _withHotelCustomItemStatus(
      MockHotelRestaurantOrder o, String itemName) {
    final idx = o.items.indexWhere((i) => i.name == itemName && i.isCustom);
    if (idx < 0) return o;
    final next = _nextHotelCustomStatus(o.items[idx].customStatus);
    return o.copyWith(
      items: [
        for (final i in o.items)
          if (i.name == itemName && i.isCustom)
            i.copyWith(customStatus: next)
          else
            i,
      ],
      kitchenBatches: [
        for (final b in o.kitchenBatches)
          b.copyWith(
            items: [
              for (final i in b.items)
                if (i.name == itemName && i.isCustom)
                  i.copyWith(customStatus: next)
                else
                  i,
            ],
          ),
      ],
    );
  }
}

// ──────────────── GROUP RESERVATIONS ────────────────

/// One room allocation inside a group reservation.
class MockGroupRoomAllocation {
  final String roomNumber;
  final String roomType;

  /// Physical room id — used for calendar blocking and availability.
  final int roomId;
  final double priceHtg;

  /// Optional guest names assigned to this room.
  final List<String> guestNames;

  /// Per-room check-in override; null = use group default.
  final String? checkInDate;

  /// Per-room check-out override; null = use group default.
  final String? checkOutDate;

  /// True after this room has been checked in from the reservations UI.
  final bool checkedIn;

  const MockGroupRoomAllocation({
    required this.roomNumber,
    required this.roomType,
    required this.roomId,
    required this.priceHtg,
    this.guestNames = const [],
    this.checkInDate,
    this.checkOutDate,
    this.checkedIn = false,
  });

  MockGroupRoomAllocation copyWith({
    String? roomNumber,
    String? roomType,
    int? roomId,
    double? priceHtg,
    List<String>? guestNames,
    Object? checkInDate = _sentinel,
    Object? checkOutDate = _sentinel,
    Object? checkedIn = _sentinel,
  }) =>
      MockGroupRoomAllocation(
        roomNumber: roomNumber ?? this.roomNumber,
        roomType: roomType ?? this.roomType,
        roomId: roomId ?? this.roomId,
        priceHtg: priceHtg ?? this.priceHtg,
        guestNames: guestNames ?? this.guestNames,
        checkInDate: checkInDate == _sentinel
            ? this.checkInDate
            : checkInDate as String?,
        checkOutDate: checkOutDate == _sentinel
            ? this.checkOutDate
            : checkOutDate as String?,
        checkedIn:
            checkedIn == _sentinel ? this.checkedIn : checkedIn as bool,
      );
}

class MockGroupReservation {
  final int id;
  final String confirmationCode;
  final String? groupName;
  final String contactName;
  final String contactPhone;
  final String? contactEmail;
  final String? contactIdType;
  final String? contactIdNumber;
  final int totalGuests;
  final String defaultCheckIn;
  final String defaultCheckOut;
  final List<MockGroupRoomAllocation> rooms;
  final double depositHtg;

  /// HTG collected toward this group (full or partial payment at booking).
  final double amountPaidHtg;
  final String status; // confirmed, checked_in, cancelled

  const MockGroupReservation({
    required this.id,
    required this.confirmationCode,
    this.groupName,
    required this.contactName,
    required this.contactPhone,
    this.contactEmail,
    this.contactIdType,
    this.contactIdNumber,
    required this.totalGuests,
    required this.defaultCheckIn,
    required this.defaultCheckOut,
    required this.rooms,
    required this.depositHtg,
    this.amountPaidHtg = 0,
    required this.status,
  });

  MockGroupReservation copyWith({
    int? id,
    String? confirmationCode,
    Object? groupName = _sentinel,
    String? contactName,
    String? contactPhone,
    Object? contactEmail = _sentinel,
    Object? contactIdType = _sentinel,
    Object? contactIdNumber = _sentinel,
    int? totalGuests,
    String? defaultCheckIn,
    String? defaultCheckOut,
    List<MockGroupRoomAllocation>? rooms,
    double? depositHtg,
    double? amountPaidHtg,
    String? status,
  }) =>
      MockGroupReservation(
        id: id ?? this.id,
        confirmationCode: confirmationCode ?? this.confirmationCode,
        groupName:
            groupName == _sentinel ? this.groupName : groupName as String?,
        contactName: contactName ?? this.contactName,
        contactPhone: contactPhone ?? this.contactPhone,
        contactEmail: contactEmail == _sentinel
            ? this.contactEmail
            : contactEmail as String?,
        contactIdType: contactIdType == _sentinel
            ? this.contactIdType
            : contactIdType as String?,
        contactIdNumber: contactIdNumber == _sentinel
            ? this.contactIdNumber
            : contactIdNumber as String?,
        totalGuests: totalGuests ?? this.totalGuests,
        defaultCheckIn: defaultCheckIn ?? this.defaultCheckIn,
        defaultCheckOut: defaultCheckOut ?? this.defaultCheckOut,
        rooms: rooms ?? this.rooms,
        depositHtg: depositHtg ?? this.depositHtg,
        amountPaidHtg: amountPaidHtg ?? this.amountPaidHtg,
        status: status ?? this.status,
      );
}

/// Nights for one allocation (same rules as synthetic group reservation rows).
int groupAllocationNights(
  MockGroupReservation g,
  MockGroupRoomAllocation a,
) {
  final ci = parseHotelCalendarDate(a.checkInDate ?? g.defaultCheckIn);
  final co = parseHotelCalendarDate(a.checkOutDate ?? g.defaultCheckOut);
  if (ci == null || co == null) return 1;
  final n = co.difference(ci).inDays;
  return n > 0 ? n : 1;
}

/// Sum of nightly rate × nights for all rooms in the group (room-stay bill).
double groupRoomStayTotalHtg(MockGroupReservation g) {
  var sum = 0.0;
  for (final a in g.rooms) {
    sum += a.priceHtg * groupAllocationNights(g, a);
  }
  return sum;
}

/// Positive = guest owes more; negative = credit / refund due vs [amountPaidHtg].
double groupStayBalanceHtg(MockGroupReservation g) {
  return groupRoomStayTotalHtg(g) - g.amountPaidHtg;
}

/// Parses check-in / check-out strings used across hotel mock data (e.g. `Jan 5, 2026`).
DateTime? parseHotelCalendarDate(String s) {
  final cleaned = s.replaceAll(RegExp(r'\s+\d+:\d+.*$'), '').trim();
  for (final fmt in ['MMM d, yyyy', 'MMM d']) {
    try {
      final d = DateFormat(fmt).parse(cleaned);
      if (!fmt.contains('y')) {
        return DateTime(DateTime.now().year, d.month, d.day);
      }
      return d;
    } catch (_) {}
  }
  return null;
}

/// Synthetic blocking rows for each group room (availability / picker only).
List<MockReservation> individualReservationsFromGroup(MockGroupReservation g) {
  final out = <MockReservation>[];
  for (final alloc in g.rooms) {
    final ciStr = alloc.checkInDate ?? g.defaultCheckIn;
    final coStr = alloc.checkOutDate ?? g.defaultCheckOut;
    final ci = parseHotelCalendarDate(ciStr);
    final co = parseHotelCalendarDate(coStr);
    if (ci == null || co == null) continue;
    final nightCount = co.difference(ci).inDays;
    final nights = nightCount > 0 ? nightCount : 1;
    final name = g.groupName != null && g.groupName!.trim().isNotEmpty
        ? '${g.groupName!.trim()} (${g.contactName})'
        : g.contactName;
    out.add(MockReservation(
      id: 0,
      confirmationCode: g.confirmationCode,
      guestName: name,
      phone: g.contactPhone,
      email: g.contactEmail,
      notes: 'Réservation de groupe',
      idType: g.contactIdType,
      idNumber: g.contactIdNumber,
      roomType: alloc.roomType,
      roomNumber: alloc.roomNumber,
      checkInDate: ciStr,
      checkOutDate: coStr,
      nights: nights,
      guests: alloc.guestNames.isEmpty ? 1 : alloc.guestNames.length,
      depositHtg: 0,
      isPaid: false,
      status: 'confirmed',
      roomId: alloc.roomId,
    ));
  }
  return out;
}

/// Blocks inventory for the room picker and group flow (synthetic rows; list UI
/// uses [MockGroupReservation] directly, not these rows).
List<MockReservation> mockReservationsWithGroupBlocks(
  List<MockReservation> individual,
  List<MockGroupReservation> groups,
) {
  final expanded = <MockReservation>[];
  for (final g in groups) {
    if (g.status == 'cancelled') continue;
    expanded.addAll(individualReservationsFromGroup(g));
  }
  return [...individual, ...expanded];
}

class GroupReservationsNotifier
    extends StateNotifier<List<MockGroupReservation>> {
  GroupReservationsNotifier() : super([]);
  int get _nextId => state.isEmpty
      ? 1
      : state.map((r) => r.id).reduce((a, b) => a > b ? a : b) + 1;
  void add(MockGroupReservation r) =>
      state = [...state, r.copyWith(id: _nextId)];
  void update(MockGroupReservation r) =>
      state = [for (final x in state) x.id == r.id ? r : x];
  void remove(int id) => state = state.where((r) => r.id != id).toList();
}

// ──────────────── PROVIDERS ────────────────

final mockRoomsProvider = StateNotifierProvider<RoomsNotifier, List<MockRoom>>(
  (ref) => RoomsNotifier(),
);

final mockReservationsProvider =
    StateNotifierProvider<ReservationsNotifier, List<MockReservation>>(
  (ref) => ReservationsNotifier(),
);

final mockGuestsProvider =
    StateNotifierProvider<GuestsNotifier, List<MockGuest>>(
  (ref) => GuestsNotifier(),
);

final mockHotelRestaurantOrdersProvider = StateNotifierProvider<
    HotelRestaurantOrdersNotifier, List<MockHotelRestaurantOrder>>(
  (ref) => HotelRestaurantOrdersNotifier(),
);

/// Tracks which hotel restaurant order is currently being edited (add items mode).
final activeEditHotelOrderIdProvider = StateProvider<int?>((ref) => null);

final mockGroupReservationsProvider = StateNotifierProvider<
    GroupReservationsNotifier, List<MockGroupReservation>>(
  (ref) => GroupReservationsNotifier(),
);

// ── Table merge snapshot ──────────────────────────────────────────────────────

/// Immutable snapshot of the hotel restaurant order absorbed when two tables merged.
class MergedHotelTableSnapshot {
  final int orderId;
  final String tableName;
  final DateTime mergedAt;
  final List<MockHotelOrderItem> items;
  final double totalHtg;
  final String? waiter;
  final String? guestName;

  const MergedHotelTableSnapshot({
    required this.orderId,
    required this.tableName,
    required this.mergedAt,
    required this.items,
    required this.totalHtg,
    this.waiter,
    this.guestName,
  });
}

const Object _sentinel = Object();
