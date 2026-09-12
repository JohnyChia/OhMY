import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../../../../preference_recommender/features/routes/navigation_sensor.dart';
import '../../../core/theme/app_theme.dart';
import '../controllers/travel_group_controller.dart';
import '../models/travel_group_models.dart';
import '../services/live_trip_location_service.dart';
import '../widgets/travel_group_scaffold.dart';
import '../widgets/travel_group_widgets.dart';
import 'itinerary_board.dart';
import 'active_itinerary_map_screen.dart';
import 'group_member_profile_screen.dart';
import 'meetup_picker_screen.dart';
import 'suggestion_board.dart';

class GroupLobbyScreen extends StatefulWidget {
  const GroupLobbyScreen({
    super.key,
    required this.controller,
    this.initialMessage,
  });

  final TravelGroupController controller;
  final String? initialMessage;

  @override
  State<GroupLobbyScreen> createState() => _GroupLobbyScreenState();
}

class _GroupLobbyScreenState extends State<GroupLobbyScreen> {
  int _tabIndex = 0;
  LiveTripLocationService? _locationService;
  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<List<LiveMemberLocation>>? _memberLocationSubscription;
  bool _startingLocationSharing = false;
  String? _locationSharingError;
  List<LiveMemberLocation> _liveMembers = const [];
  Timer? _workspaceTimer;
  Timer? _locationHeartbeat;
  bool _refreshingWorkspace = false;
  String? _openedSharedStopId;
  bool _sharedNavigationOpen = false;

