abstract final class SupabaseConfig {
  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://tscmfdcmocvowipweyrb.supabase.co',
  );

  // This is the client-safe anon key. Never place a service_role key here.
  static const publishableKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.'
        'eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRzY21mZGNtb2N2b3dpcHdleXJiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODM4ODU1MzksImV4cCI6MjA5OTQ2MTUzOX0.'
        'a03wYT91TeISre_-wp8R4Rk7x3eoTpTLn1UMPb1z3as',
  );

  static bool get isConfigured => url.isNotEmpty && publishableKey.isNotEmpty;
}
