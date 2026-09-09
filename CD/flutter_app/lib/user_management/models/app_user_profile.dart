import 'package:supabase_flutter/supabase_flutter.dart';

enum TravellerVerificationStatus { unverified, verified }

class AppUserProfile {
  const AppUserProfile({
    required this.userId,
    required this.email,
    required this.fullName,
    required this.bio,
    required this.avatarPath,
    required this.avatarUrl,
    required this.verificationStatus,
  });

  final String userId;
  final String email;
  final String fullName;
  final String bio;
  final String? avatarPath;
  final String? avatarUrl;
  final TravellerVerificationStatus verificationStatus;

  bool get isVerified =>
      verificationStatus == TravellerVerificationStatus.verified;

  factory AppUserProfile.fromAuthUser(User user) {
    final userMetadata = user.userMetadata ?? const <String, dynamic>{};
    final appMetadata = user.appMetadata;

    // app_metadata cannot be changed by the Flutter user. A future secure
    // eKYC backend or Edge Function can set is_verified after verification.
    final isVerified = appMetadata['is_verified'] == true;

    return AppUserProfile(
      userId: user.id,
      email: user.email ?? '',
      fullName:
          (userMetadata['username'] as String?)?.trim() ??
          (userMetadata['full_name'] as String?)?.trim() ??
          '',
      bio: (userMetadata['bio'] as String?)?.trim() ?? '',
      avatarPath: (userMetadata['avatar_path'] as String?)?.trim(),
      avatarUrl: userMetadata['avatar_url'] as String?,
      verificationStatus: isVerified
          ? TravellerVerificationStatus.verified
          : TravellerVerificationStatus.unverified,
    );
  }

  AppUserProfile withAvatarUrl(String? value) => AppUserProfile(
    userId: userId,
    email: email,
    fullName: fullName,
    bio: bio,
    avatarPath: avatarPath,
    avatarUrl: value,
    verificationStatus: verificationStatus,
  );
}
