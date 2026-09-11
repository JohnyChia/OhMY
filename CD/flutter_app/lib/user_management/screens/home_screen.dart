import 'package:flutter/material.dart';
import 'package:flutter_app/shared/widgets/wau_loading_indicator.dart';
import 'package:flutter_app/shared/widgets/ohmy_snack_bar.dart';

import '../models/app_user_profile.dart';
import '../services/auth_service.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _authService = AuthService();
  bool _isLoggingOut = false;

  Future<void> _logout() async {
    setState(() => _isLoggingOut = true);
    try {
      await _authService.logout();
    } on AuthFailure catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        OhMySnackBar(
          content: Text(error.message),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoggingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = _authService.currentProfile;

    return Scaffold(
      appBar: AppBar(
        title: const Text('ohMY Travel'),
        actions: [
          IconButton(
            tooltip: 'Profile',
            onPressed: profile == null
                ? null
                : () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ProfileScreen(),
                      ),
                    );
                    if (mounted) setState(() {});
                  },
            icon: const Icon(Icons.account_circle_outlined),
          ),
          IconButton(
            tooltip: 'Logout',
            onPressed: _isLoggingOut ? null : _logout,
            icon: _isLoggingOut
                ? const SizedBox.square(
                    dimension: 20,
                    child: WauLoadingIndicator(size: 20),
                  )
                : const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  profile?.fullName.isNotEmpty == true
                      ? 'Hello, ${profile!.fullName}'
                      : 'Hello, traveller',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Your authentication foundation is ready.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(color: Colors.black54),
                ),
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 28,
                          child: Text(
                            _initial(profile),
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                profile?.email ?? '',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              _VerificationBadge(profile: profile),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Open profile',
                          onPressed: profile == null
                              ? null
                              : () async {
                                  await Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => const ProfileScreen(),
                                    ),
                                  );
                                  if (mounted) setState(() {});
                                },
                          icon: const Icon(Icons.chevron_right),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.info_outline),
                    title: Text('Authentication stage'),
                    subtitle: Text(
                      'Bookmarks, travel history and identity verification will be connected in later stages.',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _initial(AppUserProfile? profile) {
    final name = profile?.fullName.trim() ?? '';
    if (name.isNotEmpty) return name[0].toUpperCase();
    final email = profile?.email.trim() ?? '';
    return email.isNotEmpty ? email[0].toUpperCase() : '?';
  }
}

class _VerificationBadge extends StatelessWidget {
  const _VerificationBadge({required this.profile});

  final AppUserProfile? profile;

  @override
  Widget build(BuildContext context) {
    final isVerified = profile?.isVerified ?? false;
    final color = isVerified ? Colors.green : Colors.orange.shade800;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isVerified ? Icons.verified : Icons.gpp_maybe_outlined,
          size: 18,
          color: color,
        ),
        const SizedBox(width: 6),
        Text(
          isVerified ? 'Verified Traveller' : 'Unverified Traveller',
          style: TextStyle(color: color, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
