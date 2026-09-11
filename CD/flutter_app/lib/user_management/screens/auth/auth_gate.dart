import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/auth_service.dart';
import '../../services/traveler_profile_service.dart';
import '../profile_screen.dart';
import '../travel_preferences_screen.dart';
import 'login_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key, this.authenticatedHome});

  final Widget? authenticatedHome;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final AuthService _authService = AuthService();
  final TravelerProfileService _travelerProfileService =
      TravelerProfileService();
  StreamSubscription<AuthState>? _subscription;
  Session? _session;
  Future<bool>? _onboardingCheck;
  bool _onboardingCompletedThisSession = false;

  @override
  void initState() {
    super.initState();
    _session = _authService.currentSession;
    if (_session != null) _refreshOnboardingCheck();
    _subscription = _authService.authStateChanges.listen(
      (authState) {
        if (!mounted) return;
        setState(() {
          _session = authState.session;
          if (authState.session == null) {
            _onboardingCompletedThisSession = false;
            _onboardingCheck = null;
          } else if (!_onboardingCompletedThisSession) {
            _onboardingCheck = _hasCompletedOnboarding();
          }
        });
      },
      onError: (Object error, StackTrace stackTrace) {
        // Auth refresh errors are handled without crashing the application.
      },
    );
  }

  void _refreshOnboardingCheck() {
    _onboardingCheck = _hasCompletedOnboarding();
  }

  Future<bool> _hasCompletedOnboarding() async {
    final profile = await _travelerProfileService.fetchCurrentProfile();
    return profile?.hasCompletedOnboarding ?? false;
  }

  void _onOnboardingSaved(List<String> _) {
    setState(() {
      _onboardingCompletedThisSession = true;
      _onboardingCheck = Future.value(true);
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_session == null) {
      return const LoginScreen();
    }
    if (_onboardingCompletedThisSession) {
      return widget.authenticatedHome ?? const ProfileScreen();
    }
    return FutureBuilder<bool>(
      future: _onboardingCheck ??= _hasCompletedOnboarding(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            body: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Your travel profile could not be loaded.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: () => setState(_refreshOnboardingCheck),
                        child: const Text('Retry'),
                      ),
                      TextButton(
                        onPressed: _authService.logout,
                        child: const Text('Log out'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
        if (snapshot.data != true) {
          return TravelPreferencesScreen(onSaved: _onOnboardingSaved);
        }
        return widget.authenticatedHome ?? const ProfileScreen();
      },
    );
  }
}
