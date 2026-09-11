import 'dart:async';

import 'package:flutter/material.dart';
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
import 'meetup_picker_screen.dart';
import 'suggestion_board.dart';

class GroupLobbyScreen extends StatefulWidget {
  const GroupLobbyScreen({super.key, required this.controller});

  final TravelGroupController controller;

  @override
  State<GroupLobbyScreen> createState() => _GroupLobbyScreenState();
}

class _GroupLobbyScreenState extends State<GroupLobbyScreen> {
  int _tabIndex = 0;
  LiveTripLocationService? _locationService;
  StreamSubscription<Position>? _positionSubscription;

  TravelGroupController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    final service = _locationService;
    if (service != null) unawaited(service.dispose());
    super.dispose();
  }

  Future<void> _refresh() async {
    await controller.refreshWorkspace();
    if (mounted &&
        controller.isMember &&
        controller.activeSession != null &&
        _locationService == null) {
      await _startLocationSharing();
    }
  }

  Future<void> _startLocationSharing() async {
    if (!await Geolocator.isLocationServiceEnabled()) return;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }
    final service = controller.createLiveTripLocationService();
    _locationService = service;
    void publish(Position position) => service.publishOwnLocation(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracyMeters: position.accuracy,
    );
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: navigationLocationSettings,
    ).listen(publish);
    try {
      publish(
        await Geolocator.getCurrentPosition(
          locationSettings: navigationLocationSettings,
        ),
      );
    } catch (_) {
      // The stream will publish when the device gets its next precise fix.
    }
  }

  @override
  Widget build(BuildContext context) {
    return TravelGroupScaffold(
      controller: controller,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final group = controller.activeGroup!;
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
  const _LobbyTab({required this.controller, required this.onSuggest});

  final TravelGroupController controller;
  final VoidCallback onSuggest;

  @override
  Widget build(BuildContext context) {
    final group = controller.activeGroup!;
    final pending = controller.joinRequests
        .where((request) => request.status == JoinRequestStatus.pending)
        .toList();
    final confirmed = controller.suggestions
        .where((suggestion) => suggestion.isConfirmed)
        .length;
    final avatarCount = group.memberIds.length > 5 ? 5 : group.memberIds.length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
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
                  if (controller.isCreator && group.isConfirmed)
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) =>
                              MeetupPickerScreen(controller: controller),
                        ),
                      ),
                      child: Text(
                        group.meetupPoint.isEmpty ? 'Set on map' : 'Change',
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
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  for (var index = 0; index < avatarCount; index++)
                    MemberAvatar(
                      label: index == 0 ? 'AS' : 'M$index',
                      color: Colors
                          .primaries[index % Colors.primaries.length]
                          .shade400,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${group.creatorName} · Creator',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11),
              ),
              const Text(
                'Group creator',
                style: TextStyle(fontSize: 9, color: AppColors.secondaryText),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        AppPanel(
          color: AppColors.paleBlue,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Planning progress', style: TextStyle(fontSize: 14)),
              const Text(
                'Collaborate before the creator starts the trip.',
                style: TextStyle(fontSize: 10, color: AppColors.secondaryText),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _ProgressStat(
                    value: '${controller.suggestions.length}',
                    label: 'Suggestions',
                  ),
                  const SizedBox(width: 9),
                  _ProgressStat(value: '$confirmed', label: 'Confirmed stops'),
                  const SizedBox(width: 9),
                  _ProgressStat(
                    value: group.status == GroupStatus.waiting
                        ? 'Not started'
                        : group.status.name,
                    label: 'Trip status',
                    warning: group.status == GroupStatus.waiting,
                  ),
                ],
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
        if (controller.isCreator && group.tripPhase == GroupTripPhase.gathering)
          FilledButton.icon(
            key: const Key('begin_group_trip_button'),
            onPressed: group.meetupPoint.isEmpty || group.memberCount < 2
                ? null
                : () => _beginTrip(context),
            icon: const Icon(Icons.navigation_rounded),
            label: Text(
              group.meetupPoint.isEmpty
                  ? 'Set meetup point first'
                  : group.memberCount < 2
                  ? 'Wait for another traveller'
                  : 'Begin group trip',
            ),
          )
        else if (group.tripPhase == GroupTripPhase.choosingNext)
          FilledButton.icon(
            key: const Key('choose_next_stop_button'),
            onPressed: onSuggest,
            icon: const Icon(Icons.add_location_alt_rounded),
            label: const Text('Choose where to go next'),
          )
        else if (group.tripPhase == GroupTripPhase.navigating)
          FilledButton.icon(
            onPressed: () => _openNavigation(context),
            icon: const Icon(Icons.navigation_rounded),
            label: const Text('Return to navigation'),
          )
        else
          FilledButton(
            onPressed: onSuggest,
            child: const Text('+  Suggest a stop'),
          ),
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

  Future<void> _beginTrip(BuildContext context) async {
    try {
      await controller.startItinerary();
      if (context.mounted) await _openNavigation(context);
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
}

class _ProgressStat extends StatelessWidget {
  const _ProgressStat({
    required this.value,
    required this.label,
    this.warning = false,
  });

  final String value;
  final String label;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FittedBox(
              child: Text(
                value,
                style: TextStyle(
                  fontSize: value.length > 4 ? 11 : 17,
                  color: warning ? AppColors.warning : AppColors.primary,
                ),
              ),
            ),
            Text(
              label,
              style: const TextStyle(
                fontSize: 9,
                color: AppColors.secondaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
