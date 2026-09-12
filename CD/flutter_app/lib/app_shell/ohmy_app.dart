import 'dart:async';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:community_discovery/community_discovery.dart';

import '../ai_chatbot/main.dart' show ChatScreen;
import '../ai_chatbot/services/nova_action_bridge.dart';
import '../ai_chatbot/services/nova_owner_action_dispatcher.dart';
import '../ai_chatbot/services/nova_voice_controller.dart';
import '../ai_chatbot/widgets/nova_bottom_assistant.dart';
import '../preference_recommender/features/routes/native_navigation_map.dart';
import '../preference_recommender/pages/place_map_page.dart';
import '../travel_group/features/travel_group/controllers/travel_group_controller.dart';
import '../travel_group/features/travel_group/models/travel_group_models.dart';
import '../travel_group/features/travel_group/repositories/mock_travel_group_repository.dart';
import '../travel_group/features/travel_group/repositories/supabase_travel_group_repository.dart';
import '../travel_group/features/travel_group/screens/group_lobby_screen.dart';
import '../travel_group/features/travel_group/screens/travel_group_discovery_screen.dart';
import '../travel_group/features/travel_group/services/live_trip_location_service.dart';
import '../travel_group/features/travel_group/services/supabase_live_trip_location_service.dart';
import '../user_management/screens/auth/auth_gate.dart';
import '../user_management/screens/profile_screen.dart';
import '../user_management/services/traveler_profile_service.dart';
import '../shared/widgets/wau_loading_indicator.dart';
import '../shared/widgets/ohmy_snack_bar.dart';
import 'ohmy_bottom_navigation_bar.dart';
import 'personalized_home_page.dart';

// Explicit testing switch only; never grants verified status in Supabase.
const _skipTravellerVerification =
    kDebugMode &&
    bool.fromEnvironment(
      'BYPASS_TRAVEL_GROUP_VERIFICATION',
      defaultValue: false,
    );

class OhMyApp extends StatelessWidget {
  const OhMyApp({super.key, required this.supabaseEnabled});

  final bool supabaseEnabled;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OhMY',
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
  DateTime? _lastHomeBackPress;
  final List<NovaOwnerActionRegistration> _novaRegistrations = [];