  void _followCreatorNavigation() {
    final session = controller.activeSession;
    if (_sharedNavigationOpen) {
      _openedSharedStopId = session?.currentStopId;
      return;
    }
    if (controller.isCreator ||
        !controller.isMember ||
        _sharedNavigationOpen ||
        controller.activeGroup?.tripPhase != GroupTripPhase.navigating ||
        session?.currentStopId == null ||
        session!.currentStopId == _openedSharedStopId) {
      return;
    }
    _openedSharedStopId = session.currentStopId;
    _sharedNavigationOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await Navigator.of(context, rootNavigator: true).push<void>(
        PageRouteBuilder<void>(
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (_, _, _) =>
              ActiveItineraryMapScreen(controller: controller),
        ),
      );
      _sharedNavigationOpen = false;
    });
  }

  TravelGroupController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.addListener(_handleControllerUpdate);
    unawaited(_refresh());
    _workspaceTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) unawaited(_refresh());
    });
    _locationHeartbeat = Timer.periodic(const Duration(seconds: 20), (_) {
      final service = _locationService;
      if (mounted && service != null) {
        unawaited(_refreshOwnPosition(service));
      }
    });
    final message = widget.initialMessage;
    if (message != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showTravelGroupMessage(context, message);
      });
    }
  }

  @override
  void dispose() {
    _workspaceTimer?.cancel();
    _locationHeartbeat?.cancel();
    controller.removeListener(_handleControllerUpdate);
    _positionSubscription?.cancel();
    _memberLocationSubscription?.cancel();
    final service = _locationService;
    if (service != null) unawaited(service.dispose());
    super.dispose();
  }

  void _handleControllerUpdate() {
    _followCreatorNavigation();
    final group = controller.activeGroup;
    if (!controller.isMember ||
        group == null ||
        group.status == GroupStatus.completed ||
        group.status == GroupStatus.cancelled) {
      unawaited(_stopLocationSharing());
      return;
    }
    if (controller.isMember &&
        controller.activeSession != null &&
        _locationService == null &&
        !_startingLocationSharing) {
      unawaited(_startLocationSharing());
    }
  }

  Future<void> _stopLocationSharing() async {
    final service = _locationService;
    _locationService = null;
    final positions = _positionSubscription;
    _positionSubscription = null;
    final members = _memberLocationSubscription;
    _memberLocationSubscription = null;
    await positions?.cancel();
    await members?.cancel();
    await service?.dispose();
  }

  Future<void> _refreshOwnPosition(LiveTripLocationService service) async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      if (mounted) await _publishLocation(service, position);
    } catch (error) {
      _setLocationSharingError(error);
    }
  }

  Future<void> _refresh() async {
    if (_refreshingWorkspace || !mounted) return;
    _refreshingWorkspace = true;
    try {
      await controller.refreshWorkspace();
      if (mounted &&
          controller.isMember &&
          controller.activeSession != null &&
          _locationService == null) {
        await _startLocationSharing();
      }
    } catch (error) {
      _setLocationSharingError(error);
    } finally {
      _refreshingWorkspace = false;
    }
  }

  Future<void> _startLocationSharing() async {
    if (_locationService != null || _startingLocationSharing) return;
    if (controller.ongoingMemberGroup?.id != controller.activeGroup?.id) return;
    _startingLocationSharing = true;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      if (!mounted || !controller.isMember) return;
      final service = controller.createLiveTripLocationService();
      _locationService = service;
      _memberLocationSubscription = service.watchLocations().listen((
        locations,
      ) {
        if (mounted) setState(() => _liveMembers = locations);
      }, onError: _setLocationSharingError);
      _positionSubscription =
          Geolocator.getPositionStream(
            locationSettings: navigationLocationSettings,
          ).listen(
            (position) => unawaited(_publishLocation(service, position)),
            onError: (Object error) => _setLocationSharingError(error),
          );
      try {
        await _publishLocation(
          service,
          await Geolocator.getCurrentPosition(
            locationSettings: navigationLocationSettings,
          ),
        );
      } catch (error) {
        _setLocationSharingError(error);
      }
    } finally {
      _startingLocationSharing = false;
    }
  }

  Future<void> _publishLocation(
    LiveTripLocationService service,
    Position position,
  ) async {
    final coordinate = controller.effectiveLocation(
      position.latitude,
      position.longitude,
    );
    try {
      await service.publishOwnLocation(
        latitude: coordinate.latitude,
        longitude: coordinate.longitude,
        accuracyMeters: position.accuracy,
      );
      if (mounted && _locationSharingError != null) {
        setState(() => _locationSharingError = null);
      }
    } catch (error) {
      _setLocationSharingError(error);
    }
  }

  void _setLocationSharingError(Object error) {
    if (!mounted) return;
    setState(() {
      _locationSharingError =
          'Live location could not reach the group. ${error.toString()}';
    });
  }

  @override
  Widget build(BuildContext context) {
    return TravelGroupScaffold(
      controller: controller,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final group = controller.activeGroup;
          // Deleting clears the controller before this route finishes its pop
          // animation. Keep that final rebuild inert instead of dereferencing
          // the group that was just removed.
          if (group == null) return const SizedBox.shrink();
          if (!controller.isMember) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: AppPanel(
                  color: AppColors.paleBlue,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.lock_outline_rounded,
                        color: AppColors.primary,
                        size: 34,
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'This lobby is for joined travellers',
                        style: TextStyle(fontSize: 16),
                      ),
                      const SizedBox(height: 5),
                      const Text(
                        'Return to the group details to join or request access.',
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Back to group details'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: () => Navigator.pop(context),
                      child: const Text(
                        '‹ Nearby lobbies',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            group.name,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Refresh lobby',
                          onPressed: _refresh,
                          icon: const Icon(Icons.refresh_rounded),
                        ),
                        if (controller.isCreator)
                          PopupMenuButton<String>(
                            key: const Key('group_actions_menu'),
                            tooltip: 'Group actions',
                            onSelected: (value) {
                              if (value == 'delete') {
                                unawaited(_deleteGroup());
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem<String>(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.delete_outline_rounded,
                                      color: Color(0xFFB3261E),
                                    ),
                                    SizedBox(width: 10),
                                    Text('Delete group'),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        _StatusBadge(group: group),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      group.tags.join('  •  '),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.secondaryText,
                      ),
                    ),
                    const SizedBox(height: 10),
                    GroupTabs(
                      index: _tabIndex,
                      onChanged: (index) => setState(() => _tabIndex = index),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: IndexedStack(
                  index: _tabIndex,
                  children: [
                    _LobbyTab(
                      controller: controller,
                      locationSharingError: _locationSharingError,
                      liveMembers: _liveMembers,
                      onSuggest: () => setState(() => _tabIndex = 1),
                    ),
                    SuggestionBoard(controller: controller),
                    ItineraryBoard(controller: controller),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _deleteGroup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this group?'),
        content: const Text(
          'This permanently removes the lobby, members, suggestions, and itinerary.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm_delete_group_button'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB3261E),
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete group'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await controller.deleteActiveGroup();
      if (mounted) Navigator.pop(context, true);
    } on TravelGroupException catch (error) {
      if (mounted) {
        showTravelGroupMessage(context, error.message, error: true);
      }
    }
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.group});

  final TravelGroup group;

  @override
  Widget build(BuildContext context) {
    final label = switch (group.tripPhase) {
      GroupTripPhase.recruiting => 'RECRUITING',
      GroupTripPhase.gathering => 'MEETING UP',
      GroupTripPhase.navigating => 'ON THE WAY',
      GroupTripPhase.choosingNext => 'CHOOSING NEXT',
      GroupTripPhase.completed => 'COMPLETED',
      GroupTripPhase.cancelled => 'CANCELLED',
    };
    final color = group.tripPhase == GroupTripPhase.completed
        ? AppColors.success
        : AppColors.primary;
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 13),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: group.tripPhase == GroupTripPhase.completed
            ? AppColors.successSurface
            : AppColors.paleBlue,
        border: Border.all(
          color: group.tripPhase == GroupTripPhase.completed
              ? const Color(0xFF8CDBB0)
              : AppColors.border,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label, style: TextStyle(fontSize: 9, color: color)),
    );
  }
}

class _LobbyTab extends StatelessWidget {
  const _LobbyTab({
    required this.controller,
    required this.locationSharingError,
    required this.liveMembers,
    required this.onSuggest,
  });

  final TravelGroupController controller;
  final String? locationSharingError;
  final List<LiveMemberLocation> liveMembers;
  final VoidCallback onSuggest;

  @override
  Widget build(BuildContext context) {
    final group = controller.activeGroup!;
    final nextStop = controller.nextItineraryStop;
    final pending = controller.joinRequests
        .where((request) => request.status == JoinRequestStatus.pending)
        .toList();
    final meetupReady = _meetupReadiness(group);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        if (group.status == GroupStatus.completed)
          AppPanel(
            color: AppColors.successSurface,
            child: Text(
              controller.isCreator
                  ? 'Travel Group ended. Your trip history has been saved.'
                  : '${group.creatorName} ended this Travel Group session. Your trip history has been saved.',
            ),
          ),
        if (locationSharingError != null) ...[
          AppPanel(
            color: const Color(0xFFFFECEA),
            borderColor: const Color(0xFFF0A39B),
            child: Text(
              locationSharingError!,
              style: const TextStyle(fontSize: 11, color: Color(0xFF8C1D18)),
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (controller.isMember) ...[
          AppPanel(
            color: const Color(0xFFE8FAF0),
            borderColor: const Color(0xFF8CDBB0),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 16,
                  backgroundColor: AppColors.success,
                  child: Icon(Icons.check, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'You’re in the lobby',
                        style: TextStyle(fontSize: 14),
                      ),
                      Text(
                        '${group.memberCount} of ${group.maxMembers} members',
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.secondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (controller.isCreator && !group.isConfirmed) ...[
          AppPanel(
            color: const Color(0xFFFFF6E8),
            borderColor: const Color(0xFFF2CB8D),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Confirm your travellers',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                const Text(
                  'When your group is ready, confirm it to unlock live locations and meetup selection.',
                  style: TextStyle(fontSize: 11),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const Key('confirm_group_button'),
                    onPressed: () => _confirmGroup(context),
                    icon: const Icon(Icons.group_add_rounded),
                    label: const Text('Confirm group'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        AppPanel(
          color: AppColors.paleBlue,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'MEETUP POINT',
                      style: TextStyle(fontSize: 10, color: AppColors.primary),
                    ),
                  ),
                  if (group.isConfirmed &&
                      group.status != GroupStatus.completed &&
                      group.status != GroupStatus.cancelled)
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) =>
                              MeetupPickerScreen(controller: controller),
                        ),
                      ),
                      child: Text(
                        !controller.isCreator
                            ? 'View everyone'
                            : group.meetupPoint.isEmpty
                            ? 'Set on map'
                            : 'Change',
                      ),
                    ),
                ],
              ),
              Text(
                group.meetupPoint.isEmpty
                    ? controller.isCreator
                          ? 'See joined travellers live, then choose a fair meetup point.'
                          : 'The creator will set a meetup point after travellers join.'
                    : group.meetupPoint,
                style: const TextStyle(fontSize: 15),
              ),
              if (group.meetupNote.isNotEmpty) ...[
                const SizedBox(height: 9),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '●  ${group.meetupNote}',
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.secondaryText,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        AppPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('Members', style: TextStyle(fontSize: 14)),
                  const SizedBox(width: 12),
                  Text(
                    '${group.memberCount} / ${group.maxMembers}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.primary,
                    ),
                  ),
                  const Spacer(),
                ],
              ),
              const SizedBox(height: 6),
              if (controller.members.isEmpty)
                const Text(
                  'Member profiles are loading…',
                  style: TextStyle(color: AppColors.secondaryText),
                )
              else
                for (var index = 0; index < controller.members.length; index++)
                  _MemberProfileTile(
                    member: controller.members[index],
                    isCurrentUser:
                        controller.members[index].userId ==
                        controller.currentUser.id,
                    onTap: () =>
                        _openProfile(context, controller.members[index]),
                  ),
            ],
          ),
        ),
        if (controller.isCreator && pending.isNotEmpty) ...[
          const SizedBox(height: 10),
          AppPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Join requests (${pending.length})',
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 8),
                for (final request in pending)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        MemberAvatar(
                          label: request.travellerName.substring(0, 1),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(request.travellerName)),
                        TextButton(
                          onPressed: () =>
                              controller.respondToRequest(request, false),
                          child: const Text('Decline'),
                        ),
                        FilledButton(
                          onPressed: () =>
                              controller.respondToRequest(request, true),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(68, 32),
                          ),
                          child: const Text('Accept'),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        if (kDebugMode &&
            group.tripPhase == GroupTripPhase.gathering &&
            group.meetupLatitude != null) ...[
          AppPanel(
            color: const Color(0xFFFFF6E8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'DEMO SIMULATION · not actual GPS',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  controller.meetupSimulation == null
                      ? 'Each member must tap this on their own device. Your pin travels to the meetup in about 10 seconds.'
                      : controller.meetupSimulation!.arrived
                      ? 'Simulated arrival. Keeping your meetup location fresh until the creator begins the trip.'
                      : 'Your simulated pin is on its way to the meetup.',
                ),
                if (controller.meetupSimulationError != null)
                  Text(
                    'Could not share simulation: ${controller.meetupSimulationError}',
                  ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  key: const Key('simulate_to_meetup_button'),
                  onPressed: controller.meetupSimulation == null
                      ? () => _simulateMeetup(context)
                      : controller.stopMeetupSimulation,
                  icon: Icon(
                    controller.meetupSimulation == null
                        ? Icons.directions_walk
                        : Icons.gps_fixed,
                  ),
                  label: Text(
                    controller.meetupSimulation == null
                        ? 'Simulate to meetup'
                        : 'Stop simulation · use real GPS',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (controller.isCreator &&
            group.tripPhase == GroupTripPhase.gathering &&
            group.meetupPoint.isNotEmpty) ...[
          AppPanel(
            color: meetupReady.$1
                ? const Color(0xFFE8FAF0)
                : const Color(0xFFFFF6E8),
            borderColor: meetupReady.$1
                ? const Color(0xFF8CDBB0)
                : const Color(0xFFF2CB8D),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  meetupReady.$1
                      ? Icons.check_circle_rounded
                      : Icons.location_searching_rounded,
                  color: meetupReady.$1
                      ? AppColors.success
                      : const Color(0xFF9A5B00),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    meetupReady.$2,
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (controller.isCreator && group.tripPhase == GroupTripPhase.gathering)
          FilledButton.icon(
            key: const Key('begin_group_trip_button'),
            onPressed:
                group.meetupPoint.isEmpty ||
                    group.memberCount < 2 ||
                    !meetupReady.$1
                ? null
                : () => _beginTrip(context),
            icon: const Icon(Icons.navigation_rounded),
            label: Text(
              group.meetupPoint.isEmpty
                  ? 'Set meetup point first'
                  : group.memberCount < 2
                  ? 'Wait for another traveller'
                  : !meetupReady.$1
                  ? 'Waiting at meetup point'
                  : 'Begin group trip',
            ),
          )
        else if (group.tripPhase == GroupTripPhase.choosingNext)
          Column(
            children: [
              const Text(
                'Enjoy the current stop. The creator starts the next leg when everyone is ready.',
              ),
              if (controller.isCreator && nextStop != null)
                FilledButton.icon(
                  onPressed: () =>
                      _beginTrip(context, expectedStopId: nextStop.id),
                  icon: const Icon(Icons.navigation),
                  label: Text('Start next: ${nextStop.placeName}'),
                ),
              FilledButton.icon(
                key: const Key('choose_next_stop_button'),
                onPressed: onSuggest,
                icon: const Icon(Icons.add_location_alt_rounded),
                label: const Text('Choose where to go next'),
              ),
            ],
          )
        else if (group.tripPhase == GroupTripPhase.navigating)
          FilledButton.icon(
            onPressed: () => _openNavigation(context),
            icon: const Icon(Icons.navigation_rounded),
            label: const Text('Return to navigation'),
          )
        else if (group.status == GroupStatus.completed ||
            group.status == GroupStatus.cancelled)
          const SizedBox.shrink()
        else
          FilledButton(
            onPressed: onSuggest,
            child: const Text('+  Suggest a stop'),
          ),
        if (controller.isCreator &&
            (group.tripPhase == GroupTripPhase.navigating ||
                group.tripPhase == GroupTripPhase.choosingNext)) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            key: const Key('end_travel_group_from_lobby_button'),
            onPressed: () => _endTravelGroup(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFB3261E),
              side: const BorderSide(color: Color(0xFFB3261E)),
            ),
            icon: const Icon(Icons.stop_circle_outlined),
            label: const Text('End Travel Group'),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          controller.isCreator
              ? 'You control final stops and when the trip starts.'
              : 'Only the creator can start the group trip.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 10, color: AppColors.secondaryText),
        ),
      ],
    );
  }

  (bool, String) _meetupReadiness(TravelGroup group) {
    final meetupLatitude = group.meetupLatitude;
    final meetupLongitude = group.meetupLongitude;
    if (meetupLatitude == null || meetupLongitude == null) {
      return (false, 'Set a meetup point first.');
    }
    final recent = liveMembers.where((location) => location.isFresh).toList();
    if (recent.length < group.memberCount) {
      return (
        false,
        '${recent.length} of ${group.memberCount} travellers have shared a location in the last 2 minutes. Keep this lobby open on every device.',
      );
    }
    for (final location in recent) {
      final distance = Geolocator.distanceBetween(
        location.coordinate.latitude,
        location.coordinate.longitude,
        meetupLatitude,
        meetupLongitude,
      );
      if (distance > 150) {
        return (
          false,
          '${location.displayName} is ${distance >= 1000 ? '${(distance / 1000).toStringAsFixed(1)} km' : '${distance.round()} m'} from the meetup point. Everyone must be within 150 m.',
        );
      }
    }
    return (true, 'Everyone is sharing a recent location within 150 m.');
  }

  Future<void> _confirmGroup(BuildContext context) async {
    try {
      await controller.confirmGroup();
      if (context.mounted) {
        showTravelGroupMessage(
          context,
          'Group confirmed. Live meetup planning is now available.',
        );
      }
    } on TravelGroupException catch (error) {
      if (context.mounted) {
        showTravelGroupMessage(context, error.message, error: true);
      }
    }
  }

  Future<void> _beginTrip(
    BuildContext context, {
    String? expectedStopId,
  }) async {
    try {
      await controller.startItinerary(expectedStopId: expectedStopId);
      if (context.mounted) await _openNavigation(context);
    } on TravelGroupException catch (error) {
      if (context.mounted) {
        showTravelGroupMessage(context, error.message, error: true);
      }
    }
  }

  Future<void> _simulateMeetup(BuildContext context) async {
    try {
      final own = liveMembers
          .where(
            (member) =>
                member.userId == controller.currentUser.id && member.isFresh,
          )
          .firstOrNull;
      final position = own == null
          ? await Geolocator.getCurrentPosition(
              locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.high,
                timeLimit: Duration(seconds: 15),
              ),
            )
          : null;
      await controller.simulateToMeetup(
        own?.coordinate ??
            GeoCoordinate(position!.latitude, position.longitude),
      );
    } catch (error) {
      if (context.mounted) {
        showTravelGroupMessage(
          context,
          'Could not start simulation: $error',
          error: true,
        );
      }
    }
  }

  Future<void> _endTravelGroup(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('End this Travel Group?'),
        content: const Text(
          'This ends the trip for everyone and saves it to each traveller\'s history. It cannot be resumed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep travelling'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('End Travel Group'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await controller.endTrip();
      if (!context.mounted) return;
      showTravelGroupMessage(context, 'Travel Group saved to your history.');
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on TravelGroupException catch (error) {
      if (context.mounted) {
        showTravelGroupMessage(context, error.message, error: true);
      }
    }
  }

  Future<void> _openNavigation(BuildContext context) =>
      Navigator.of(context, rootNavigator: true).push<void>(
        MaterialPageRoute(
          builder: (_) => ActiveItineraryMapScreen(controller: controller),
        ),
      );

  void _openProfile(BuildContext context, GroupMemberProfile member) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => GroupMemberProfileScreen(
          member: member,
          groupName: controller.activeGroup!.name,
          isCurrentUser: member.userId == controller.currentUser.id,
        ),
      ),
    );
  }
}

class _MemberProfileTile extends StatelessWidget {
  const _MemberProfileTile({
    required this.member,
    required this.isCurrentUser,
    required this.onTap,
  });

  final GroupMemberProfile member;
  final bool isCurrentUser;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'View ${member.displayName} profile',
      child: InkWell(
        key: Key('member_profile_${member.userId}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.primary,
                foregroundImage:
                    member.avatarUrl == null || member.avatarUrl!.isEmpty
                    ? null
                    : NetworkImage(member.avatarUrl!),
                child: Text(
                  member.initials,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      member.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      [
                        member.isCreator ? 'Creator' : 'Traveller',
                        if (isCurrentUser) 'You',
                      ].join(' · '),
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.secondaryText,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
