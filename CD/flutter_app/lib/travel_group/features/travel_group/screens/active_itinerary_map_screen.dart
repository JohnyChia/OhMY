import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../preference_recommender/features/routes/native_navigation_map.dart';
import '../../../core/theme/app_theme.dart';
import '../controllers/travel_group_controller.dart';
import '../models/travel_group_models.dart';
import '../services/live_trip_location_service.dart';
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

  ItineraryStop? get _currentStop {
    for (final stop in widget.controller.itinerary) {
      if (stop.status == StopStatus.current) return stop;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _locationService = widget.controller.createLiveTripLocationService();
    _memberSubscription = _locationService.watchLocations().listen(
      (members) {
        if (mounted) setState(() => _members = members);
      },
      onError: (Object error) {
        if (mounted) setState(() => _statusMessage = error.toString());
      },
    );
  }

  @override
  void dispose() {
    _memberSubscription?.cancel();
    unawaited(_locationService.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stop = _currentStop;
    if (stop == null || stop.latitude == null || stop.longitude == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Group journey')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.route_rounded, size: 56),
                const SizedBox(height: 12),
                const Text(
                  'There is no active destination yet.',
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
      body: Stack(
        children: [
          Positioned.fill(
            child: NativeNavigationMap(
              destinationName: stop.placeName,
              destinationLatitude: stop.latitude!,
              destinationLongitude: stop.longitude!,
              routeToken: '',
              trafficEnabled: true,
              onArrived: () => unawaited(_completeStop()),
              onLocation: (latitude, longitude) {
                _locationService.publishOwnLocation(
                  latitude: latitude,
                  longitude: longitude,
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
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
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
          ),
          if (navigationSimulationEnabled)
            Positioned(
              top: MediaQuery.paddingOf(context).top + 66,
              left: 16,
              child: const Chip(label: Text('TEST SIMULATION · 5x')),
            ),
          if (_statusMessage != null)
            Positioned(
              top: MediaQuery.paddingOf(context).top + 112,
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
            left: 12,
            right: 12,
            bottom: MediaQuery.paddingOf(context).bottom + 12,
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
        ],
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
        title: const Text('End the group journey?'),
        content: const Text(
          'This closes the live trip for everyone. This cannot be resumed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep travelling'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('End journey'),
          ),
        ],
      ),
    );
    if (shouldEnd != true || !mounted) return;
    try {
      await widget.controller.endTrip();
      if (mounted) Navigator.pop(context);
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
    return Card(
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
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
                Text(
                  timeText,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const Text('  ·  '),
                Text(distanceText),
                const Spacer(),
                if (isCreator)
                  TextButton(onPressed: onEnd, child: const Text('End trip')),
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
          ],
        ),
      ),
    );
  }
}