  @override
  void initState() {
    super.initState();
    for (final target in ['trip', 'map', 'community', 'profile']) {
      _novaRegistrations.add(
        NovaOwnerActionDispatcher.register(
          target: target,
          handler: _handleNovaAction,
        ),
      );
    }
    final authUser = widget.supabaseEnabled
        ? Supabase.instance.client.auth.currentUser
        : null;
    final travelUser = authUser == null ? null : _prototypeUser(authUser);
    _travelGroupController = TravelGroupController(
      repository: widget.supabaseEnabled
          ? SupabaseTravelGroupRepository(Supabase.instance.client)
          : MockTravelGroupRepository.seeded(),
      currentUser: travelUser,
      allowDemoVerification: !widget.supabaseEnabled,
      liveTripLocationServiceFactory: widget.supabaseEnabled
          ? createSupabaseLiveTripLocationService
          : createMockLiveTripLocationService,
    )..addListener(_onTravelGroupChanged);
    if (widget.supabaseEnabled) {
      unawaited(_travelGroupController.restoreOngoingCreatedGroup());
    }
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
      (context) => _communityController == null
          ? HomeModulePage(
              onOpenTab: _selectTab,
              onOpenSoloMap: () => _openSoloMap(null),
            )
          : PersonalizedHomePage(
              communityController: _communityController!,
              onOpenSoloMap: _openSoloMap,
              onOpenCommunity: () => _selectTab(3),
              onOpenPost: _openCommunityPost,
            ),
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

  void _openSoloMap(Map<String, dynamic>? recommendation) {
    if (_travelGroupController.ongoingMemberGroup != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const OhMySnackBar(
          content: Text(
            'Leave or finish your Travel Group before starting a solo trip.',
          ),
        ),
      );
      _returnToGroup();
      return;
    }
    if (_selectedIndex != 2) setState(() => _selectedIndex = 2);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _navigatorKeys[2].currentState?.push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: '/start-trip/solo-map'),
          builder: (_) => PlaceMapPage(
            autofocusSearch: recommendation == null,
            initialRecommendation: recommendation,
          ),
        ),
      );
    });
  }

  void _openCommunityPost(CommunityPost post) {
    if (_selectedIndex != 3) setState(() => _selectedIndex = 3);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navigator = _navigatorKeys[3].currentState;
      navigator?.popUntil((route) => route.isFirst);
      navigator?.push(
        MaterialPageRoute<void>(
          settings: RouteSettings(name: '/community/post/${post.id}'),
          builder: (_) => PostDetailScreen(
            postId: post.id,
            controller: _communityController!,
          ),
        ),
      );
    });
  }

  @override
  void dispose() {
    for (final registration in _novaRegistrations) {
      registration.dispose();
    }
    _authSubscription?.cancel();
    _travelGroupController
      ..removeListener(_onTravelGroupChanged)
      ..dispose();
    _communityController?.dispose();
    super.dispose();
  }

  Future<NovaOwnerActionResult> _handleNovaAction(NovaAction action) async {
    if (!mounted) {
      return NovaOwnerActionResult(
        action: action,
        status: NovaOwnerActionStatus.unavailable,
        message: 'App navigation is unavailable.',
      );
    }
    if (action.target == 'trip' || action.target == 'map') {
      await _travelGroupController.restoreOngoingCreatedGroup();
      if (_travelGroupController.ongoingMemberGroup != null) {
        return NovaOwnerActionResult(
          action: action,
          status: NovaOwnerActionStatus.rejected,
          message:
              'Return to your travel group before starting another journey.',
          errorCode: 'ACTIVE_TRAVEL_GROUP',
        );
      }
      final query = action.parameters['destination']?.toString().trim() ?? '';
      if (_selectedIndex != 2) setState(() => _selectedIndex = 2);
      await Future<void>.delayed(Duration.zero);
      if (!mounted || _navigatorKeys[2].currentState == null) {
        return NovaOwnerActionResult(
          action: action,
          status: NovaOwnerActionStatus.unavailable,
          message: 'Map navigation is not ready.',
        );
      }
      unawaited(
        _navigatorKeys[2].currentState!.push<void>(
          MaterialPageRoute(
            settings: const RouteSettings(name: '/start-trip/solo-map'),
            builder: (_) => PlaceMapPage(initialSearchQuery: query),
          ),
        ),
      );
      return NovaOwnerActionResult(
        action: action,
        status: NovaOwnerActionStatus.executed,
        message:
            'Destination search opened. Select the place to start navigation.',
      );
    }
    _selectTab(action.target == 'community' ? 3 : 4);
    return NovaOwnerActionResult(
      action: action,
      status: NovaOwnerActionStatus.executed,
      message: '${action.target} opened.',
    );
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
          _skipTravellerVerification || appMetadata['is_verified'] == true,
    );
  }

  void _onTravelGroupChanged() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  void _returnToGroup() async {
    final group = _travelGroupController.ongoingMemberGroup;
    if (group == null) return;
    if (_selectedIndex != 2) setState(() => _selectedIndex = 2);
    await _travelGroupController.openGroup(group.id);
    if (!mounted) return;
    final navigator = _navigatorKeys[2].currentState;
    navigator?.popUntil((route) => route.isFirst);
    unawaited(
      navigator?.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => GroupLobbyScreen(controller: _travelGroupController),
        ),
      ),
    );
  }

  void _selectTab(int index) {
    _lastHomeBackPress = null;
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

  Future<void> _handleBack(BuildContext context) async {
    final navigator = _navigatorKeys[_selectedIndex].currentState;
    if (navigator != null && await navigator.maybePop()) return;
    if (!context.mounted) return;
    if (_selectedIndex != 0) {
      _selectTab(0);
      _lastHomeBackPress = null;
      return;
    }
    final now = DateTime.now();
    if (_lastHomeBackPress == null ||
        now.difference(_lastHomeBackPress!) > const Duration(seconds: 2)) {
      _lastHomeBackPress = now;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const OhMySnackBar(
            duration: Duration(seconds: 2),
            content: Text('Press back again to exit'),
          ),
        );
      return;
    }
    await SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _handleBack(context);
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
            if (_selectedIndex != 1)
              Positioned(
                left: 20,
                right: 20,
                top: MediaQuery.paddingOf(context).top + 6,
                child: ValueListenableBuilder<NovaVoiceState>(
                  valueListenable: NovaVoiceController.state,
                  builder: (_, state, _) => state.phase == NovaVoicePhase.idle
                      ? const SizedBox.shrink()
                      : NovaBottomAssistant(
                          state: state,
                          onDismiss: NovaVoiceController.reset,
                          compact: true,
                        ),
                ),
              ),
            if (_selectedIndex != 2 &&
                _travelGroupController.ongoingMemberGroup != null)
              Positioned(
                right: 14,
                bottom: 12,
                child: _ReturnToGroupButton(
                  group: _travelGroupController.ongoingMemberGroup!,
                  onPressed: _returnToGroup,
                ),
              ),
          ],
        ),
        bottomNavigationBar: ValueListenableBuilder<bool>(
          valueListenable: navigationExperienceActive,
          builder: (context, navigationActive, _) => navigationActive
              ? const SizedBox.shrink()
              : SafeArea(
                  top: false,
                  child: OhMyBottomNavigationBar(
                    selectedIndex: _selectedIndex,
                    onSelected: _selectTab,
                  ),
                ),
        ),
      ),
    );
  }
}

