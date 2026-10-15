/// Synthetic facilities for the Spark exhibition. No real-world booking.
class DemoVenue {
  const DemoVenue(
      {required this.id,
      required this.slug,
      required this.name,
      required this.locationLabel,
      required this.size,
      required this.indoor,
      required this.price});
  final int id;
  final String slug;
  final String name;
  final String locationLabel;
  final String size;
  final bool indoor;
  final int price;
  int get courtId => id * 10 + 1;

  Map<String, dynamic> get card => {
        'id': id,
        'name': name,
        'roadAddress': locationLabel,
        'latitude': 0.0,
        'longitude': 0.0,
        'thumbnailUrl': null,
        'minPrice': price,
        'hasIndoor': indoor,
        'hasOutdoor': !indoor,
        'sizes': [size],
        'facilities': <String>[],
        'dataSource': 'EXHIBITION',
        'availableSlots': 3,
      };

  Map<String, dynamic> get detail => {
        ...card,
        'description': '전시용 가상 시설입니다. 실제 풋살장이 아니며 결제·대관이 이루어지지 않습니다.',
        'regionCode': '',
        'phone': null,
        'rules': '캡스톤 전시용 화면입니다. 실제 예약·대관과 관계없습니다.',
        'verificationStatus': 'VERIFIED',
        'cancelPolicy': [
          {'hoursBefore': 0, 'refundPercent': 100}
        ],
        'photos': <Object>[],
        'courts': [
          {
            'id': courtId,
            'name': '시연 코트',
            'isIndoor': indoor,
            'surface': 'ARTIFICIAL_TURF',
            'sizeClass': size,
            'isActive': true,
          }
        ],
        'facilities': <Object>[],
      };
}

const demonstrationVenues = <DemoVenue>[
  DemoVenue(
      id: 101,
      slug: 'demo-01',
      name: '시연용 풋살장 A (가상)',
      locationLabel: '서울권 시연 데이터 · 실제 주소 아님',
      size: '5V5',
      indoor: true,
      price: 45000),
  DemoVenue(
      id: 102,
      slug: 'demo-02',
      name: '시연용 풋살장 B (가상)',
      locationLabel: '경기권 시연 데이터 · 실제 주소 아님',
      size: '6V6',
      indoor: false,
      price: 55000),
  DemoVenue(
      id: 103,
      slug: 'demo-03',
      name: '시연용 풋살장 C (가상)',
      locationLabel: '서울권 시연 데이터 · 실제 주소 아님',
      size: '5V5',
      indoor: false,
      price: 40000),
  DemoVenue(
      id: 104,
      slug: 'demo-04',
      name: '시연용 풋살장 D (가상)',
      locationLabel: '경기권 시연 데이터 · 실제 주소 아님',
      size: '6V6',
      indoor: true,
      price: 60000),
];

DemoVenue? findDemoVenue(int id) {
  for (final venue in demonstrationVenues) {
    if (venue.id == id || venue.courtId == id) return venue;
  }
  return null;
}

String demoDateKey(DateTime value) =>
    '${value.year}${value.month.toString().padLeft(2, '0')}${value.day.toString().padLeft(2, '0')}';

String demoSlotId(DemoVenue venue, DateTime value) =>
    '${venue.slug}_${demoDateKey(value)}_${value.hour.toString().padLeft(2, '0')}';
