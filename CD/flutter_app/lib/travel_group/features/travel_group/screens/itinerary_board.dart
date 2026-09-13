import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../controllers/travel_group_controller.dart';
import '../models/travel_group_models.dart';
import '../services/travel_place_search_service.dart';
import '../widgets/travel_place_photo.dart';
import '../widgets/travel_group_widgets.dart';
import 'active_itinerary_map_screen.dart';

class ItineraryBoard extends StatelessWidget {
  const ItineraryBoard({
    super.key,
    required this.controller,
    required this.placeSearchService,
    this.onChooseNext,
  });

  final TravelGroupController controller;
  final TravelPlaceSearchService placeSearchService;
  final VoidCallback? onChooseNext;

  @override
  Widget build(BuildContext context) {
    final group = controller.activeGroup!;
    final nextStop = controller.nextItineraryStop;
    return CustomScrollView(
      key: const Key('itinerary_board'),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          sliver: SliverMainAxisGroup(
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (controller.itinerary.isNotEmpty) ...[
                      _ItineraryMapPreview(controller: controller),
                      const SizedBox(height: 10),
                    ],
                    if (group.isConfirmed && group.meetupPoint.isNotEmpty) ...[
                      Container(
                        key: const Key('itinerary_meetup_summary'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 13,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.paleBlue,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.location_on_rounded,
                              color: AppColors.primary,
                              size: 21,
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    group.meetupPoint,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const Text(
                                    'Meetup point set by the group creator',
                                    style: TextStyle(
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
                    if (controller.itinerary.length > 1)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.successSurface,
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.sync_rounded,
                              color: AppColors.success,
                              size: 19,
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Time and distance recalculated',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                  Text(
                                    'Live traffic is applied when navigation starts',
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: AppColors.success,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (controller.itinerary.length > 1)
                      const SizedBox(height: 10),
                    if (controller.itinerary.isNotEmpty)
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Your route',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (controller.isCreator &&
                              controller.itinerary.length > 1)
                            const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.edit_outlined,
                                  size: 16,
                                  color: AppColors.primary,
                                ),
                                SizedBox(width: 5),
                                Text(
                                  'Drag to edit',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    if (controller.itinerary.isNotEmpty)
                      const SizedBox(height: 10),
                    if (controller.isCreator &&
                        group.status != GroupStatus.completed &&
                        group.status != GroupStatus.cancelled)
                      const Text(
                        '⋮⋮  Drag cards to reorder the itinerary',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.secondaryText,
                        ),
                      ),
                    const SizedBox(height: 10),
                    if (controller.itinerary.isEmpty)
                      const AppPanel(
                        color: AppColors.paleBlue,
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 28),
                          child: Column(
                            children: [
                              Icon(
                                Icons.route_outlined,
                                size: 38,
                                color: AppColors.primary,
                              ),
                              SizedBox(height: 10),
                              Text(
                                'No confirmed stops yet',
                                style: TextStyle(fontSize: 16),
                              ),
                              Text(
                                'Confirm a suggestion before starting the group trip.',
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (controller.itinerary.isNotEmpty)
                SliverReorderableList(
                  itemCount: controller.itinerary.length,
                  onReorderItem: controller.isCreator
                      ? (oldIndex, newIndex) async {
                          if (!controller.canReorderStop(oldIndex) ||
                              !controller.canReorderStop(newIndex)) {
                            return;
                          }
                          try {
                            await controller.reorderStops(oldIndex, newIndex);
                          } on TravelGroupException catch (error) {
                            if (context.mounted) {
                              showTravelGroupMessage(
                                context,
                                error.message,
                                error: true,
                              );
                            }
                          }
                        }
                      : (_, _) {},
                  itemBuilder: (context, index) {
                    final stop = controller.itinerary[index];
                    return Padding(
                      key: ValueKey(stop.id),
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Column(
                        children: [
                          _ItineraryStopCard(
                            stop: stop,
                            index: index,
                            placeSearchService: placeSearchService,
                            knownPhotoName:
                                (stop.placeId == group.destinationPlaceId ||
                                    stop.placeName == group.destination)
                                ? group.destinationPhotoName
                                : null,
                            canReorder:
                                controller.isCreator &&
                                controller.canReorderStop(index),
                            onRemove:
                                controller.isCreator &&
                                    index > 0 &&
                                    stop.status == StopStatus.upcoming
                                ? () => _removeStop(context, stop)
                                : null,
                            onComplete:
                                stop.status == StopStatus.current &&
                                    controller.isCreator
                                ? () => controller.completeStop(stop)
                                : null,
                          ),
                          if (index < controller.itinerary.length - 1)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: Center(
                                child: Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  key: Key('itinerary_direction_arrow'),
                                  size: 22,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (controller.isCreator &&
                        group.status != GroupStatus.completed &&
                        group.status != GroupStatus.cancelled) ...[
                      InkWell(
                        key: const Key('choose_next_itinerary_stop'),
                        onTap: onChooseNext,
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: AppColors.border),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Row(
                            children: [
                              CircleAvatar(
                                radius: 16,
                                backgroundColor: AppColors.paleBlue,
                                child: Icon(
                                  Icons.add_location_alt_outlined,
                                  color: AppColors.primary,
                                  size: 18,
                                ),
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Choose next stop',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      'Add a place from group suggestions',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: AppColors.secondaryText,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: AppColors.primary,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        key: const Key('add_itinerary_stop_button'),
                        onPressed: onChooseNext,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Add a stop'),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (controller.itinerary.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      if (group.tripPhase == GroupTripPhase.navigating)
                        FilledButton.icon(
                          onPressed: () => _openMap(context),
                          icon: const Icon(Icons.navigation_rounded),
                          label: const Text('Open active route map'),
                        )
                      else if (group.tripPhase == GroupTripPhase.choosingNext &&
                          controller.isCreator &&
                          nextStop != null)
                        FilledButton.icon(
                          key: const Key('start_next_itinerary_leg'),
                          icon: const Icon(Icons.navigation_rounded),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                          ),
                          label: const Text('Start Navigation'),
                          onPressed: () async {
                            try {
                              await controller.startItinerary(
                                expectedStopId: nextStop.id,
                              );
                              if (context.mounted) await _openMap(context);
                            } on TravelGroupException catch (error) {
                              if (context.mounted) {
                                showTravelGroupMessage(
                                  context,
                                  error.message,
                                  error: true,
                                );
                              }
                            }
                          },
                        )
                      else if (group.tripPhase == GroupTripPhase.choosingNext)
                        const AppPanel(
                          color: AppColors.paleBlue,
                          child: Center(
                            child: Text(
                              'Choose and confirm the next destination in Suggestions.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      else if (group.status == GroupStatus.completed)
                        const AppPanel(
                          color: AppColors.successSurface,
                          borderColor: Color(0xFFA8DEB8),
                          child: Center(
                            child: Text(
                              '✓ Group itinerary completed',
                              style: TextStyle(color: AppColors.success),
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _openMap(BuildContext context) async {
    await Navigator.of(context, rootNavigator: true).push<void>(
      PageRouteBuilder<void>(
        settings: const RouteSettings(name: '/travel-group/active-navigation'),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, _, _) =>
            ActiveItineraryMapScreen(controller: controller),
      ),
    );
    await controller.refreshWorkspace();
  }

  Future<void> _removeStop(BuildContext context, ItineraryStop stop) async {
    try {
      await controller.removeStop(stop);
    } on TravelGroupException catch (error) {
      if (context.mounted) {
        showTravelGroupMessage(context, error.message, error: true);
      }
    }
  }
}

class _ItineraryMapPreview extends StatelessWidget {
  const _ItineraryMapPreview({required this.controller});

  final TravelGroupController controller;

  @override
  Widget build(BuildContext context) {
    final points = controller.itinerary
        .where((stop) => stop.latitude != null && stop.longitude != null)
        .map((stop) => LatLng(stop.latitude!, stop.longitude!))
        .toList(growable: false);
    if (points.isEmpty) return const SizedBox.shrink();
    final markers = <Marker>{
      for (var index = 0; index < controller.itinerary.length; index++)
        if (controller.itinerary[index].latitude != null &&
            controller.itinerary[index].longitude != null)
          Marker(
            markerId: MarkerId(controller.itinerary[index].id),
            position: LatLng(
              controller.itinerary[index].latitude!,
              controller.itinerary[index].longitude!,
            ),
            infoWindow: InfoWindow(
              title: controller.itinerary[index].placeName,
              snippet:
                  controller.itinerary[index].status == StopStatus.completed
                  ? 'Completed'
                  : index == 0
                  ? 'First destination'
                  : 'Stop ${index + 1}',
            ),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              controller.itinerary[index].status == StopStatus.completed
                  ? BitmapDescriptor.hueGreen
                  : BitmapDescriptor.hueAzure,
            ),
          ),
    };
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 190,
        child: GoogleMap(
          initialCameraPosition: CameraPosition(
            target: points.first,
            zoom: 12.5,
          ),
          markers: markers,
          polylines: points.length < 2
              ? const {}
              : {
                  Polyline(
                    polylineId: const PolylineId('itinerary_preview'),
                    points: points,
                    width: 5,
                    color: AppColors.primary,
                  ),
                },
          mapToolbarEnabled: false,
          zoomControlsEnabled: true,
          zoomGesturesEnabled: true,
          scrollGesturesEnabled: true,
          rotateGesturesEnabled: true,
          tiltGesturesEnabled: true,
          gestureRecognizers: travelMapGestureRecognizers(),
          compassEnabled: false,
          myLocationButtonEnabled: false,
        ),
      ),
    );
  }
}

class _ItineraryStopCard extends StatelessWidget {
  const _ItineraryStopCard({
    required this.stop,
    required this.index,
    required this.canReorder,
    required this.placeSearchService,
    this.knownPhotoName,
    this.onRemove,
    this.onComplete,
  });

  final ItineraryStop stop;
  final int index;
  final bool canReorder;
  final TravelPlaceSearchService placeSearchService;
  final String? knownPhotoName;
  final VoidCallback? onRemove;
  final VoidCallback? onComplete;

  @override
  Widget build(BuildContext context) {
    final completed = stop.status == StopStatus.completed;
    final current = stop.status == StopStatus.current;
    final color = Colors.white;
    final border = completed
        ? const Color(0xFFA8DEB8)
        : current
        ? AppColors.primary
        : const Color(0xFFE6ECF7);
    final status = completed
        ? 'COMPLETED'
        : current
        ? 'NEXT STOP'
        : 'CONFIRMED';
    final card = AppPanel(
      color: color,
      borderColor: border,
      padding: const EdgeInsets.fromLTRB(11, 10, 13, 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              TravelPlacePhoto(
                key: Key('itinerary_photo_${stop.id}'),
                placeName: stop.placeName,
                knownPhotoName: knownPhotoName,
                placeSearchService: placeSearchService,
                width: 78,
                height: 82,
                borderRadius: 12,
              ),
              if (completed || current)
                Positioned(
                  left: -5,
                  bottom: -5,
                  child: CircleAvatar(
                    radius: 12,
                    backgroundColor: completed
                        ? AppColors.success
                        : AppColors.primary,
                    child: Icon(
                      completed
                          ? Icons.check_rounded
                          : Icons.navigation_rounded,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        stop.placeName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (onRemove != null)
                      IconButton(
                        tooltip: 'Remove from itinerary',
                        visualDensity: VisualDensity.compact,
                        onPressed: onRemove,
                        icon: const Icon(Icons.close_rounded, size: 19),
                      ),
                    if (canReorder && onRemove == null)
                      const Padding(
                        padding: EdgeInsets.only(left: 5),
                        child: Icon(
                          Icons.drag_indicator_rounded,
                          size: 20,
                          color: AppColors.secondaryText,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  status == 'NEXT STOP' ? 'Next stop • Confirmed' : status,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: completed ? AppColors.success : AppColors.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${stop.travelTimeFromPreviousMinutes} min travel  •  ${stop.travelDistanceFromPreviousKm.toStringAsFixed(1)} km',
                  style: const TextStyle(fontSize: 11),
                ),
                const SizedBox(height: 6),
                if (onComplete != null)
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: onComplete,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(128, 28),
                        padding: const EdgeInsets.symmetric(horizontal: 13),
                      ),
                      child: const Text('Mark completed'),
                    ),
                  )
                else
                  Text(
                    completed
                        ? 'Travel time recalculated for the next stop'
                        : index == 0
                        ? 'Initial destination · stays first'
                        : 'Confirmed by the group creator',
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
    );
    return canReorder
        ? ReorderableDelayedDragStartListener(index: index, child: card)
        : card;
  }
}
