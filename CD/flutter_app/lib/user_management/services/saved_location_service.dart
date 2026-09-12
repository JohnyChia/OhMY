import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/saved_location.dart';

final savedLocationService = SavedLocationService();

class SavedLocationService {
  SavedLocationService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;
  final ValueNotifier<int> changes = ValueNotifier<int>(0);
  List<SavedLocation> _cached = const [];
  String? _cachedUserId;

  List<SavedLocation> get cached => List.unmodifiable(_cached);

  String contentHashFor(Map<String, dynamic> item) {
    final place = Map<String, dynamic>.from(item['place'] as Map? ?? const {});
    final id = place['id']?.toString().trim();
    if (id != null && id.isNotEmpty) return 'place:$id';
    final location = Map<String, dynamic>.from(
      place['location'] as Map? ?? const {},
    );
    final name =
        (place['displayName'] as Map?)?['text']?.toString().trim() ?? 'unknown';
    return 'place:${name.toLowerCase()}:${location['latitude']}:${location['longitude']}';
  }

  bool isSaved(Map<String, dynamic> item) {
    final userId = _client.auth.currentUser?.id;
    if (userId == null || userId != _cachedUserId) return false;
    final hash = contentHashFor(item);
    return _cached.any((location) => location.contentHash == hash);
  }

  Future<List<SavedLocation>> fetch({bool force = false}) async {
    final user = _client.auth.currentUser;
    if (user == null) throw const SavedLocationFailure('Please sign in first.');
    if (!force && _cachedUserId == user.id) return cached;
    try {
      final rows = await _client
          .from('saved_travel_items')
          .select()
          .eq('source_type', 'place')
          .order('created_at', ascending: false);
      _cachedUserId = user.id;
      _cached = List<Map<String, dynamic>>.from(rows)
          .map(SavedLocation.fromRow)
          .where(
            (location) =>
                location.latitude.abs() <= 90 &&
                location.longitude.abs() <= 180,
          )
          .toList(growable: false);
      changes.value++;
      return cached;
    } on PostgrestException catch (error) {
      throw SavedLocationFailure(_friendlyMessage(error));
    } catch (_) {
      throw const SavedLocationFailure(
        'Could not load saved locations. Check your connection and try again.',
      );
    }
  }

  Future<bool> toggle(Map<String, dynamic> item) async {
    final user = _client.auth.currentUser;
    if (user == null) throw const SavedLocationFailure('Please sign in first.');
    if (_cachedUserId != user.id) await fetch(force: true);
    final hash = contentHashFor(item);
    final existing = _cached.where((entry) => entry.contentHash == hash);
    if (existing.isNotEmpty) {
      await remove(existing.first);
      return false;
    }
    await save(item);
    return true;
  }

  Future<SavedLocation> save(Map<String, dynamic> item) async {
    final user = _client.auth.currentUser;
    if (user == null) throw const SavedLocationFailure('Please sign in first.');
    final place = _jsonMap(item['place']);
    final analysis = _jsonMap(item['analysis']);
    final ranking = _jsonMap(item['ranking']);
    final location = _jsonMap(place['location']);
    final latitude = (location['latitude'] as num?)?.toDouble();
    final longitude = (location['longitude'] as num?)?.toDouble();
    if (latitude == null || longitude == null) {
      throw const SavedLocationFailure(
        'This place cannot be saved because its location is unavailable.',
      );
    }
    final title = (place['displayName'] as Map?)?['text']?.toString().trim();
    final tags = <String>{
      ...List<String>.from(analysis['generalTags'] as List? ?? const []),
      ...List<String>.from(analysis['culturalTags'] as List? ?? const []),
      ...List<String>.from(item['matchedPreferences'] as List? ?? const []),
    }.where((value) => value.trim().isNotEmpty).toList(growable: false);
    final payload = <String, dynamic>{
      'user_id': user.id,
      'source_type': 'place',
      'source_name': 'Google Places',
      'content_hash': contentHashFor(item),
      'title': title == null || title.isEmpty ? 'Saved place' : title,
      'summary': place['description']?.toString() ?? '',
      'location_hint': place['formattedAddress']?.toString() ?? '',
      'google_place_id': place['id']?.toString(),
      'latitude': latitude,
      'longitude': longitude,
      'travel_tags': tags,
      'metadata': {
        'place': place,
        'analysis': analysis,
        if (ranking.isNotEmpty) 'ranking': ranking,
        if (item['matchedPreferences'] is List)
          'matchedPreferences': List<dynamic>.from(
            item['matchedPreferences'] as List,
          ),
      },
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    try {
      final row = await _client
          .from('saved_travel_items')
          .upsert(payload, onConflict: 'user_id,content_hash')
          .select()
          .single();
      final saved = SavedLocation.fromRow(row);
      _cachedUserId = user.id;
      _cached = [
        saved,
        ..._cached.where((entry) => entry.contentHash != saved.contentHash),
      ];
      changes.value++;
      return saved;
    } on PostgrestException catch (error) {
      throw SavedLocationFailure(_friendlyMessage(error));
    }
  }

  Future<void> remove(SavedLocation location) async {
    final user = _client.auth.currentUser;
    if (user == null) throw const SavedLocationFailure('Please sign in first.');
    try {
      await _client
          .from('saved_travel_items')
          .delete()
          .eq('user_id', user.id)
          .eq('content_hash', location.contentHash);
      _cached = _cached
          .where((entry) => entry.contentHash != location.contentHash)
          .toList(growable: false);
      changes.value++;
    } on PostgrestException catch (error) {
      throw SavedLocationFailure(_friendlyMessage(error));
    }
  }

  Map<String, dynamic> _jsonMap(dynamic value) {
    if (value is! Map) return <String, dynamic>{};
    return Map<String, dynamic>.from(
      jsonDecode(jsonEncode(value)) as Map<String, dynamic>,
    );
  }

  String _friendlyMessage(PostgrestException error) {
    if (error.code == '42P01') {
      return 'Saved locations are not configured in Supabase yet.';
    }
    return 'Could not update saved locations. Please try again.';
  }
}

class SavedLocationFailure implements Exception {
  const SavedLocationFailure(this.message);
  final String message;
  @override
  String toString() => message;
}
