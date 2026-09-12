import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/verification_config.dart';
import '../models/verification_result.dart';

class VerificationFailure implements Exception {
  const VerificationFailure(this.message);

  final String message;
}

class VerificationService {
  VerificationService({SupabaseClient? client, http.Client? httpClient})
    : _client = client ?? Supabase.instance.client,
      _httpClient = httpClient ?? http.Client();

  final SupabaseClient _client;
  final http.Client _httpClient;

  Future<VerificationResult> submit({
    required String documentType,
    required String documentFrontPath,
    String? documentBackPath,
    required String selfiePath,
  }) async {
    final accessToken = _client.auth.currentSession?.accessToken;
    if (accessToken == null) {
      throw const VerificationFailure('Please sign in again to continue.');
    }

    final request =
        http.MultipartRequest(
            'POST',
            Uri.parse('${VerificationConfig.backendUrl}/verify'),
          )
          ..headers['Authorization'] = 'Bearer $accessToken'
          ..fields['document_type'] = documentType
          ..files.addAll([
            await http.MultipartFile.fromPath(
              'document_front',
              documentFrontPath,
            ),
            await http.MultipartFile.fromPath('selfie', selfiePath),
          ]);

    if (documentBackPath != null) {
      request.files.add(
        await http.MultipartFile.fromPath('document_back', documentBackPath),
      );
    }

    try {
      final streamed = await _httpClient
          .send(request)
          .timeout(const Duration(seconds: 90));
      final response = await http.Response.fromStream(streamed);
      return parseResponse(response);
    } on VerificationFailure {
      rethrow;
    } on SocketException {
      throw const VerificationFailure(
        'Cannot reach the verification service. Check that the laptop backend is running.',
      );
    } on TimeoutException {
      throw const VerificationFailure(
        'Verification took too long. Please try again with clear photos.',
      );
    } on FormatException {
      throw const VerificationFailure(
        'The verification service returned an invalid response.',
      );
    }
  }

  static VerificationResult parseResponse(http.Response response) {
    Map<String, dynamic>? body;
    if (response.body.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          body = decoded;
        }
      } on FormatException {
        // Status handling below provides the useful message for non-JSON errors.
      }
    }

    if (response.statusCode >= 400) {
      final apiMessage = body?['message'] ?? body?['detail'];
      if (apiMessage is String && apiMessage.trim().isNotEmpty) {
        throw VerificationFailure(apiMessage.trim());
      }
      if (response.statusCode >= 500) {
        throw const VerificationFailure(
          'The verification service is unavailable. Check that the laptop backend is running.',
        );
      }
      throw const VerificationFailure(
        'Verification could not be completed. Please check the photos and try again.',
      );
    }

    if (body == null) {
      throw const VerificationFailure(
        'The verification service returned an invalid response.',
      );
    }
    return VerificationResult.fromJson(body);
  }

  Future<void> refreshVerifiedSession() async {
    await _client.auth.refreshSession();
  }
}