class HomeModulePage extends StatelessWidget {
  const HomeModulePage({
    super.key,
    required this.onOpenTab,
    required this.onOpenSoloMap,
  });

  final ValueChanged<int> onOpenTab;
  final VoidCallback onOpenSoloMap;

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.paddingOf(context).top;
    return Scaffold(
      backgroundColor: const Color(0xFFF9FBFE),
      body: ListView(
        padding: EdgeInsets.fromLTRB(0, topPadding + 10, 0, 110),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(
                  width: 58,
                  height: 58,
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3266CC),
                    borderRadius: BorderRadius.circular(17),
                    border: Border.all(
                      color: const Color(0xFF1685FF),
                      width: 2,
                    ),
                  ),
                  child: Image.asset(
                    'assets/images/branding/ohmy_icon.png',
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: _HomeSearchBar(onTap: onOpenSoloMap)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _HomeDiscoveryContent(onOpenSoloMap: onOpenSoloMap),
          const SizedBox(height: 24),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Discover posts by other travellers',
              style: TextStyle(
                color: Color(0xFF14213D),
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _GroupPreviewCard(onTap: () => onOpenTab(3)),
          ),
        ],
      ),
    );
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

class _HomeDiscoveryContent extends StatefulWidget {
  const _HomeDiscoveryContent({required this.onOpenSoloMap});

  final VoidCallback onOpenSoloMap;

  @override
  State<_HomeDiscoveryContent> createState() => _HomeDiscoveryContentState();
}

