import 'package:flutter_test/flutter_test.dart';
import 'package:fmate_app/core/models.dart';
import 'package:fmate_app/firebase_original_ui/demo_venue_catalog.dart';
import 'package:fmate_app/firebase_original_ui/firebase_legacy_api.dart';

void main() {
  test('Spark records still use collaborator VenueCard and VenueDetail models', () {
    expect(demonstrationVenues.length, 4);
    expect(demonstrationVenues.map((venue) => venue.id).toSet().length, 4);
    for (final venue in demonstrationVenues) {
      final card = VenueCard.fromJson(venue.card);
      final detail = VenueDetail.fromJson(venue.detail);
      expect(card.id, detail.id);
      expect(card.name, contains('가상'));
      expect(card.dataSource, 'EXHIBITION');
      expect(detail.courts.single.id, venue.courtId);
      expect(detail.description, contains('전시용'));
    }
  });

  test('Firestore slot IDs use the preserved date/hour contract', () {
    final day = DateTime(2026, 10, 16, 18);
    expect(demoDateKey(day), '20261016');
    expect(demoSlotId(demonstrationVenues.first, day), 'demo-01_20261016_18');
  });

  test('display IDs are deterministic for Firebase UIDs', () {
    expect(FirebaseLegacyApi.displayId('firebase-uid-1'),
        FirebaseLegacyApi.displayId('firebase-uid-1'));
    expect(FirebaseLegacyApi.displayId('firebase-uid-1'),
        isNot(FirebaseLegacyApi.displayId('firebase-uid-2')));
  });
}
