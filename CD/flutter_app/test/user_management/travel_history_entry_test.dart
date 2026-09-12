import 'package:flutter_app/user_management/models/travel_history_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps a completed Supabase trip session', () {
    final entry = TravelHistoryEntry.fromSupabase({
      'id': 'session-id',
      'started_at': '2026-09-01T01:00:00Z',
      'ended_at': '2026-09-01T04:00:00Z',
      'travel_groups': {
        'name': 'KL Food Journey',
        'destination': 'Kuala Lumpur',
      },
    });

    expect(entry.id, 'session-id');
    expect(entry.title, 'KL Food Journey');
    expect(entry.destination, 'Kuala Lumpur');
    expect(entry.completedAt, DateTime.utc(2026, 9, 1, 4));
    expect(entry.isPersisted, isFalse);
    expect(entry.canShareToCommunity, isFalse);
  });

  test('maps a completed unified trip with itinerary details', () {
    final entry = TravelHistoryEntry.fromSupabase({
      'id': 'history-id',
      'source_type': 'solo',
      'title': 'Batu Caves Solo Trip',
      'destination': 'Batu Caves',
      'started_at': '2026-09-10T01:00:00Z',
      'ended_at': '2026-09-10T02:15:00Z',
      'distance_km': 12.4,
      'duration_minutes': 75,
      'tags': ['Cultural'],
      'travel_mode': 'Driving',
      'itinerary': [
        {'name': 'Batu Caves', 'visited_at': '2026-09-10T02:15:00Z'},
      ],
    });

    expect(entry.type, TravelHistoryType.solo);
    expect(entry.stops.single.name, 'Batu Caves');
    expect(entry.distanceKm, 12.4);
    expect(entry.durationMinutes, 75);
    expect(entry.isPersisted, isTrue);
    expect(entry.canShareToCommunity, isTrue);
  });

  test('exposes Community posting for a persisted group history row', () {
    final entry = TravelHistoryEntry.fromSupabase({
      'id': 'group-history-id',
      'source_type': 'group',
      'title': 'Group city tour',
      'destination': 'Kuala Lumpur',
      'started_at': '2026-09-10T01:00:00Z',
      'ended_at': '2026-09-10T02:15:00Z',
      'itinerary': const [],
    });

    expect(entry.isPersisted, isTrue);
    expect(entry.canShareToCommunity, isTrue);
  });
}
