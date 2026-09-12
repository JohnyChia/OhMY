import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/traveler_profile.dart';

/// Session-scoped copy of the authenticated traveller's compulsory interests.
/// AuthGate loads this before the app shell is shown and profile edits refresh it.
final ValueNotifier<List<String>> currentTravelerPreferences =
    ValueNotifier<List<String>>(const []);

void clearCurrentTravelerPreferences() {
  currentTravelerPreferences.value = const [];
}

class TravelerProfileFailure implements Exception {
  const TravelerProfileFailure(this.message);

  final String message;
}

class TravelerProfileService {
  TravelerProfileService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<TravelerProfile?> fetchCurrentProfile() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const TravelerProfileFailure('Please sign in again.');
    }

    try {
      final data = await _client
          .from('traveler_profiles')
          .select(
            'user_id, preferred_language, travel_style, '
            'favorite_categories, budget_preference',
          )
          .eq('user_id', user.id)
          .maybeSingle();

      final profile = data == null ? null : TravelerProfile.fromJson(data);
      currentTravelerPreferences.value = List<String>.unmodifiable(
        profile?.favoriteCategories ?? const [],
      );
      return profile;
    } catch (error) {
      throw _friendlyFailure(error);
    }
  }

  Future<List<String>> requireCurrentPreferences() async {
    final profile = await fetchCurrentProfile();
    final preferences = profile?.favoriteCategories
            .map((category) => category.trim())
            .where((category) => category.isNotEmpty)
            .toSet()
            .toList(growable: false) ??
        const <String>[];
    if (preferences.length < 3) {
      throw const TravelerProfileFailure(
        'Your travel preferences are unavailable. Complete your profile first.',
      );
    }
    return preferences;
  }

  Future<TravelerProfile> saveFavoriteCategories(
    List<String> categories,
  ) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const TravelerProfileFailure('Please sign in again.');
    }
    if (categories.length < 3) {
      throw const TravelerProfileFailure('Please select at least 3 interests.');
    }

    try {
      final data = await _client
          .from('traveler_profiles')
          .upsert({
            'user_id': user.id,
            'favorite_categories': categories,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          }, onConflict: 'user_id')
          .select(
            'user_id, preferred_language, travel_style, '
            'favorite_categories, budget_preference',
          )
          .single();

      final profile = TravelerProfile.fromJson(data);
      await _client.auth.updateUser(
        UserAttributes(data: {'needs_preferences_onboarding': false}),
      );
      currentTravelerPreferences.value = List<String>.unmodifiable(
        profile.favoriteCategories,
      );
      return profile;
    } catch (error) {
      throw _friendlyFailure(error);
    }
  }

  TravelerProfileFailure _friendlyFailure(Object error) {
    if (error is TravelerProfileFailure) return error;
    if (error is SocketException || error is TimeoutException) {
      return const TravelerProfileFailure(
        'Unable to connect. Check your internet connection and try again.',
      );
    }
    if (error is PostgrestException && error.code == '42501') {
      return const TravelerProfileFailure(
        'Travel preferences are not permitted yet. Run the traveler profile '
        'RLS migration in Supabase, then try again.',
      );
    }
    return const TravelerProfileFailure(
      'Your travel preferences could not be saved. Please try again.',
    );
  }
}
