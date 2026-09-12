import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:community_discovery/community_discovery.dart';

import '../ai_chatbot/main.dart' show ChatScreen;
import '../preference_recommender/pages/place_map_page.dart';
import '../travel_group/features/travel_group/controllers/travel_group_controller.dart';
import '../travel_group/features/travel_group/models/travel_group_models.dart';
import '../travel_group/features/travel_group/repositories/mock_travel_group_repository.dart';
import '../travel_group/features/travel_group/repositories/supabase_travel_group_repository.dart';
import '../travel_group/features/travel_group/screens/travel_group_discovery_screen.dart';
import '../travel_group/features/travel_group/services/live_trip_location_service.dart';
import '../travel_group/features/travel_group/services/supabase_live_trip_location_service.dart';
import '../user_management/screens/auth/auth_gate.dart';
import '../user_management/screens/profile_screen.dart';
import '../user_management/services/traveler_profile_service.dart';
import 'ohmy_bottom_navigation_bar.dart';

// Temporary development switch. Pass
// --dart-define=BYPASS_TRAVEL_GROUP_VERIFICATION=false to restore the gate.
const _bypassTravelGroupVerification = bool.fromEnvironment(
  'BYPASS_TRAVEL_GROUP_VERIFICATION',
  defaultValue: true,
);

class OhMyApp extends StatelessWidget {
  const OhMyApp({super.key, required this.supabaseEnabled});

  final bool supabaseEnabled;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ohMY',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3266CC)),
        scaffoldBackgroundColor: const Color(0xFFF8FBFF),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
        ),
      ),
      home: supabaseEnabled
          ? AuthGate(authenticatedHome: const OhMyShell(supabaseEnabled: true))
          : const OhMyShell(supabaseEnabled: false),
    );
  }
}

class OhMyShell extends StatefulWidget {
  const OhMyShell({super.key, required this.supabaseEnabled});

  final bool supabaseEnabled;

  @override
  State<OhMyShell> createState() => _OhMyShellState();
}