class _HomeDiscoveryContentState extends State<_HomeDiscoveryContent> {
  static const _backend = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'http://127.0.0.1:3000',
  );
  List<Map<String, dynamic>> places = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      final location = await Geolocator.getCurrentPosition();
      final preferences =
          (await TravelerProfileService().fetchCurrentProfile())
              ?.favoriteCategories ??
          const <String>[];
      if (preferences.isEmpty) return;
      final response = await http
          .post(
            Uri.parse('$_backend/api/recommendations/nearby-tagged'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'latitude': location.latitude,
              'longitude': location.longitude,
              'mode': 'preferences',
              'preferences': preferences,
            }),
          )
          .timeout(const Duration(seconds: 60));
      if (response.statusCode < 200 || response.statusCode >= 300) return;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final discovered =
          List<Map<String, dynamic>>.from(
            data['matchedPlaces'] ?? const [],
          ).where((item) {
            final place = Map<String, dynamic>.from(
              item['place'] as Map? ?? {},
            );
            final description = place['description']?.toString().trim() ?? '';
            final distance = place['routeDistanceKm'] ?? place['distanceKm'];
            return description.isNotEmpty && distance is num && distance <= 10;
          }).toList();
      if (mounted) setState(() => places = discovered.take(8).toList());
    } catch (_) {
      // The homepage remains usable when location or recommendations are down.
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String _name(Map<String, dynamic> item) =>
      item['place']?['displayName']?['text']?.toString() ?? 'Local heritage';

  String _description(Map<String, dynamic> item) =>
      item['place']?['description']?.toString() ?? '';

  String? _photo(Map<String, dynamic> item) {
    final name = item['place']?['photo']?['name']?.toString();
    return name == null
        ? null
        : '$_backend/api/places/photo?name=${Uri.encodeQueryComponent(name)}';
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const _HomeDiscoverySkeleton(loading: true);
    }
    if (places.isEmpty) {
      return _HomeDiscoverySkeleton(
        loading: false,
        onTap: widget.onOpenSoloMap,
      );
    }
    final hero = places.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: _HomeHeroPlace(
            name: _name(hero),
            description: _description(hero),
            photo: _photo(hero),
            onTap: widget.onOpenSoloMap,
          ),
        ),
        const SizedBox(height: 20),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Places You May Like',
                style: TextStyle(
                  color: Color(0xFF14213D),
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 5),
              Text(
                'Culture • Food • Café hopping',
                style: TextStyle(color: Color(0xFF596B8A), fontSize: 10),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 148,
          child: Padding(
            padding: const EdgeInsets.only(left: 20),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: places.length,
              separatorBuilder: (_, index) => const SizedBox(width: 10),
              itemBuilder: (_, index) => _NearbyPlaceTile(
                name: _name(places[index]),
                photo: _photo(places[index]),
                onTap: widget.onOpenSoloMap,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _HomeHeroPlace extends StatelessWidget {
  const _HomeHeroPlace({
    required this.name,
    required this.description,
    required this.photo,
    required this.onTap,
  });
  final String name;
  final String description;
  final String? photo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFF1D4F9F),
    borderRadius: BorderRadius.circular(24),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 245,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (photo != null) Image.network(photo!, fit: BoxFit.cover),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xF21B4387)],
                  stops: [.32, 1],
                ),
              ),
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 20,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 25,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    description,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, height: 1.35),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _NearbyPlaceTile extends StatelessWidget {
  const _NearbyPlaceTile({
    required this.name,
    required this.photo,
    required this.onTap,
  });
  final String name;
  final String? photo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 146,
    child: Material(
      color: const Color(0xFFEAF1FC),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SizedBox.expand(
                child: photo == null
                    ? const Icon(
                        Icons.museum_outlined,
                        color: Color(0xFF3266CC),
                      )
                    : Image.network(photo!, fit: BoxFit.cover),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _HomeDiscoverySkeleton extends StatelessWidget {
  const _HomeDiscoverySkeleton({required this.loading, this.onTap});
  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Material(
          color: const Color(0xFFF4B85F),
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              height: 245,
              child: Center(
                child: loading
                    ? const WauLoadingIndicator(size: 52)
                    : const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Explore heritage and cultural places near you',
                          style: TextStyle(
                            color: Color(0xFF14213D),
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 16),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Places You May Like',
              style: TextStyle(
                color: Color(0xFF14213D),
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 5),
            Text(
              'Culture • Food • Café hopping',
              style: TextStyle(color: Color(0xFF596B8A), fontSize: 10),
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      SizedBox(
        height: 138,
        child: ListView.separated(
          padding: const EdgeInsets.only(left: 20, right: 20),
          scrollDirection: Axis.horizontal,
          itemCount: 3,
          separatorBuilder: (_, index) => const SizedBox(width: 10),
          itemBuilder: (_, index) => Container(
            width: 146,
            decoration: BoxDecoration(
              color: const Color(0xFFF3F7FE),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFC7D6F2)),
            ),
          ),
        ),
      ),
    ],
  );
}

// Legacy dashboard components retained for teammate branch compatibility.
// ignore: unused_element
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

// ignore: unused_element
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

// ignore: unused_element
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

// ignore: unused_element
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

// ignore: unused_element
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

// ignore: unused_element
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
          height: 138,
          child: Padding(
            padding: EdgeInsets.fromLTRB(18, 18, 18, 14),
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
                        'Discover from other travellers',
                        style: TextStyle(
                          color: Color(0xFF121F38),
                          fontSize: 14,
                        ),
                      ),
                      SizedBox(height: 5),
                      Text(
                        'Heritage stories, local finds and shared journeys',
                        style: TextStyle(
                          color: Color(0xFF596B8A),
                          fontSize: 10,
                        ),
                      ),
                      Spacer(),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          'View posts  ›',
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
    final topPadding = MediaQuery.paddingOf(context).top;
    return Scaffold(
      backgroundColor: const Color(0xfff6f9fd),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _StartTripBackground(),
          SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(22, topPadding + 22, 22, 34),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 74,
                  child: Stack(
                    children: [
                      const Positioned(
                        left: 0,
                        top: 0,
                        child: Text(
                          'Start Trip',
                          style: TextStyle(
                            color: Color(0xff121a3a),
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Positioned(
                        right: 0,
                        top: 0,
                        child: IgnorePointer(
                          child: Image.asset(
                            'assets/images/start_trip_selection/startTripSelectionTopRight.png',
                            width: 74,
                            height: 74,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'How would you like\nto travel?',
                  style: TextStyle(
                    color: Color(0xff10183b),
                    fontSize: 34,
                    height: 1.06,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Explore Malaysia your way.\nChoose a travel style to get started.',
                  style: TextStyle(
                    color: Color(0xff6f758b),
                    fontSize: 17,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 42),
                _TripModeCard(
                  imageAsset:
                      'assets/images/start_trip_selection/startTripSelectionSolo.png',
                  accent: const Color(0xffe7f2ff),
                  title: 'Solo trip',
                  subtitle:
                      'Search places, receive recommendations, check weather and traffic, then build your route.',
                  onTap: () => _openSoloTrip(context),
                ),
                const SizedBox(height: 18),
                _TripModeCard(
                  imageAsset:
                      'assets/images/start_trip_selection/startTripSelectionGroup.png',
                  accent: const Color(0xffffeee1),
                  title: 'Group trip',
                  subtitle:
                      'Discover or create a travel group, vote on stops and manage a shared itinerary.',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          TravelGroupModulePage(controller: controller),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openSoloTrip(BuildContext context) async {
    final ownedGroup = controller.ongoingMemberGroup;
    if (ownedGroup != null) {
      final openGroup = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Travel Group already active'),
          content: Text(
            'You are in ${ownedGroup.name}. Leave or finish that Travel Group before starting a solo trip.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Not now'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.groups_rounded),
              label: const Text('Open Travel Group'),
            ),
          ],
        ),
      );
      if (openGroup == true && context.mounted) {
        await controller.openGroup(ownedGroup.id);
        if (!context.mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => GroupLobbyScreen(controller: controller),
          ),
        );
      }
      return;
    }
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/start-trip/solo-map'),
        builder: (_) => const PlaceMapPage(),
      ),
    );
  }
}

class _StartTripBackground extends StatelessWidget {
  const _StartTripBackground();

  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: Opacity(
      opacity: .30,
      child: ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: 1.5, sigmaY: 1.5),
        child: ColorFiltered(
          // 75% saturation: the artwork is desaturated by 25%.
          colorFilter: const ColorFilter.matrix(<double>[
            .803,
            .179,
            .018,
            0,
            0,
            .053,
            .929,
            .018,
            0,
            0,
            .053,
            .179,
            .768,
            0,
            0,
            0,
            0,
            0,
            1,
            0,
          ]),
          child: Image.asset(
            'assets/images/start_trip_selection/startTripSelectionBg.png',
            fit: BoxFit.cover,
            alignment: Alignment.bottomCenter,
          ),
        ),
      ),
    ),
  );
}

class _TripModeCard extends StatelessWidget {
  const _TripModeCard({
    required this.imageAsset,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String imageAsset;
  final Color accent;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 5,
      shadowColor: Colors.black.withValues(alpha: .16),
      color: Colors.white.withValues(alpha: .94),
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 14, 18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 112,
                height: 112,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
                child: Image.asset(imageAsset, fit: BoxFit.contain),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: const Color(0xff10183b),
                        fontSize: 25,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xff626a83),
                        fontSize: 14,
                        height: 1.32,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 7),
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: .7),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xff10183b),
                  size: 29,
                ),
              ),
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
