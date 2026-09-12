import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_app/user_management/services/auth_service.dart';
import 'package:flutter_app/user_management/services/password_recovery_account_service.dart';

void main() {
  test('unknown email prevents the Supabase recovery request', () async {
    var recoveryRequests = 0;
    final lookup = PasswordRecoveryAccountService(
      httpClient: MockClient((request) async {
        expect(jsonDecode(request.body)['email'], 'unknown@example.com');
        return http.Response('{"registered":false}', 200);
      }),
    );
    final client = SupabaseClient(
      'https://test.supabase.co',
      'anon',
      httpClient: MockClient((request) async {
        recoveryRequests++;
        return http.Response('{}', 200);
      }),
    );
    final auth = AuthService(client: client, recoveryAccountService: lookup);
    await expectLater(
      auth.sendPasswordRecoveryOtp(' Unknown@example.com '),
      throwsA(
        isA<AuthFailure>().having(
          (e) => e.message,
          'message',
          'This email address is not registered.',
        ),
      ),
    );
    expect(recoveryRequests, 0);
    await client.dispose();
  });

  test('registered email sends the Supabase recovery request', () async {
    var recoveryRequests = 0;
    final lookup = PasswordRecoveryAccountService(
      httpClient: MockClient(
        (_) async => http.Response('{"registered":true}', 200),
      ),
    );
    final client = SupabaseClient(
      'https://test.supabase.co',
      'anon',
      authOptions: AuthClientOptions(pkceAsyncStorage: _MemoryPkceStorage()),
      httpClient: MockClient((request) async {
        expect(request.url.path, '/auth/v1/recover');
        recoveryRequests++;
        return http.Response('{}', 200);
      }),
    );
    await AuthService(
      client: client,
      recoveryAccountService: lookup,
    ).sendPasswordRecoveryOtp('known@example.com');
    expect(recoveryRequests, 1);
    await client.dispose();
  });

  for (final response in [
    http.Response('{}', 503),
    http.Response('bad json', 200),
    http.Response('{"registered":"false"}', 200),
    http.Response('{}', 429),
  ]) {
    test(
      'lookup failure ${response.statusCode}/${response.body} cannot send OTP',
      () async {
        var recoveryRequests = 0;
        final lookup = PasswordRecoveryAccountService(
          httpClient: MockClient((_) async => response),
        );
        final client = SupabaseClient(
          'https://test.supabase.co',
          'anon',
          httpClient: MockClient((_) async {
            recoveryRequests++;
            return http.Response('{}', 200);
          }),
        );
        await expectLater(
          AuthService(
            client: client,
            recoveryAccountService: lookup,
          ).sendPasswordRecoveryOtp('known@example.com'),
          throwsA(isA<AuthFailure>()),
        );
        expect(recoveryRequests, 0);
        await client.dispose();
      },
    );
  }
}

class _MemoryPkceStorage extends GotrueAsyncStorage {
  final Map<String, String> values = {};
  @override
  Future<String?> getItem({required String key}) async => values[key];
  @override
  Future<void> setItem({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) async {
    values.remove(key);
  }
}
