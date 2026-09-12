import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class CommunityValidationException implements Exception {
  const CommunityValidationException({
    required this.reason,
    this.fieldErrors = const <String, String>{},
  });

  final String reason;
  final Map<String, String> fieldErrors;

  @override
  String toString() => reason;
}

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
    required String historyEntryId,
    required String title,
    required String description,
    required List<String> imagePaths,
  }) async {
    final body = await _send('/community/posts', {
      'historyEntryId': historyEntryId,
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
      final fieldErrors = <String, String>{};
      for (final entry
          in (decoded['fieldErrors'] as Map? ?? const {}).entries) {
        final message = '${entry.value}'.trim();
        if (message.isNotEmpty) fieldErrors['${entry.key}'] = message;
      }
      throw CommunityValidationException(
        reason: decoded['reason'] as String? ?? 'The post was rejected.',
        fieldErrors: fieldErrors,
      );
    }
    return decoded;
  }

  void close() => _client.close();
}
