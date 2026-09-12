import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../preference_recommender/features/routes/native_navigation_map.dart';
import '../../../core/theme/app_theme.dart';
import '../controllers/travel_group_controller.dart';
import '../models/travel_group_models.dart';
import '../services/live_trip_location_service.dart';
import '../services/member_location_clusters.dart';
import '../widgets/travel_group_widgets.dart';

class ActiveItineraryMapScreen extends StatefulWidget {
  const ActiveItineraryMapScreen({super.key, required this.controller});

  final TravelGroupController controller;

  @override
  State<ActiveItineraryMapScreen> createState() =>
      _ActiveItineraryMapScreenState();
}

class _ActiveItineraryMapScreenState extends State<ActiveItineraryMapScreen> {
  late final LiveTripLocationService _locationService;
  StreamSubscription<List<LiveMemberLocation>>? _memberSubscription;
  List<LiveMemberLocation> _members = const [];
  double? _remainingDistanceMeters;
  double? _remainingTimeSeconds;
  String? _statusMessage;
  bool _completing = false;
  bool _mountNavigationMap = false;
  final _navigationKey = GlobalKey<NativeNavigationMapState>();
  Timer? _workspaceTimer;
  bool _refreshing = false;

  void _sharedStateChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _refreshSharedState() async {
    if (_refreshing || !mounted) return;
    _refreshing = true;
    try {
      await widget.controller.refreshWorkspace();
    } catch (error) {
      if (mounted) {
        setState(() => _statusMessage = 'Could not sync the group: $error');
      }
    } finally {
      _refreshing = false;
    }
  }

  List<NavigationMemberPin> get _memberPins {
    final clusters = clusterMemberLocations(_members);
    return clusters
        .map(
          (c) => NavigationMemberPin(
            latitude: c.first.coordinate.latitude,
            longitude: c.first.coordinate.longitude,
            names: c.map((m) => m.displayName).toList(),
          ),
        )
        .toList();
  }

