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
      if (history.isNotEmpty) return history;

      // The shared history table may be hidden by RLS even though the
      // Community security-definer function can see this user's eligible
      // completed trips. Prefer those real IDs so Create/Edit Post can
      // pass server-side ownership validation. Local demo IDs must never be
      // sent to the Community publishing API.
      final eligibleHistory = await _fetchEligibleCommunityHistoryTrips();
      return eligibleHistory;
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
      return history;
    } catch (_) {
      return const [];
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

  Future<List<TravelHistoryEntry>> _fetchEligibleCommunityHistoryTrips() async {
    try {
      final response = await _client.rpc(
        'eligible_community_history_entries_v6',
      );
      final rows = (response as List<dynamic>).cast<Map<String, dynamic>>();
      return rows.map(_eligibleHistoryFromCommunity).toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  TravelHistoryEntry _eligibleHistoryFromCommunity(Map<String, dynamic> row) {
    final completedAt =
        DateTime.tryParse(row['ended_at']?.toString() ?? '') ?? DateTime.now();
    final destination =
        row['location_name']?.toString().trim() ?? 'Unknown destination';
    final isGroup = row['source_type']?.toString() == 'group';
    final fallbackTitle = isGroup
        ? 'Completed group trip'
        : 'Completed solo trip';
    final title = row['title']?.toString().trim() ?? fallbackTitle;

    return TravelHistoryEntry(
      id: row['id'].toString(),
      type: isGroup ? TravelHistoryType.group : TravelHistoryType.solo,
      title: title.isEmpty ? fallbackTitle : title,
      destination: destination.isEmpty ? 'Unknown destination' : destination,
      startedAt: completedAt.subtract(const Duration(hours: 1)),
      completedAt: completedAt,
      stops: const [],
      distanceKm: 0,
      durationMinutes: 60,
      tags: const [],
      travelMode: 'Not recorded',
      isPersisted: true,
    );
  }
}