class _OhMyShellState extends State<OhMyShell> {
  int _selectedIndex = 0;
  final _navigatorKeys = List.generate(5, (_) => GlobalKey<NavigatorState>());
  CommunityController? _communityController;
  late final TravelGroupController _travelGroupController;
  late final List<WidgetBuilder> _rootBuilders;
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    final authUser = widget.supabaseEnabled
        ? Supabase.instance.client.auth.currentUser
        : null;
    final travelUser = authUser == null ? null : _prototypeUser(authUser);
    _travelGroupController = TravelGroupController(
      repository: widget.supabaseEnabled
          ? SupabaseTravelGroupRepository(Supabase.instance.client)
          : MockTravelGroupRepository.seeded(),
      currentUser: travelUser,
      allowDemoVerification:
          !widget.supabaseEnabled || _bypassTravelGroupVerification,
      liveTripLocationServiceFactory: widget.supabaseEnabled
          ? createSupabaseLiveTripLocationService
          : createMockLiveTripLocationService,
    )..addListener(_onTravelGroupChanged);
    if (widget.supabaseEnabled) {
      _authSubscription = Supabase.instance.client.auth.onAuthStateChange
          .listen((authState) {
            final user = authState.session?.user;
            if (user == null ||
                user.id != _travelGroupController.currentUser.id) {
              return;
            }
            _travelGroupController.switchUser(_prototypeUser(user));
          });
      final CommunityRepository communityRepository =
          SupabaseCommunityRepository(
            Supabase.instance.client,
            communityApiUrl: SupabaseConfig.communityApiUrl,
          );
      _communityController = CommunityController(communityRepository);
    }
    _rootBuilders = [
      (context) => HomeModulePage(onOpenTab: _selectTab),
      (context) => const ChatScreen(showBottomNavigation: false),
      (context) => StartTripHubPage(controller: _travelGroupController),
      (context) => _communityController == null
          ? const ModuleSetupPage(
              icon: Icons.groups_outlined,
              title: 'Community setup required',
              message:
                  'Start Flutter with SUPABASE_URL, SUPABASE_ANON_KEY, and COMMUNITY_API_URL.',
            )
          : CommunityModulePage(
              controller: _communityController!,
              onStartJourney: _openCommunityLocationInStartTrip,
            ),
      (context) => widget.supabaseEnabled
          ? ProfileScreen(
              showBottomNavigation: false,
              communityController: _communityController,
            )
          : const ModuleSetupPage(
              icon: Icons.person_outline,
              title: 'Profile setup required',
              message:
                  'Start Flutter with SUPABASE_URL and SUPABASE_ANON_KEY to use authentication and profile features.',
            ),
    ];
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _travelGroupController
      ..removeListener(_onTravelGroupChanged)
      ..dispose();
    _communityController?.dispose();
    super.dispose();
  }

  PrototypeUser _prototypeUser(User user) {
    final metadata = user.userMetadata ?? const <String, dynamic>{};
    final appMetadata = user.appMetadata;
    return PrototypeUser(
      id: user.id,
      name:
          (metadata['username'] ??
                  metadata['full_name'] ??
                  user.email ??
                  'Traveller')
              .toString(),
      isVerified:
          _bypassTravelGroupVerification || appMetadata['is_verified'] == true,
    );
  }

  void _onTravelGroupChanged() {
    if (mounted) setState(() {});
  }

  void _returnToGroup() {
    if (_selectedIndex != 2) setState(() => _selectedIndex = 2);
  }

  void _selectTab(int index) {
    if (_selectedIndex == index) {
      _navigatorKeys[index].currentState?.popUntil((route) => route.isFirst);
      return;
    }
    setState(() => _selectedIndex = index);
  }

  Future<void> _openCommunityLocationInStartTrip(
    StartJourneyRequest request,
  ) async {
    final query = request.attractionName.trim().isNotEmpty
        ? request.attractionName.trim()
        : request.destinationName.trim();
    if (!mounted) return;

    if (_selectedIndex != 2) {
      setState(() => _selectedIndex = 2);
      await Future<void>.delayed(Duration.zero);
    }

    final navigator = _navigatorKeys[2].currentState;
    if (navigator == null || !mounted) return;
    navigator.popUntil((route) => route.isFirst);
    await navigator.push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/start-trip/solo-map'),
        builder: (_) => PlaceMapPage(initialSearchQuery: query),
      ),
    );
  }

  Future<bool> _handleBack() async {
    final navigator = _navigatorKeys[_selectedIndex].currentState;
    if (navigator != null && await navigator.maybePop()) return false;
    if (_selectedIndex != 0) {
      _selectTab(0);
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (await _handleBack() && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        body: Stack(
          children: [
            IndexedStack(
              index: _selectedIndex,
              children: List.generate(
                _rootBuilders.length,
                (index) => Navigator(
                  key: _navigatorKeys[index],
                  onGenerateRoute: (_) =>
                      MaterialPageRoute<void>(builder: _rootBuilders[index]),
                ),
              ),
            ),
            if (_selectedIndex != 2 &&
                _travelGroupController.activeGroup != null &&
                _travelGroupController.isMember)
              Positioned(
                right: 14,
                bottom: 12,
                child: _ReturnToGroupButton(
                  group: _travelGroupController.activeGroup!,
                  onPressed: _returnToGroup,
                ),
              ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: OhMyBottomNavigationBar(
            selectedIndex: _selectedIndex,
            onSelected: _selectTab,
          ),
        ),
      ),
    );
  }
}

class HomeModulePage extends StatelessWidget {
  const HomeModulePage({super.key, required this.onOpenTab});

  final ValueChanged<int> onOpenTab;

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.paddingOf(context).top;
    final greeting = _greeting();
    final userName = _userName();

    return Scaffold(
      backgroundColor: const Color(0xFFF9FBFE),
      body: Stack(
        children: [
          Container(
            height: 150,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF8FB1FA), Color(0xFF9CBBFF)],
              ),
            ),
          ),
          ListView(
            padding: EdgeInsets.fromLTRB(24, topPadding + 18, 24, 110),
            children: [
              _HomeSearchBar(onTap: () => onOpenTab(2)),
              SizedBox(height: 150 - topPadding - 18 - 49 + 18),
              Text(
                '$greeting, $userName',
                style: const TextStyle(
                  color: Color(0xFF121F38),
                  fontSize: 20,
                  height: 1.3,
                ),
              ),
              const Text(
                'Your recommendations are ready.',
                style: TextStyle(
                  color: Color(0xFF596B8A),
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              _JourneyCard(onTap: () => onOpenTab(2)),
              const SizedBox(height: 18),
              const _SectionHeading(
                title: 'Current conditions',
                trailing: 'Kuala Lumpur • Now',
              ),
              const SizedBox(height: 10),
              const Row(
                children: [
                  Expanded(child: _WeatherCard()),
                  SizedBox(width: 14),
                  Expanded(child: _TrafficCard()),
                ],
              ),
              const SizedBox(height: 22),
              const Text(
                'Picked for your preferences',
                style: TextStyle(color: Color(0xFF121F38), fontSize: 16),
              ),
              const SizedBox(height: 2),
              const Text(
                'Culture • Food • Café hopping',
                style: TextStyle(color: Color(0xFF596B8A), fontSize: 10),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: _BatuCavesCard(onTap: () => onOpenTab(2)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: _MorePlacesCard(onTap: () => onOpenTab(2))),
                ],
              ),
              const SizedBox(height: 22),
              _GroupPreviewCard(onTap: () => onOpenTab(2)),
            ],
          ),
        ],
      ),
    );
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String _userName() {
    try {
      final fullName =
          Supabase.instance.client.auth.currentUser?.userMetadata?['full_name']
              ?.toString()
              .trim() ??
          '';
      if (fullName.isNotEmpty) return fullName.split(RegExp(r'\s+')).first;
    } catch (_) {
      // Supabase is intentionally unavailable in local/demo mode.
    }
    return 'Traveller';
  }
}

