import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../ai_chatbot/main.dart' show ChatScreen;
import '../community_discovery/data/community_repository.dart';
import '../community_discovery/data/demo_community_repository.dart';
import '../community_discovery/data/supabase_community_repository.dart';
import '../community_discovery/state/community_controller.dart';
import '../community_discovery/ui/community_feed_screen.dart';
import '../preference_recommender/pages/place_map_page.dart';
import '../travel_group/features/travel_group/controllers/travel_group_controller.dart';
import '../travel_group/features/travel_group/repositories/mock_travel_group_repository.dart';
import '../travel_group/features/travel_group/screens/travel_group_discovery_screen.dart';
import '../user_management/screens/auth/auth_gate.dart';
import '../user_management/screens/profile_screen.dart';

class OhMyApp extends StatelessWidget {
  const OhMyApp({super.key, required this.supabaseEnabled});

  final bool supabaseEnabled;

  @override
  Widget build(BuildContext context) {
    final shell = OhMyShell(supabaseEnabled: supabaseEnabled);
    return MaterialApp(
      title: 'ohMY',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3266CC)),
        scaffoldBackgroundColor: const Color(0xFFF8FBFF),
        navigationBarTheme: const NavigationBarThemeData(
          height: 72,
          backgroundColor: Colors.white,
          indicatorColor: Color(0xFFDDE8FF),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        ),
      ),
      home: supabaseEnabled ? AuthGate(authenticatedHome: shell) : shell,
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

  late final List<WidgetBuilder> _rootBuilders = [
    (context) => HomeModulePage(onOpenTab: _selectTab),
    (context) => const ChatScreen(showBottomNavigation: false),
    (context) => const StartTripHubPage(),
    (context) => CommunityModulePage(useSupabase: widget.supabaseEnabled),
    (context) => widget.supabaseEnabled
        ? const ProfileScreen(showBottomNavigation: false)
        : const ModuleSetupPage(
            icon: Icons.person_outline,
            title: 'Profile setup required',
            message:
                'Start Flutter with SUPABASE_URL and SUPABASE_ANON_KEY to use authentication and profile features.',
          ),
  ];

  void _selectTab(int index) {
    if (_selectedIndex == index) {
      _navigatorKeys[index].currentState?.popUntil((route) => route.isFirst);
      return;
    }
    setState(() => _selectedIndex = index);
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
        body: IndexedStack(
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
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: _selectTab,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.smart_toy_outlined),
              selectedIcon: Icon(Icons.smart_toy),
              label: 'AI Chat',
            ),
            NavigationDestination(
              icon: Icon(Icons.luggage_outlined),
              selectedIcon: Icon(Icons.luggage),
              label: 'Start Trip',
            ),
            NavigationDestination(
              icon: Icon(Icons.explore_outlined),
              selectedIcon: Icon(Icons.explore),
              label: 'Community',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Profile',
            ),
          ],
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
    return Scaffold(
      appBar: AppBar(title: const Text('ohMY')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Explore Malaysia your way',
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text(
            'Plan a solo or group journey, ask the travel assistant, or discover trips shared by the community.',
          ),
          const SizedBox(height: 24),
          _HomeActionCard(
            icon: Icons.luggage_outlined,
            title: 'Start a trip',
            subtitle: 'Choose a solo recommendation or group travel.',
            onTap: () => onOpenTab(2),
          ),
          _HomeActionCard(
            icon: Icons.smart_toy_outlined,
            title: 'Ask AI Chat',
            subtitle: 'Plan conversationally using text or voice.',
            onTap: () => onOpenTab(1),
          ),
          _HomeActionCard(
            icon: Icons.explore_outlined,
            title: 'Community Discovery',
            subtitle: 'Browse experiences shared by other travellers.',
            onTap: () => onOpenTab(3),
          ),
        ],
      ),
    );
  }
}

class _HomeActionCard extends StatelessWidget {
  const _HomeActionCard({
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
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: CircleAvatar(child: Icon(icon)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(subtitle),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class StartTripHubPage extends StatelessWidget {
  const StartTripHubPage({super.key});

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
              MaterialPageRoute<void>(builder: (_) => const PlaceMapPage()),
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
                builder: (_) => const TravelGroupModulePage(),
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

class CommunityModulePage extends StatefulWidget {
  const CommunityModulePage({super.key, required this.useSupabase});

  final bool useSupabase;

  @override
  State<CommunityModulePage> createState() => _CommunityModulePageState();
}

class _CommunityModulePageState extends State<CommunityModulePage> {
  late final CommunityController _controller;

  @override
  void initState() {
    super.initState();
    final CommunityRepository repository = widget.useSupabase
        ? SupabaseCommunityRepository(Supabase.instance.client)
        : DemoCommunityRepository();
    _controller = CommunityController(repository);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CommunityFeedScreen(
      controller: _controller,
      showBottomNavigation: false,
    );
  }
}

class TravelGroupModulePage extends StatefulWidget {
  const TravelGroupModulePage({super.key});

  @override
  State<TravelGroupModulePage> createState() => _TravelGroupModulePageState();
}

class _TravelGroupModulePageState extends State<TravelGroupModulePage> {
  late final TravelGroupController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TravelGroupController(
      repository: MockTravelGroupRepository.seeded(),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TravelGroupDiscoveryScreen(controller: _controller);
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
