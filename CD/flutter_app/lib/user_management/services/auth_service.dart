import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_user_profile.dart';

class AuthFailure implements Exception {
  const AuthFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

class AuthService {
  AuthService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;
  static const _avatarBucket = 'profile-avatars';

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  Session? get currentSession => _client.auth.currentSession;

  User? get currentUser => _client.auth.currentUser;

  AppUserProfile? get currentProfile {
    final user = currentUser;
    return user == null ? null : AppUserProfile.fromAuthUser(user);
  }

  Future<AppUserProfile> fetchCurrentProfile() async {
    try {
      final response = await _client.auth.getUser();
      final user = response.user;
      if (user == null) {
        throw const AuthFailure('Your signed-in profile could not be loaded.');
      }
      return _withSignedAvatar(AppUserProfile.fromAuthUser(user));
    } catch (error) {
      if (error is AuthFailure) rethrow;
      throw _friendlyFailure(error);
    }
  }

  Future<AuthResponse> register({
    required String username,
    required String email,
    required String password,
  }) async {
    try {
      final response = await _client.auth.signUp(
        email: email.trim().toLowerCase(),
        password: password,
        data: {
          'username': username.trim(),
          // Keep the legacy key temporarily because existing teammate screens
          // may still read it as the public display name.
          'full_name': username.trim(),
        },
      );

      // With email confirmation enabled, Supabase can deliberately return an
      // obfuscated user with no identities instead of an error for an existing
      // address. Convert that response into the clear registration message
      // required by this prototype.
      if (response.session == null &&
          response.user?.identities != null &&
          response.user!.identities!.isEmpty) {
        throw const AuthFailure('This email address is already registered.');
      }
      return response;
    } catch (error) {
      if (error is AuthFailure) rethrow;
      throw _friendlyFailure(error);
    }
  }

  Future<void> verifyRegistrationOtp({
    required String email,
    required String otp,
  }) async {
    try {
      await _client.auth.verifyOTP(
        email: email.trim(),
        token: otp.trim(),
        type: OtpType.email,
      );
    } catch (error) {
      throw _friendlyFailure(error);
    }
  }

  Future<void> resendRegistrationOtp(String email) async {
    try {
      await _client.auth.resend(type: OtpType.signup, email: email.trim());
    } catch (error) {
      throw _friendlyFailure(error);
    }
  }

  Future<void> login({required String email, required String password}) async {
    try {
      await _client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
    } catch (error) {
      throw _friendlyFailure(error);
    }
  }

  Future<void> logout() async {
    try {
      await _client.auth.signOut();
    } catch (error) {
      throw _friendlyFailure(error);
    }
  }

  Future<void> sendPasswordRecoveryOtp(String email) async {
    try {
      // Supabase intentionally does not reveal whether this email exists.
      await _client.auth.resetPasswordForEmail(email.trim());
    } catch (error) {
      throw _friendlyFailure(error);
    }
  }

  Future<void> verifyPasswordRecoveryOtp({
    required String email,
    required String otp,
  }) async {
    try {
      await _client.auth.verifyOTP(
        email: email.trim(),
        token: otp.trim(),
        type: OtpType.recovery,
      );
    } catch (error) {
      throw _friendlyFailure(error);
    }
  }

  Future<void> updatePassword(String newPassword) async {
    try {
      await _client.auth.updateUser(UserAttributes(password: newPassword));
    } catch (error) {
      throw _friendlyFailure(error);
    }
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = currentUser;
    final email = user?.email?.trim();
    if (user == null || email == null || email.isEmpty) {
      throw const AuthFailure('Please sign in again before changing password.');
    }

    // updateUser can accept an active session without checking the supplied
    // current password. Explicitly sign in first so an incorrect current
    // password can never reach the password-update request.
    try {
      final response = await _client.auth.signInWithPassword(
        email: email,
        password: currentPassword,
      );
      if (response.user?.id != user.id) {
        throw const AuthFailure('Your current password is incorrect.');
      }
    } on AuthException catch (error) {
      final code = error.code?.toLowerCase();
      final message = error.message.toLowerCase();
      if (code == 'invalid_credentials' ||
          message.contains('invalid login credentials')) {
        throw const AuthFailure('Your current password is incorrect.');
      }
      throw _friendlyFailure(error);
    } catch (error) {
      if (error is AuthFailure) rethrow;
      throw _friendlyFailure(error);
    }

    try {
      await _client.auth.updateUser(UserAttributes(password: newPassword));
    } catch (error) {
      throw _friendlyFailure(error);
    }
  }

