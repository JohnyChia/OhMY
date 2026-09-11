import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:community_discovery/community_discovery.dart';

import 'user_management/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!SupabaseConfig.isConfigured) {
    throw StateError(
      'Set SUPABASE_URL and SUPABASE_ANON_KEY with --dart-define.',
    );
  }

  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  );

  runApp(const OhMyApp());
}
