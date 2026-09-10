abstract final class SupabaseConfig {
  // These two defaults are public client settings. Private server credentials
  // are never included in Flutter or the APK.
  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://tscmfdcmocvowipweyrb.supabase.co',
  );
  static const publishableKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_Hg7c0yfqKL1wxaLvLown4Q_19G7Dqw5',
  );
  static const communityApiUrl = String.fromEnvironment(
    'COMMUNITY_API_URL',
    defaultValue: 'http://10.0.2.2:3001',
  );

  static bool get isConfigured => url.isNotEmpty && publishableKey.isNotEmpty;
}
