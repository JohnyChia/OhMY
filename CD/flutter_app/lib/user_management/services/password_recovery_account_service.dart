import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class RecoveryAccountCheckFailure implements Exception {
  const RecoveryAccountCheckFailure(this.message);
  final String message;
}

class PasswordRecoveryAccountService {
  PasswordRecoveryAccountService({http.Client? httpClient, String? backendUrl})
    : _httpClient = httpClient,
      _backendUrl =
          backendUrl ??
          const String.fromEnvironment(
            'AUTH_API_URL',
            defaultValue: 'http://10.0.2.2:8001',
          );

  final http.Client? _httpClient;
  final String _backendUrl;

  Future<bool> isRegistered(String email) async {
    try {
      final uri = Uri.parse('$_backendUrl/auth/email-registered');
      final headers = {'Content-Type': 'application/json'};
      final body = jsonEncode({'email': email.trim().toLowerCase()});
      // http.post closes its temporary client; injected clients belong to
      // the caller (tests), so this service never closes those clients.
      final response =
          await (_httpClient != null
                  ? _httpClient.post(uri, headers: headers, body: body)
                  : http.post(uri, headers: headers, body: body))
              .timeout(const Duration(seconds: 20));
      if (response.statusCode == 429) {
        throw const RecoveryAccountCheckFailure(
          'Too many attempts. Please wait a minute and try again.',
        );
      }
      if (response.statusCode != 200) {
        throw const RecoveryAccountCheckFailure(
          'Cannot check your account right now. Please try again.',
        );
      }
      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic> || data['registered'] is! bool) {
        throw const FormatException('Invalid account-check response');
      }
      return data['registered'] as bool;
    } on RecoveryAccountCheckFailure {
      rethrow;
    } catch (error) {
      if (kDebugMode)
        debugPrint('Recovery account check failed: ${error.runtimeType}');
      throw const RecoveryAccountCheckFailure(
        'Cannot check your account. Make sure the laptop authentication '
        'service is running and try again.',
      );
    }
  }
}
