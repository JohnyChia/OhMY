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
  });
}
