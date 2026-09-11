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
          .from('travel_history_entries')
          .select()
          .eq('user_id', user.id)
          .order('ended_at', ascending: false);
      final history = rows
          .map(TravelHistoryEntry.fromSupabase)
          .toList(growable: false);
      return history.isEmpty ? _demoCompletedTrips() : history;
    } on PostgrestException catch (error) {
      if (_isMissingHistoryTable(error)) {
        return _fetchLegacyCompletedGroupTrips(user.id);
      }
      throw const TravelHistoryFailure(
        'Your completed trips could not be loaded. Please try again.',
      );
    } on SocketException {
      throw const TravelHistoryFailure(
        'Unable to load your travel history. Check your connection.',
      );
    } on TimeoutException {
      throw const TravelHistoryFailure(
        'Unable to load your travel history. Check your connection.',
      );
    } on TravelHistoryFailure {
      rethrow;
    } catch (_) {
      throw const TravelHistoryFailure(
        'Your completed trips could not be loaded. Please try again.',
      );
    }
  }

  Future<void> recordCompletedTrip(CompletedTravelDraft draft) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const TravelHistoryFailure('Please sign in again.');
    }

    try {
      await _client
          .from('travel_history_entries')
          .insert(draft.toSupabase(user.id));
    } on PostgrestException catch (error) {
      if (error.code == '23505') return;
      if (_isMissingHistoryTable(error)) {
        throw const TravelHistoryFailure(
          'Travel history storage is not configured yet.',
        );
      }
      throw const TravelHistoryFailure(
        'The trip finished, but its history could not be saved.',
      );
    } on SocketException {
      throw const TravelHistoryFailure(
        'The trip finished, but its history could not be saved while offline.',
      );
    } on TimeoutException {
      throw const TravelHistoryFailure(
        'The trip finished, but saving its history timed out.',
      );
    }
  }

  Future<List<TravelHistoryEntry>> _fetchLegacyCompletedGroupTrips(
    String userId,
  ) async {
    try {
      final rows = await _client
          .from('travel_group_trip_sessions')
          .select(
            'id, started_by, started_at, ended_at, '
            'travel_groups!inner(name, destination, tags), '
            'travel_group_trip_participants(user_id)',
          )
          .eq('status', 'completed')
          .not('ended_at', 'is', null)
          .order('ended_at', ascending: false);

      final history = rows
          .where((row) => _belongsToUser(row, userId))
          .map(TravelHistoryEntry.fromLegacyGroup)
          .toList(growable: false);
      return history.isEmpty ? _demoCompletedTrips() : history;
    } catch (_) {
      return _demoCompletedTrips();
    }
  }

  bool _belongsToUser(Map<String, dynamic> row, String userId) {
    if (row['started_by']?.toString() == userId) return true;
    final participants = row['travel_group_trip_participants'];
    if (participants is! List) return false;
    return participants.any(
      (participant) =>
          participant is Map && participant['user_id']?.toString() == userId,
    );
  }

  bool _isMissingHistoryTable(PostgrestException error) {
    return error.code == 'PGRST205' || error.code == '42P01';
  }

  List<TravelHistoryEntry> _demoCompletedTrips() {
    return [
      TravelHistoryEntry(
        id: 'demo-group-puchong',
        type: TravelHistoryType.group,
        title: 'Puchong Group Adventure',
        destination: 'Puchong, Selangor',
        startedAt: DateTime(2026, 9, 7, 9),
        completedAt: DateTime(2026, 9, 7, 17, 15),
        stops: [
          TravelHistoryStop(
            name: 'IOI Mall Puchong',
            visitedAt: DateTime(2026, 9, 7, 9, 30),
          ),
          TravelHistoryStop(
            name: 'SetiaWalk Puchong',
            visitedAt: DateTime(2026, 9, 7, 11),
          ),
          TravelHistoryStop(
            name: 'Foo Hing Dim Sum',
            visitedAt: DateTime(2026, 9, 7, 13),
          ),
          TravelHistoryStop(
            name: 'Wawasan Hill Trail',
            visitedAt: DateTime(2026, 9, 7, 15, 15),
          ),
        ],
        distanceKm: 24.6,
        durationMinutes: 495,
        tags: const ['Food', 'Nature'],
        travelMode: 'Car + Walking',
        isPersisted: false,
      ),
      TravelHistoryEntry(
        id: 'demo-solo-tarumt',
        type: TravelHistoryType.solo,
        title: 'TAR UMT Campus Trip',
        destination: 'TAR UMT, Kuala Lumpur',
        startedAt: DateTime(2026, 9, 5, 8, 30),
        completedAt: DateTime(2026, 9, 5, 10),
        stops: [
          TravelHistoryStop(
            name: 'TAR UMT Main Entrance',
            visitedAt: DateTime(2026, 9, 5, 9, 45),
          ),
          TravelHistoryStop(
            name: 'TAR UMT Kuala Lumpur Main Campus',
            visitedAt: DateTime(2026, 9, 5, 10),
          ),
        ],
        distanceKm: 13.2,
        durationMinutes: 90,
        tags: const ['Education', 'Solo'],
        travelMode: 'Driving',
        isPersisted: false,
      ),
    ];
  }
}
