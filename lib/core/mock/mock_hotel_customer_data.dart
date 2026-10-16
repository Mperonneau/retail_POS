// Mock hotel stays and balance per customer for the hotel customer detail section.
// Links customer IDs to hotel-specific stay/balance data.

class MockHotelStay {
  final String roomName;
  final int totalGuests;
  final int totalDays;
  final double amountHtg;
  final double amountUsd;
  final double paidHtg;
  final double balanceHtg;

  const MockHotelStay({
    required this.roomName,
    required this.totalGuests,
    required this.totalDays,
    required this.amountHtg,
    required this.amountUsd,
    this.paidHtg = 0,
    this.balanceHtg = 0,
  });
}

/// Mock hotel stays keyed by customer ID. Used when showing hotel context in customer detail.
final mockHotelStaysByCustomerId = <String, List<MockHotelStay>>{
  'c1': [
    const MockHotelStay(
      roomName: 'Room 102',
      totalGuests: 2,
      totalDays: 3,
      amountHtg: 25500,
      amountUsd: 255,
      paidHtg: 10000,
      balanceHtg: 15500,
    ),
  ],
  'c2': [
    const MockHotelStay(
      roomName: 'Room 203',
      totalGuests: 1,
      totalDays: 2,
      amountHtg: 28000,
      amountUsd: 280,
      paidHtg: 0,
      balanceHtg: 28000,
    ),
  ],
  'c4': [
    const MockHotelStay(
      roomName: 'Suite 301',
      totalGuests: 4,
      totalDays: 5,
      amountHtg: 125000,
      amountUsd: 1250,
      paidHtg: 50000,
      balanceHtg: 75000,
    ),
  ],
};
