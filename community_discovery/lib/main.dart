import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/community_app.dart';
import 'src/config/supabase_config.dart';
import 'src/data/community_repository.dart';
import 'src/data/supabase_community_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!SupabaseConfig.isConfigured) {
    runApp(const _ConfigurationRequiredApp());
    return;
  }
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  );
  final CommunityRepository repository = SupabaseCommunityRepository(
    Supabase.instance.client,
    communityApiUrl: SupabaseConfig.communityApiUrl,
  );
  runApp(CommunityApp(repository: repository));
}

class _ConfigurationRequiredApp extends StatelessWidget {
  const _ConfigurationRequiredApp();

  @override
  Widget build(BuildContext context) => const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(28),
            child: Text(
              'Supabase is not configured. Run with '
              '--dart-define-from-file=config/flutter.env.json. '
              'Demo posts have been removed.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    ),
  );
}