  ItineraryStop? get _currentStop {
    final sharedStopId = widget.controller.activeSession?.currentStopId;
    if (sharedStopId != null) {
      return widget.controller.itinerary
          .where((s) => s.id == sharedStopId && s.status == StopStatus.current)
          .firstOrNull;
    }
    for (final stop in widget.controller.itinerary) {
      if (stop.status == StopStatus.current) return stop;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_sharedStateChanged);
    _workspaceTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => unawaited(_refreshSharedState()),
    );
    _locationService = widget.controller.createLiveTripLocationService();
    _memberSubscription = _locationService.watchLocations().listen(
      (members) {
        if (mounted) setState(() => _members = members);
      },
      onError: (Object error) {
        if (mounted) setState(() => _statusMessage = error.toString());
      },
    );
    // Android platform views can retain the small bounds used by a route's
    // entrance transition on some Samsung devices. Mount the Navigation SDK
    // view only after this full-screen route has completed its first layout.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _mountNavigationMap = true);
    });
  }

  @override
  void dispose() {
    _workspaceTimer?.cancel();
    widget.controller.removeListener(_sharedStateChanged);
    _memberSubscription?.cancel();
    unawaited(_locationService.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stop = _currentStop;
    final group = widget.controller.activeGroup;
    final visited = widget.controller.itinerary
        .where((s) => s.status == StopStatus.completed)
        .lastOrNull;
    if (group?.status == GroupStatus.completed) {
      return Scaffold(
        appBar: AppBar(title: const Text('Travel Group ended')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle_outline, size: 56),
                const SizedBox(height: 16),
                Text(
                  widget.controller.isCreator
                      ? 'Your Travel Group session has ended.'
                      : '${group!.creatorName} ended the Travel Group session.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text('Your trip history has been saved.'),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Return to group'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (stop == null || stop.latitude == null || stop.longitude == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Travel Group')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.route_rounded, size: 56),
                const SizedBox(height: 12),
                const Text(
                  'The group is spending time at this stop. The creator will start navigation to the next itinerary destination when everyone is ready.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.groups_rounded),
                  label: const Text('Return to group lobby'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: SizedBox.expand(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_mountNavigationMap)
              SafeArea(
                bottom: false,
                child: NativeNavigationMap(
                  key: _navigationKey,
                  memberPins: _memberPins,
                  simulationOriginLatitude:
                      visited?.latitude ?? group?.meetupLatitude,
                  simulationOriginLongitude:
                      visited?.longitude ?? group?.meetupLongitude,
                  destinationName: stop.placeName,
                  destinationLatitude: stop.latitude!,
                  destinationLongitude: stop.longitude!,
                  routeToken: '',
                  trafficEnabled: true,
                  voiceGuidanceEnabled: true,
                  vibrationEnabled: true,
                  onArrived: () {
                    if (mounted) {
                      setState(
                        () => _statusMessage =
                            'Destination reached. The creator can confirm arrival when everyone is ready.',
                      );
                    }
                  },
                  onLocation: (latitude, longitude) {
                    final coordinate = widget.controller.effectiveLocation(
                      latitude,
                      longitude,
                    );
                    unawaited(
                      _locationService
                          .publishOwnLocation(
                            latitude: coordinate.latitude,
                            longitude: coordinate.longitude,
                          )
                          .catchError((Object error) {
                            if (mounted) {
                              setState(() {
                                _statusMessage =
                                    'Live location sharing failed: $error';
                              });
                            }
                          }),
                    );
                  },
                  onProgress: (distanceMeters, timeSeconds, _) {
                    if (!mounted) return;
                    setState(() {
                      _remainingDistanceMeters = distanceMeters;
                      _remainingTimeSeconds = timeSeconds;
                    });
                  },
                  onStatus: (message) {
                    if (mounted) setState(() => _statusMessage = message);
                  },
                ),
              )
            else
              const ColoredBox(
                color: Color(0xffeef3fb),
                child: Center(child: CircularProgressIndicator()),
              ),
            Positioned(
              top: MediaQuery.paddingOf(context).top + 150,
              left: 12,
              right: 12,
              child: Row(
                children: [
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.primary,
                      elevation: 5,
                    ),
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.groups_rounded),
                    label: const Text('Group lobby'),
                  ),
                  const Spacer(),
                  ActionChip(
                    avatar: const Icon(Icons.location_on_rounded, size: 18),
                    label: Text('${_members.length} live'),
                    onPressed: _showMembers,
                  ),
                ],
              ),
            ),
            if (navigationSimulationEnabled)
              Positioned(
                top: MediaQuery.paddingOf(context).top + 214,
                left: 16,
                child: const Chip(label: Text('TEST SIMULATION · 5x')),
              ),
            if (_statusMessage != null)
              Positioned(
                top: MediaQuery.paddingOf(context).top + 264,
                left: 24,
                right: 24,
                child: Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      _statusMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                ),
              ),
            Positioned(
              right: 16,
              bottom: MediaQuery.paddingOf(context).bottom + 220,
              child: FloatingActionButton.small(
                heroTag: 'group-navigation-recenter',
                tooltip: 'Recenter on my location',
                onPressed: () =>
                    unawaited(_navigationKey.currentState?.recenter()),
                child: const Icon(Icons.my_location),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Material(
                elevation: 14,
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                    child: _JourneyCard(
                      stop: stop,
                      distanceText: _formatDistance(_remainingDistanceMeters),
                      timeText: _formatTime(_remainingTimeSeconds),
                      completing: _completing,
                      isCreator: widget.controller.isCreator,
                      onArrived: _completeStop,
                      onEnd: _confirmEndTrip,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDistance(double? meters) {
    if (meters == null) return '-- km';
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  String _formatTime(double? seconds) {
    if (seconds == null) return '-- min';
    return '${(seconds / 60).ceil()} min';
  }

  Future<void> _completeStop() async {
    final stop = _currentStop;
    if (stop == null || _completing || !widget.controller.isCreator) return;
    setState(() => _completing = true);
    try {
      await widget.controller.completeStop(stop);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Destination reached. Choose the group\'s next stop.'),
        ),
      );
    } on TravelGroupException catch (error) {
      if (mounted) showTravelGroupMessage(context, error.message, error: true);
    } finally {
      if (mounted) setState(() => _completing = false);
    }
  }

  Future<void> _confirmEndTrip() async {
    final shouldEnd = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End this Travel Group?'),
        content: const Text(
          'This ends the trip for everyone and saves it to each traveller\'s history. It cannot be resumed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep travelling'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('End Travel Group'),
          ),
        ],
      ),
    );
    if (shouldEnd != true || !mounted) return;
    try {
      await widget.controller.endTrip();
      if (mounted) {
        showTravelGroupMessage(context, 'Travel Group saved to your history.');
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } on TravelGroupException catch (error) {
      if (mounted) showTravelGroupMessage(context, error.message, error: true);
    }
  }

  void _showMembers() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            const Text(
              'Live travellers',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            if (_members.isEmpty)
              const ListTile(
                leading: Icon(Icons.location_off_rounded),
                title: Text('Waiting for shared locations'),
              ),
            for (final member in _members)
              ListTile(
                leading: Icon(
                  member.isFresh
                      ? Icons.location_on_rounded
                      : Icons.location_off_rounded,
                  color: member.isFresh ? AppColors.success : Colors.grey,
                ),
                title: Text(member.displayName),
                subtitle: Text(
                  member.isFresh
                      ? (member.isCurrentUser ? 'You · live' : 'Live now')
                      : 'Location is out of date',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _JourneyCard extends StatelessWidget {
  const _JourneyCard({
    required this.stop,
    required this.distanceText,
    required this.timeText,
    required this.completing,
    required this.isCreator,
    required this.onArrived,
    required this.onEnd,
  });

  final ItineraryStop stop;
  final String distanceText;
  final String timeText;
  final bool completing;
  final bool isCreator;
  final VoidCallback onArrived;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'NAVIGATING TOGETHER',
          style: TextStyle(
            color: AppColors.primary,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: .7,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          stop.placeName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(timeText, style: const TextStyle(fontWeight: FontWeight.w700)),
            const Text('  ·  '),
            Text(distanceText),
            const Spacer(),
          ],
        ),
        if (isCreator)
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: completing ? null : onArrived,
              icon: const Icon(Icons.flag_rounded),
              label: Text(completing ? 'Updating...' : 'We\'ve arrived'),
            ),
          ),
        if (isCreator) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              key: const Key('end_travel_group_button'),
              onPressed: completing ? null : onEnd,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFB3261E),
                side: const BorderSide(color: Color(0xFFB3261E)),
              ),
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text('End Travel Group'),
            ),
          ),
        ],
      ],
    );
  }
}
