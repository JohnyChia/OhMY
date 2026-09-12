import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../../../preference_recommender/features/routes/navigation_sensor.dart';
import '../../../core/theme/app_theme.dart';
import '../controllers/travel_group_controller.dart';
import '../models/travel_group_models.dart';
import '../services/live_trip_location_service.dart';
import '../widgets/travel_group_scaffold.dart';
import '../widgets/travel_group_widgets.dart';
import 'edit_group_sheet.dart';
import 'group_lobby_screen.dart';
import 'verification_required_screen.dart';

class GroupDetailsScreen extends StatelessWidget {
  const GroupDetailsScreen({super.key, required this.controller});

  final TravelGroupController controller;

  @override
  Widget build(BuildContext context) {
    return TravelGroupScaffold(
      controller: controller,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final group = controller.activeGroup!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
            children: [
              InkWell(
                onTap: () => Navigator.pop(context),
                child: const Text(
                  '‹ Nearby lobbies',
                  style: TextStyle(color: AppColors.primary, fontSize: 11),
                ),
              ),
              const SizedBox(height: 9),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      group.name,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                  if (controller.isCreator &&
                      group.status == GroupStatus.waiting) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      key: const Key('edit_group_button'),
                      tooltip: 'Edit group',
                      onPressed: () => _openEditSheet(context),
                      icon: const Icon(
                        Icons.edit_outlined,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                  if (controller.isCreator)
                    IconButton(
                      key: const Key('delete_group_button'),
                      tooltip: 'Delete group',
                      onPressed: () => _deleteGroup(context),
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        color: Color(0xFFB3261E),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${group.distanceKm.toStringAsFixed(1)} km away  •  ${group.joinMode == JoinMode.open ? 'Open group' : 'Approval required'}',
              ),
              const SizedBox(height: 14),
              AppPanel(
                color: AppColors.paleBlue,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.description,
                      style: const TextStyle(fontSize: 14, height: 1.4),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 7,
                      children: group.tags
                          .map(
                            (tag) =>
                                AppPill(tag, backgroundColor: Colors.white),
                          )
                          .toList(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              AppPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'MEETUP POINT',
                      style: TextStyle(fontSize: 10, color: AppColors.primary),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      group.meetupPoint.isEmpty
                          ? 'The creator will set this after travellers join.'
                          : group.meetupPoint,
                      style: const TextStyle(fontSize: 15),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${group.memberCount} of ${group.maxMembers} travellers  •  Hosted by ${group.creatorName}',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: _actionButton(context, group),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _actionButton(BuildContext context, TravelGroup group) {
    if (controller.isMember) {
      return FilledButton(
        onPressed: () => _openLobby(context),
        child: const Text('Enter lobby'),
      );
    }
    if (group.isFull) {
      return const FilledButton(onPressed: null, child: Text('Group full'));
    }
    if (group.status != GroupStatus.waiting ||
        (group.tripPhase != GroupTripPhase.recruiting &&
            group.tripPhase != GroupTripPhase.gathering)) {
      return const FilledButton(
        onPressed: null,
        child: Text('Trip already started'),
      );
    }
    if (controller.hasPendingRequestForCurrentUser()) {
      return const FilledButton(
        onPressed: null,
        child: Text('Request pending'),
      );
    }
    return FilledButton(
      onPressed: () => _join(context),
      child: Text(
        group.joinMode == JoinMode.open ? 'Join now' : 'Request to join',
      ),
    );
  }

  Future<void> _openEditSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      builder: (_) => EditGroupSheet(controller: controller),
    );
  }

  Future<void> _join(BuildContext context) async {
    try {
      final location = await _joinLocation();
      await controller.joinActiveGroup(location: location);
      if (!context.mounted) return;
      if (controller.activeGroup!.joinMode == JoinMode.open) {
        await _openLobby(context);
      } else {
        showTravelGroupMessage(context, 'Join request sent to the creator.');
      }
    } on TravelGroupException catch (error) {
      if (!context.mounted) return;
      if (error.code == 'verification_required') {
        await Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) => VerificationRequiredScreen(controller: controller),
          ),
        );
      } else {
        showTravelGroupMessage(context, error.message, error: true);
      }
    } catch (error) {
      if (context.mounted) {
        showTravelGroupMessage(
          context,
          kDebugMode
              ? 'Could not read the current location: $error'
              : 'Could not read your precise location. Check location settings and try again.',
          error: true,
        );
      }
    }
  }

  Future<GeoCoordinate> _joinLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const TravelGroupException(
        'Turn on precise location before joining a travel group.',
        'location_disabled',
      );
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw const TravelGroupException(
        'Precise location permission is required to join nearby groups.',
        'location_permission_required',
      );
    }
    final position = await Geolocator.getCurrentPosition(
      locationSettings: navigationLocationSettings,
    );
    return GeoCoordinate(position.latitude, position.longitude);
  }

  Future<void> _openLobby(BuildContext context) async {
    final deleted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => GroupLobbyScreen(controller: controller),
      ),
    );
    if (deleted == true && context.mounted) {
      Navigator.pop(context, true);
    }
  }

  Future<void> _deleteGroup(BuildContext context) async {
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
    if (confirmed != true || !context.mounted) return;
    try {
      await controller.deleteActiveGroup();
      if (context.mounted) Navigator.pop(context, true);
    } on TravelGroupException catch (error) {
      if (context.mounted) {
        showTravelGroupMessage(context, error.message, error: true);
      }
    }
  }
}
