import 'package:flutter/material.dart';
import 'package:community_discovery/community_discovery.dart';
import 'package:flutter_app/shared/widgets/wau_loading_indicator.dart';
import 'package:flutter_app/shared/widgets/ohmy_snack_bar.dart';

import '../models/app_user_profile.dart';
import '../models/traveler_profile.dart';
import '../services/auth_service.dart';
import '../services/traveler_profile_service.dart';
import 'edit_profile_screen.dart';
import 'travel_history_screen.dart';
import 'verification/verification_capture_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    this.showBottomNavigation = true,
    this.communityController,
  });

  final bool showBottomNavigation;
  final CommunityController? communityController;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _authService = AuthService();
  final _travelerProfileService = TravelerProfileService();
  AppUserProfile? _profile;
  TravelerProfile? _travelerProfile;
  bool _isLoading = true;
  bool _isLoggingOut = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final results = await Future.wait([
        _authService.fetchCurrentProfile(),
        _travelerProfileService.fetchCurrentProfile(),
      ]);
      if (!mounted) return;
      setState(() {
        _profile = results[0] as AppUserProfile;
        _travelerProfile = results[1] as TravelerProfile?;
      });
    } on AuthFailure catch (error) {
      if (mounted) setState(() => _loadError = error.message);
    } on TravelerProfileFailure catch (error) {
      if (mounted) setState(() => _loadError = error.message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _openEditProfile() async {
    final profile = _profile;
    if (profile == null) return;
    final changed = await Navigator.of(context, rootNavigator: true).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => EditProfileScreen(
          profile: profile,
          initialPreferences: _travelerProfile?.favoriteCategories ?? const [],
        ),
      ),
    );
    if (changed == true) await _loadProfile();
  }

  Future<void> _openVerification() async {
    if (_profile?.isVerified == true) return;
    final verified = await Navigator.of(context, rootNavigator: true)
        .push<bool>(
          MaterialPageRoute<bool>(
            builder: (_) => const VerificationCaptureScreen(),
          ),
        );
    if (verified == true) await _loadProfile();
  }

  Future<void> _openBookmarks() async {
    final controller = widget.communityController;
    if (controller == null) {
      _showLaterMessage('Bookmarks');
      return;
    }
    await openCommunityBookmarks(context, controller: controller);
  }

  Future<void> _openTravelHistory() async {
    await Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => TravelHistoryScreen(
          communityController: widget.communityController,
        ),
      ),
    );
  }

  Future<void> _logout() async {
    setState(() => _isLoggingOut = true);
    try {
      await _authService.logout();
    } on AuthFailure catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        OhMySnackBar(content: Text(error.message), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoggingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(child: _buildBody()),
      bottomNavigationBar: widget.showBottomNavigation
          ? const _ProfileNavigationBar()
          : null,
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: WauLoadingIndicator(size: 58));
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_loadError!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _loadProfile,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final profile = _profile!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 34, 16, 24),
      children: [
        Center(child: _ProfileAvatar(profile: profile)),
        const SizedBox(height: 14),
        const Text(
          'My profile',
          style: TextStyle(
            color: Color(0xFF1A2438),
            fontSize: 28,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          profile.fullName.isEmpty
              ? 'Manage your identity and travel activity'
              : '${profile.fullName} • ${profile.email}',
          style: const TextStyle(color: Color(0xFF596680), fontSize: 13),
        ),
        const SizedBox(height: 16),
        _VerificationCard(profile: profile, onTap: _openVerification),
        const SizedBox(height: 12),
        _MenuCard(
          title: 'Edit profile  ›',
          subtitle: 'Update your personal details and travel preferences',
          onTap: _openEditProfile,
        ),
        const SizedBox(height: 12),
        _MenuCard(
          title: 'History  ›',
          subtitle: 'View past completed trips and visited destinations',
          onTap: _openTravelHistory,
        ),
        const SizedBox(height: 12),
        _MenuCard(
          title: 'Bookmarks  ›',
          subtitle: 'View your saved places and attractions',
          onTap: _openBookmarks,
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: _isLoggingOut ? null : _logout,
          icon: _isLoggingOut
              ? const SizedBox.square(
                  dimension: 18,
                  child: WauLoadingIndicator(size: 18),
                )
              : const Icon(Icons.logout),
          label: const Text('Log out'),
        ),
      ],
    );
  }

  void _showLaterMessage(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      OhMySnackBar(
        content: Text('$feature will be connected in a later stage.'),
      ),
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.profile});

  final AppUserProfile profile;

  @override
  Widget build(BuildContext context) {
    final initial = profile.fullName.isNotEmpty
        ? profile.fullName[0].toUpperCase()
        : (profile.email.isNotEmpty ? profile.email[0].toUpperCase() : '?');
    final fallback = Container(
      color: const Color(0xFFD9E8FF),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          color: Color(0xFF2E60C4),
          fontSize: 30,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    final url = profile.avatarUrl;
    return ClipOval(
      child: SizedBox.square(
        dimension: 92,
        child: url == null || url.isEmpty
            ? fallback
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
              ),
      ),
    );
  }
}

class _VerificationCard extends StatelessWidget {
  const _VerificationCard({required this.profile, required this.onTap});

  final AppUserProfile profile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final verified = profile.isVerified;
    return Material(
      color: verified ? const Color(0xFFE5F2FF) : const Color(0xFFFFF6E5),
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: verified ? const Color(0xFFC7D6F2) : const Color(0xFFF3C56A),
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: verified ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                verified ? '✓  Verified Traveller' : 'Verify now  ›',
                style: TextStyle(
                  color: verified
                      ? const Color(0xFF1F4D9E)
                      : const Color(0xFFB54708),
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                verified
                    ? 'Identity and selfie approved • Linked to this account only'
                    : 'Verify to unlock Travel Groups. One identity can be linked to one account only.',
                style: TextStyle(
                  color: verified
                      ? const Color(0xFF1A2438)
                      : const Color(0xFF6A4B13),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: Color(0xFFC7D6F2)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(color: Color(0xFF1A2438), fontSize: 15),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: const TextStyle(color: Color(0xFF616B80), fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileNavigationBar extends StatelessWidget {
  const _ProfileNavigationBar();

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: 4,
      onDestinationSelected: (_) {},
      destinations: const [
        NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
        NavigationDestination(icon: Icon(Icons.auto_awesome), label: 'AI Chat'),
        NavigationDestination(
          icon: Icon(Icons.route_outlined),
          label: 'Start Trip',
        ),
        NavigationDestination(
          icon: Icon(Icons.groups_outlined),
          label: 'Community',
        ),
        NavigationDestination(icon: Icon(Icons.person), label: 'Profile'),
      ],
    );
  }
}
