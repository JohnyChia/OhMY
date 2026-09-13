import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../controllers/travel_group_controller.dart';
import '../models/travel_group_models.dart';
import '../widgets/travel_group_widgets.dart';
import 'active_itinerary_map_screen.dart';

class ItineraryBoard extends StatelessWidget {
  const ItineraryBoard({super.key, required this.controller});

  final TravelGroupController controller;

  @override
  Widget build(BuildContext context) {
    final group = controller.activeGroup!;
    final nextStop = controller.nextItineraryStop;
    return CustomScrollView(
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
                    if (controller.itinerary.length > 1)
                      Container(
                        height: 39,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
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
                            Column(
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
                          ],
                        ),
                      ),
                    if (controller.itinerary.length > 1)
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
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _ItineraryStopCard(
                        stop: stop,
                        index: index,
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
                    );
                  },
                ),
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
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
                          label: Text(
                            'Start navigation to ${nextStop.placeName}',
                          ),
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
          zoomControlsEnabled: false,
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
    this.onRemove,
    this.onComplete,
  });

  final ItineraryStop stop;
  final int index;
  final bool canReorder;
  final VoidCallback? onRemove;
  final VoidCallback? onComplete;

  @override
  Widget build(BuildContext context) {
    final completed = stop.status == StopStatus.completed;
    final current = stop.status == StopStatus.current;
    final color = completed
        ? AppColors.successSurface
        : current
        ? AppColors.surfaceBlue
        : index.isEven
        ? AppColors.surfaceLavender
        : AppColors.surfaceWarm;
    final border = completed
        ? const Color(0xFFA8DEB8)
        : current
        ? AppColors.primary
        : AppColors.border;
    final status = completed
        ? 'COMPLETED'
        : current
        ? 'NEXT STOP'
        : 'CONFIRMED';
    final card = AppPanel(
      color: color,
      borderColor: border,
      padding: const EdgeInsets.fromLTRB(11, 9, 13, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (completed)
            const SizedBox(
              width: 26,
              child: Icon(Icons.check, color: AppColors.success, size: 22),
            )
          else if (canReorder)
            const SizedBox(
              width: 26,
              child: Icon(
                Icons.drag_indicator,
                color: AppColors.secondaryText,
                size: 21,
              ),
            )
          else
            SizedBox(
              width: 26,
              child: Center(
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(color: AppColors.primary),
                ),
              ),
            ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        stop.placeName,
                        style: const TextStyle(fontSize: 15),
                      ),
                    ),
                    Container(
                      height: 22,
                      padding: const EdgeInsets.symmetric(horizontal: 15),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(
                          color: completed
                              ? AppColors.success
                              : AppColors.primary,
                        ),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(
                          fontSize: 9,
                          color: completed
                              ? AppColors.success
                              : AppColors.primary,
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
                  ],
                ),
                const SizedBox(height: 5),
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
