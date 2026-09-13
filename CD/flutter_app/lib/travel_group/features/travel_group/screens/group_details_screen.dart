import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../../../preference_recommender/features/routes/navigation_sensor.dart';
import '../../../core/theme/app_theme.dart';
import '../controllers/travel_group_controller.dart';
import '../models/travel_group_models.dart';
import '../services/live_trip_location_service.dart';
import '../services/travel_place_search_service.dart';
import '../widgets/travel_group_scaffold.dart';
import '../widgets/travel_group_widgets.dart';
import 'edit_group_sheet.dart';
import 'group_lobby_screen.dart';
import 'verification_required_screen.dart';

class GroupDetailsScreen extends StatefulWidget {
  const GroupDetailsScreen({
    super.key,
    required this.controller,
    this.placeSearchService,
  });

  final TravelGroupController controller;
  final TravelPlaceSearchService? placeSearchService;

  @override
  State<GroupDetailsScreen> createState() => _GroupDetailsScreenState();
}

class _GroupDetailsScreenState extends State<GroupDetailsScreen> {
  late final TravelPlaceSearchService _placeSearch;
  late final bool _ownsPlaceSearch;

  TravelGroupController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _ownsPlaceSearch = widget.placeSearchService == null;
    _placeSearch = widget.placeSearchService ?? TravelPlaceSearchService();
  }

  @override
  void dispose() {
    if (_ownsPlaceSearch) _placeSearch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TravelGroupScaffold(
      controller: controller,
      child: SafeArea(
        bottom: false,
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            final group = controller.activeGroup;
            if (group == null) return const SizedBox.shrink();
            final canSeeMeetup = controller.isMember && group.isConfirmed;
            return ListView(
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 28),
              children: [
                _TopBar(
                  isCreator: controller.isCreator,
                  onBack: () => Navigator.pop(context),
                  onEdit: () => _openEditSheet(context),
                  onDelete: () => _deleteGroup(context),
                ),
                Container(
                  height: 176,
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x1F24476F),
                        blurRadius: 10,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _DestinationPhoto(
                    photoUrl: _placeSearch.photoForDestination(
                      group.destination,
                      knownPhotoName: group.destinationPhotoName,
                    ),
                    destination: group.destination,
                  ),
                ),
                const SizedBox(height: 12),
                AppPanel(
                  color: const Color(0xF2FFFFFF),
                  padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppColors.success,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              group.joinMode == JoinMode.open
                                  ? 'Open Group Trip - Join instantly'
                                  : 'Approval required',
                              style: const TextStyle(
                                color: AppColors.secondaryText,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        group.description,
                        style: const TextStyle(fontSize: 14, height: 1.4),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 7,
                        runSpacing: 7,
                        children: group.tags
                            .map(
                              (tag) => AppPill(
                                tag,
                                backgroundColor: AppColors.paleBlue,
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                if (canSeeMeetup) ...[
                  AppPanel(
                    color: const Color(0xF2FFFFFF),
                    child: _DetailsRow(
                      icon: Icons.location_on_rounded,
                      eyebrow: 'MEETUP POINT',
                      title: group.meetupPoint.isEmpty
                          ? 'Not set yet'
                          : group.meetupPoint,
                      subtitle: group.meetupPoint.isEmpty
                          ? 'The creator will choose it with the group.'
                          : 'Visible only to confirmed group members',
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                AppPanel(
                  color: const Color(0xF2FFFFFF),
                  child: _DetailsRow(
                    icon: Icons.group_rounded,
                    eyebrow: 'MEMBERS',
                    title:
                        '${group.memberCount} of ${group.maxMembers} travellers',
                    subtitle: 'Hosted by ${group.creatorName}',
                    trailing: _AvatarStack(controller: controller),
                  ),
                ),
                const SizedBox(height: 10),
                AppPanel(
                  color: const Color(0xF2FFFFFF),
                  child: _DetailsRow(
                    icon: Icons.place_outlined,
                    eyebrow: 'FIRST DESTINATION',
                    title: group.destination,
                    subtitle: group.destinationAddress.isEmpty
                        ? "The Group Trip's first confirmed stop"
                        : group.destinationAddress,
                  ),
                ),
                if (!canSeeMeetup && !controller.isMember) ...[
                  const SizedBox(height: 10),
                  const AppPanel(
                    color: Color(0xF2F0F6FF),
                    child: Row(
                      children: [
                        Icon(Icons.shield_outlined, color: AppColors.primary),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Meetup and live locations stay private until you join and the creator confirms the group.',
                            style: TextStyle(fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: _actionButton(context, group),
                ),
              ],
            );
          },
        ),
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
      backgroundColor: const Color(0xFFF8FBFF),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      clipBehavior: Clip.antiAlias,
      builder: (_) => Theme(
        data: AppTheme.light,
        child: EditGroupSheet(controller: controller),
      ),
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
        'Turn on precise location before joining a group trip.',
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
    if (deleted == true && context.mounted) Navigator.pop(context, true);
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

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.isCreator,
    required this.onBack,
    required this.onEdit,
    required this.onDelete,
  });

  final bool isCreator;
  final VoidCallback onBack;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 52,
    child: Row(
      children: [
        IconButton(
          tooltip: 'Nearby lobbies',
          onPressed: onBack,
          color: AppColors.primaryDark,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        const Expanded(
          child: Text(
            'Nearby lobbies',
            style: TextStyle(
              color: AppColors.primaryDark,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (isCreator)
          PopupMenuButton<String>(
            color: Colors.white,
            onSelected: (value) {
              if (value == 'edit') onEdit();
              if (value == 'delete') onDelete();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit group')),
              PopupMenuItem(value: 'delete', child: Text('Delete group')),
            ],
          )
        else
          const SizedBox(width: 48),
      ],
    ),
  );
}

class _DestinationPhoto extends StatelessWidget {
  const _DestinationPhoto({required this.photoUrl, required this.destination});

  final Future<String?> photoUrl;
  final String destination;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      FutureBuilder<String?>(
        future: photoUrl,
        builder: (context, snapshot) {
          final url = snapshot.data;
          if (url == null) return const _DestinationFallback();
          return Image.network(
            url,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const _DestinationFallback(),
          );
        },
      ),
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.center,
            colors: [Color(0xB800183A), Colors.transparent],
          ),
        ),
      ),
      Positioned(
        left: 16,
        right: 16,
        bottom: 14,
        child: Text(
          destination,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ],
  );
}

class _DestinationFallback extends StatelessWidget {
  const _DestinationFallback();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(colors: [Color(0xFF174982), Color(0xFF8EB7E8)]),
    ),
    child: Center(
      child: Icon(Icons.landscape_rounded, size: 62, color: Colors.white54),
    ),
  );
}

class _DetailsRow extends StatelessWidget {
  const _DetailsRow({
    required this.icon,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final String eyebrow;
  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: AppColors.paleBlue,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: AppColors.primary),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              eyebrow,
              style: const TextStyle(
                fontSize: 9,
                color: AppColors.secondaryText,
              ),
            ),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.secondaryText,
              ),
            ),
          ],
        ),
      ),
      if (trailing != null) ...[const SizedBox(width: 8), trailing!],
    ],
  );
}

class _AvatarStack extends StatelessWidget {
  const _AvatarStack({required this.controller});

  final TravelGroupController controller;

  @override
  Widget build(BuildContext context) {
    final shown = controller.members.take(2).toList();
    return SizedBox(
      width: shown.isEmpty ? 0 : 34.0 + (shown.length - 1) * 22,
      height: 34,
      child: Stack(
        children: [
          for (var index = 0; index < shown.length; index++)
            Positioned(
              left: index * 22,
              child: CircleAvatar(
                radius: 17,
                backgroundColor: index.isEven
                    ? AppColors.primary
                    : const Color(0xFFE72C69),
                child: Text(
                  shown[index].initials,
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
