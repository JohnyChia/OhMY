import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter_android/google_maps_flutter_android.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:community_discovery/community_discovery.dart';

import 'app_shell/ohmy_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  if (defaultTargetPlatform == TargetPlatform.android) {
    final mapsImplementation = GoogleMapsFlutterPlatform.instance;
    if (mapsImplementation is GoogleMapsFlutterAndroid) {
      mapsImplementation.useAndroidViewSurface = true;
    }
  }

  runApp(const _OhMyBootstrap());
}

class _OhMyBootstrap extends StatefulWidget {
  const _OhMyBootstrap();

  @override
  State<_OhMyBootstrap> createState() => _OhMyBootstrapState();
}

class _OhMyBootstrapState extends State<_OhMyBootstrap> {
  static const _minimumInitializationPageDuration = Duration(
    milliseconds: 1600,
  );

  late final Future<bool> _serviceInitialization;
  bool _showInitializationPage = true;
  bool _supabaseEnabled = false;

  @override
  void initState() {
    super.initState();
    _serviceInitialization = _initializeServices();
    // Start the minimum display time only after Flutter has painted the full
    // initialization artwork. Debug/plugin startup can take longer than a
    // timer started before the first frame and would otherwise skip the page.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_finishInitialization());
    });
  }

  Future<bool> _initializeServices() async {
    final supabaseEnabled = SupabaseConfig.isConfigured;
    if (supabaseEnabled) {
      await Supabase.initialize(
        url: SupabaseConfig.url,
        publishableKey: SupabaseConfig.publishableKey,
      );
    }
    return supabaseEnabled;
  }

  Future<void> _finishInitialization() async {
    final minimumDisplay = Future<void>.delayed(
      _minimumInitializationPageDuration,
    );
    var supabaseEnabled = false;
    try {
      supabaseEnabled = await _serviceInitialization;
    } catch (error, stackTrace) {
      debugPrint('App service initialization failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
    await minimumDisplay;
    if (!mounted) return;
    setState(() {
      _supabaseEnabled = supabaseEnabled;
      _showInitializationPage = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_showInitializationPage) {
      return OhMyApp(supabaseEnabled: _supabaseEnabled);
    }
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.white,
        body: SizedBox.expand(
          child: Image.asset(
            'assets/images/branding/initialize_page.png',
            fit: BoxFit.cover,
            gaplessPlayback: true,
          ),
        ),
      ),
    );
  }
}
