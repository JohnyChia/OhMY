import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class CommunityValidationApi {
  CommunityValidationApi({
    required String baseUrl,
    required SupabaseClient supabase,
    http.Client? client,
  }) : _baseUrl = baseUrl.replaceFirst(RegExp(r'/$'), ''),
       _supabase = supabase,
       _client = client ?? http.Client();

  final String _baseUrl;
  final SupabaseClient _supabase;
  final http.Client _client;

  Future<String> createPost({
    required String tripSessionId,
    required String title,
    required String description,
    required List<String> imagePaths,
  }) async {
    final body = await _send('/community/posts', {
      'tripSessionId': tripSessionId,
      'title': title,
      'description': description,
      'imagePaths': imagePaths,
    });
    return body['postId'] as String;
  }

  Future<String> updatePost({
    required String postId,
    required String title,
    required String description,
    required List<String> imagePaths,
  }) async {
    final body = await _send('/community/posts/$postId', {
      'title': title,
      'description': description,
      'imagePaths': imagePaths,
    }, method: 'PATCH');
    return body['postId'] as String;
  }

  Future<Map<String, dynamic>> _send(
    String path,
    Map<String, dynamic> payload, {
    String method = 'POST',
  }) async {
    final token = _supabase.auth.currentSession?.accessToken;
    if (token == null) throw StateError('Please sign in before publishing.');
    late http.Response response;
    try {
      final uri = Uri.parse('$_baseUrl$path');
      final headers = {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };
      response =
          await (method == 'PATCH'
                  ? _client.patch(
                      uri,
                      headers: headers,
                      body: jsonEncode(payload),
                    )
                  : _client.post(
                      uri,
                      headers: headers,
                      body: jsonEncode(payload),
                    ))
              .timeout(const Duration(seconds: 12));
    } catch (_) {
      throw StateError(
        'Validation service is unavailable. Check your connection and retry.',
      );
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final fieldErrors = (decoded['fieldErrors'] as Map?)?.values
          .map((value) => '$value')
          .where((value) => value.trim().isNotEmpty)
          .toSet()
          .join(' ');
      throw StateError(
        fieldErrors?.isNotEmpty == true
            ? fieldErrors!
            : decoded['reason'] as String? ?? 'The post was rejected.',
      );
    }
    return decoded;
  }

  void close() => _client.close();
}