  Future<AppUserProfile> uploadProfilePhoto({
    required Uint8List bytes,
    required String extension,
    required String contentType,
  }) async {
    final user = currentUser;
    if (user == null) {
      throw const AuthFailure('Please sign in before changing your photo.');
    }

    final safeExtension = extension.toLowerCase();
    if (!const {'jpg', 'jpeg', 'png', 'webp'}.contains(safeExtension)) {
      throw const AuthFailure('Choose a JPG, PNG or WebP image.');
    }
    if (bytes.length > 5 * 1024 * 1024) {
      throw const AuthFailure('The profile photo must be smaller than 5 MB.');
    }

    final previousPath = (user.userMetadata?['avatar_path'] as String?)?.trim();
    final path = '${user.id}/avatar.$safeExtension';
    try {
      await _client.storage
          .from(_avatarBucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              cacheControl: '3600',
              upsert: true,
              contentType: contentType,
            ),
          );
      final response = await _client.auth.updateUser(
        UserAttributes(data: {'avatar_path': path}),
      );
      final updatedUser = response.user;
      if (updatedUser == null) {
        throw const AuthFailure('Your profile photo could not be saved.');
      }
      if (previousPath != null && previousPath != path) {
        await _client.storage.from(_avatarBucket).remove([previousPath]);
      }
      return _withSignedAvatar(AppUserProfile.fromAuthUser(updatedUser));
    } on StorageException catch (error) {
      if (kDebugMode) debugPrint('Supabase Storage error: ${error.message}');
      throw const AuthFailure(
        'The profile photo could not be uploaded. Please try another image.',
      );
    } catch (error) {
      if (error is AuthFailure) rethrow;
      throw _friendlyFailure(error);
    }
  }

  Future<AppUserProfile> updateFullName(String fullName) async {
    final currentBio = currentProfile?.bio ?? '';
    return updateProfile(fullName: fullName, bio: currentBio);
  }

  Future<AppUserProfile> updateProfile({
    required String fullName,
    required String bio,
  }) async {
    try {
      final response = await _client.auth.updateUser(
        UserAttributes(
          data: {
            'username': fullName.trim(),
            'full_name': fullName.trim(),
            'bio': bio.trim(),
          },
        ),
      );
      final user = response.user;
      if (user == null) {
        throw const AuthFailure('Your profile could not be updated.');
      }
      return AppUserProfile.fromAuthUser(user);
    } catch (error) {
      if (error is AuthFailure) rethrow;
      throw _friendlyFailure(error);
    }
  }

  Future<AppUserProfile> _withSignedAvatar(AppUserProfile profile) async {
    final path = profile.avatarPath;
    if (path == null || path.isEmpty) return profile;
    try {
      final url = await _client.storage
          .from(_avatarBucket)
          .createSignedUrl(path, 60 * 60);
      return profile.withAvatarUrl(url);
    } on StorageException {
      // A missing or unavailable photo must not prevent the rest of the
      // profile from loading.
      return profile.withAvatarUrl(null);
    }
  }

  AuthFailure _friendlyFailure(Object error) {
    if (error is AuthFailure) return error;

    if (error is SocketException || error is TimeoutException) {
      return const AuthFailure(
        'Unable to connect. Check your internet connection and try again.',
      );
    }

    if (error is AuthException) {
      final message = error.message.toLowerCase();
      final code = error.code?.toLowerCase();

      if (kDebugMode) {
        debugPrint(
          'Supabase Auth error: status=${error.statusCode}, '
          'code=${error.code}, message=${error.message}',
        );
      }

      if (code == 'email_address_invalid') {
        return const AuthFailure(
          'Please use a valid, deliverable email address.',
        );
      }
      if (code == 'email_address_not_authorized') {
        return const AuthFailure(
          'This email cannot receive authentication messages yet. '
          'Check the Supabase SMTP settings.',
        );
      }
      if (code == 'user_already_exists' ||
          code == 'email_exists' ||
          message.contains('already registered') ||
          message.contains('already exists')) {
        return const AuthFailure('This email address is already registered.');
      }
      if (code == 'weak_password') {
        return const AuthFailure(
          'Use a password that meets the required format.',
        );
      }
      if (code == 'same_password' ||
          message.contains('different from the old')) {
        return const AuthFailure(
          'Your new password must be completely different from your old password.',
        );
      }
      if (code == 'current_password_mismatch' ||
          code == 'current_password_required') {
        return const AuthFailure('Your current password is incorrect.');
      }
      if (code == 'over_email_send_rate_limit' ||
          code == 'over_request_rate_limit' ||
          message.contains('rate limit') ||
          message.contains('too many')) {
        return const AuthFailure(
          'Too many attempts. Please wait before trying again.',
        );
      }
      if (code == 'signup_disabled') {
        return const AuthFailure(
          'New account registration is currently disabled.',
        );
      }
      if ((message.contains('email') && message.contains('send')) ||
          message.contains('smtp')) {
        return const AuthFailure(
          'The verification email could not be sent. '
          'Please check the Supabase SMTP username and password.',
        );
      }

      if (message.contains('invalid login credentials')) {
        return const AuthFailure('Invalid email address or password.');
      }
      if (message.contains('email not confirmed')) {
        return const AuthFailure('Please verify your email before signing in.');
      }
      if (message.contains('password')) {
        return const AuthFailure(
          'The password does not meet the required format.',
        );
      }
      if (message.contains('token') ||
          message.contains('otp') ||
          message.contains('expired')) {
        return const AuthFailure('The code is invalid or has expired.');
      }
      if (code == 'unexpected_failure' || error.statusCode == '500') {
        return const AuthFailure(
          'The authentication service could not complete the request. '
          'Please check the Supabase Auth logs and email configuration.',
        );
      }

      return const AuthFailure(
        'Authentication could not be completed. Please try again.',
      );
    }

    return const AuthFailure('Something went wrong. Please try again.');
  }
}