class _HomeSearchBar extends StatelessWidget {
  const _HomeSearchBar({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF7F3FB),
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: const SizedBox(
          height: 49,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Search Attractions ...',
                    style: TextStyle(color: Color(0xFF49454F), fontSize: 16),
                  ),
                ),
                Icon(Icons.search, color: Color(0xFF49454F), size: 25),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _JourneyCard extends StatelessWidget {
  const _JourneyCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF2E60C4),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: const SizedBox(
          height: 114,
          child: Padding(
            padding: EdgeInsets.fromLTRB(18, 15, 14, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'START A NEW JOURNEY',
                        style: TextStyle(
                          color: Color(0xFFE5F0FF),
                          fontSize: 10,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Where would you like to go?',
                        style: TextStyle(color: Colors.white, fontSize: 18),
                      ),
                      SizedBox(height: 5),
                      Text(
                        'Choose Solo Trip or join a nearby Group Trip.',
                        style: TextStyle(
                          color: Color(0xFFE8F2FF),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: Colors.white, size: 28),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.trailing});

  final String title;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(color: Color(0xFF121F38), fontSize: 16),
          ),
        ),
        Text(
          trailing,
          style: const TextStyle(color: Color(0xFF596B8A), fontSize: 10),
        ),
      ],
    );
  }
}

class _WeatherCard extends StatelessWidget {
  const _WeatherCard();

  @override
  Widget build(BuildContext context) {
    return const _ConditionCard(
      backgroundColor: Color(0xFFE8F5FF),
      icon: Icons.wb_sunny_outlined,
      iconColor: Color(0xFFFFA60D),
      value: '30°C',
      valueColor: Color(0xFF2E60C4),
      label: 'Sunny',
    );
  }
}

class _TrafficCard extends StatelessWidget {
  const _TrafficCard();

  @override
  Widget build(BuildContext context) {
    return const _ConditionCard(
      backgroundColor: Color(0xFFFFF2E3),
      icon: Icons.air,
      iconColor: Color(0xFFE07314),
      value: 'Moderate',
      valueColor: Color(0xFF121F38),
      label: '+4 min nearby',
    );
  }
}

class _ConditionCard extends StatelessWidget {
  const _ConditionCard({
    required this.backgroundColor,
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.valueColor,
    required this.label,
  });

  final Color backgroundColor;
  final IconData icon;
  final Color iconColor;
  final String value;
  final Color valueColor;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 76,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: TextStyle(color: valueColor, fontSize: 17)),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  style: const TextStyle(
                    color: Color(0xFF596B8A),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BatuCavesCard extends StatelessWidget {
  const _BatuCavesCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _OutlinedHomeCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 76,
            height: 80,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFF2B861),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(
              Icons.change_history,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Batu Caves',
                  style: TextStyle(color: Color(0xFF121F38), fontSize: 14),
                ),
                SizedBox(height: 5),
                Text(
                  'Matches Culture',
                  style: TextStyle(color: Color(0xFF2E60C4), fontSize: 10),
                ),
                SizedBox(height: 12),
                Text(
                  '18 min • 11.4 km',
                  style: TextStyle(color: Color(0xFF596B8A), fontSize: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MorePlacesCard extends StatelessWidget {
  const _MorePlacesCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _OutlinedHomeCard(
      onTap: onTap,
      backgroundColor: Colors.white,
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('+12', style: TextStyle(color: Color(0xFF2E60C4), fontSize: 23)),
          SizedBox(height: 2),
          Text(
            'places nearby',
            style: TextStyle(color: Color(0xFF596B8A), fontSize: 10),
          ),
          SizedBox(height: 5),
          Icon(Icons.arrow_forward, color: Color(0xFF2E60C4), size: 15),
        ],
      ),
    );
  }
}

