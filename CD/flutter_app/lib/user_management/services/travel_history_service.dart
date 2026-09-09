import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/travel_history_entry.dart';

class TravelHistoryFailure implements Exception {
  const TravelHistoryFailure(this.message);

  final String message;
}

class TravelHistoryService {
  TravelHistoryService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<List<TravelHistoryEntry>> fetchCompletedTrips() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const TravelHistoryFailure('Please sign in again.');
    }

    try {
      final rows = await _client
          .from('travel_group_trip_sessions')
          .select(
            'id, started_by, started_at, ended_at, '
            'travel_groups!inner(name, destination), '
            'travel_group_trip_participants(user_id)',
          )
          .eq('status', 'completed')
          .not('ended_at', 'is', null)
          .order('ended_at', ascending: false);

      return rows
          .where((row) => _belongsToUser(row, user.id))
          .map(TravelHistoryEntry.fromSupabase)
          .toList(growable: false);
    } catch (error) {
      if (error is TravelHistoryFailure) rethrow;
      if (error is SocketException || error is TimeoutException) {
        throw const TravelHistoryFailure(
          'Unable to load your travel history. Check your connection.',
        );
      }
      throw const TravelHistoryFailure(
        'Your completed trips could not be loaded. Please try again.',
      );
    }
  }

  bool _belongsToUser(Map<String, dynamic> row, String userId) {
    if (row['started_by'] == userId) return true;
    final participants = row['travel_group_trip_participants'];
    if (participants is! List) return false;
    return participants.any(
      (participant) =>
          participant is Map && participant['user_id']?.toString() == userId,
    );
  }
}