class _OutlinedHomeCard extends StatelessWidget {
  const _OutlinedHomeCard({
    required this.onTap,
    required this.child,
    this.backgroundColor = const Color(0xFFF3F7FE),
  });

  final VoidCallback onTap;
  final Widget child;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: backgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: const BorderSide(color: Color(0xFFC7D6F2)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 100,
          child: Padding(padding: const EdgeInsets.all(9), child: child),
        ),
      ),
    );
  }
}

class _GroupPreviewCard extends StatelessWidget {
  const _GroupPreviewCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF5F0FF),
      borderRadius: BorderRadius.circular(15),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: const SizedBox(
          height: 82,
          child: Padding(
            padding: EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                SizedBox(
                  width: 42,
                  child: Icon(
                    Icons.groups_outlined,
                    color: Color(0xFF734FBF),
                    size: 28,
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Petaling Street Food Hunt',
                        style: TextStyle(
                          color: Color(0xFF121F38),
                          fontSize: 14,
                        ),
                      ),
                      SizedBox(height: 5),
                      Text(
                        '3/5 travellers • 0.8 km away',
                        style: TextStyle(
                          color: Color(0xFF596B8A),
                          fontSize: 10,
                        ),
                      ),
                      Spacer(),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          'View lobby  ›',
                          style: TextStyle(
                            color: Color(0xFF2E60C4),
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class StartTripHubPage extends StatelessWidget {
  const StartTripHubPage({super.key, required this.controller});

  final TravelGroupController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Start Trip')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'How would you like to travel?',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text(
            'Solo trips use personalised recommendations with weather and live traffic. Group trips open the shared Travel Group experience.',
          ),
          const SizedBox(height: 24),
          _TripModeCard(
            icon: Icons.person_pin_circle_outlined,
            title: 'Solo trip',
            subtitle:
                'Search places, receive recommendations, check weather and traffic, then build your route.',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                settings: const RouteSettings(name: '/start-trip/solo-map'),
                builder: (_) => const PlaceMapPage(),
              ),
            ),
          ),
          const SizedBox(height: 14),
          _TripModeCard(
            icon: Icons.groups_outlined,
            title: 'Group trip',
            subtitle:
                'Discover or create a travel group, vote on stops and manage a shared itinerary.',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => TravelGroupModulePage(controller: controller),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TripModeCard extends StatelessWidget {
  const _TripModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(radius: 25, child: Icon(icon)),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(subtitle),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class CommunityModulePage extends StatelessWidget {
  const CommunityModulePage({
    super.key,
    required this.controller,
    required this.onStartJourney,
  });

  final CommunityController controller;
  final StartJourneyCallback onStartJourney;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<String>>(
      valueListenable: currentTravelerPreferences,
      builder: (context, preferences, _) => CommunityFeedScreen(
        controller: controller,
        showBottomNavigation: false,
        preferredTagNames: preferences,
        includeDemoLikes: true,
        searchLeading: Image.asset(
          'assets/images/branding/ohmy_icon.png',
          fit: BoxFit.contain,
        ),
        integrationCallbacks: CommunityIntegrationCallbacks(
          onStartJourney: onStartJourney,
        ),
      ),
    );
  }
}

class TravelGroupModulePage extends StatelessWidget {
  const TravelGroupModulePage({super.key, required this.controller});

  final TravelGroupController controller;

  @override
  Widget build(BuildContext context) {
    return TravelGroupDiscoveryScreen(controller: controller);
  }
}

class _ReturnToGroupButton extends StatelessWidget {
  const _ReturnToGroupButton({required this.group, required this.onPressed});

  final TravelGroup group;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FilledButton.icon(
        key: const Key('return_to_group_button'),
        onPressed: onPressed,
        icon: const Badge(
          smallSize: 9,
          backgroundColor: Color(0xFF45C878),
          child: Icon(Icons.groups_rounded),
        ),
        label: Text(
          'Return to ${group.name}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        style: FilledButton.styleFrom(
          elevation: 7,
          maximumSize: const Size(240, 48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        ),
      ),
    );
  }
}

class ModuleSetupPage extends StatelessWidget {
  const ModuleSetupPage({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 56,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 10),
              Text(message, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}
