import 'package:flutter/material.dart';

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
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        if (controller.itinerary.length > 1)
          Container(
            height: 39,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
                color: AppColors.successSurface,
                borderRadius: BorderRadius.circular(11)),
            child: const Row(
              children: [
                Icon(Icons.sync_rounded, color: AppColors.success, size: 19),
                SizedBox(width: 8),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Times recalculated after reorder',
                        style: TextStyle(fontSize: 11)),
                    Text('Prototype travel times update instantly',
                        style:
                            TextStyle(fontSize: 9, color: AppColors.success)),
                  ],
                ),
              ],
            ),
          ),
        if (controller.itinerary.length > 1) const SizedBox(height: 10),
        if (controller.isCreator && group.status == GroupStatus.waiting)
          const Text('⋮⋮  Drag cards to reorder the itinerary',
              style: TextStyle(fontSize: 11, color: AppColors.secondaryText)),
        const SizedBox(height: 10),
        if (controller.itinerary.isEmpty)
          const AppPanel(
            color: AppColors.paleBlue,
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Column(
                children: [
                  Icon(Icons.route_outlined,
                      size: 38, color: AppColors.primary),
                  SizedBox(height: 10),
                  Text('No confirmed stops yet',
                      style: TextStyle(fontSize: 16)),
                  Text('Confirm a suggestion before starting the group trip.'),
                ],
              ),
            ),
          )
        else
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: controller.itinerary.length,
            onReorderItem:
                group.status == GroupStatus.waiting && controller.isCreator
                    ? controller.reorderStops
                    : (_, __) {},
            itemBuilder: (context, index) {
              final stop = controller.itinerary[index];
              return Padding(
                key: ValueKey(stop.id),
                padding: const EdgeInsets.only(bottom: 10),
                child: _ItineraryStopCard(
                  stop: stop,
                  index: index,
                  canReorder: group.status == GroupStatus.waiting &&
                      controller.isCreator,
                  onComplete:
                      stop.status == StopStatus.current && controller.isCreator
                          ? () => controller.completeStop(stop)
                          : null,
                ),
              );
            },
          ),
        if (controller.itinerary.isNotEmpty) ...[
          const SizedBox(height: 4),
          if (group.status == GroupStatus.waiting && controller.isCreator)
            FilledButton(
                onPressed: () => _start(context),
                child: const Text('Start group itinerary'))
          else if (group.status == GroupStatus.active)
            FilledButton.icon(
              onPressed: () => _openMap(context),
              icon: const Icon(Icons.navigation_rounded),
              label: const Text('Open active route map'),
            )
          else if (group.status == GroupStatus.completed)
            const AppPanel(
              color: AppColors.successSurface,
              borderColor: Color(0xFFA8DEB8),
              child: Center(
                  child: Text('✓ Group itinerary completed',
                      style: TextStyle(color: AppColors.success))),
            ),
        ],
      ],
    );
  }

  Future<void> _start(BuildContext context) async {
    try {
      await controller.startItinerary();
      if (context.mounted) {
        await _openMap(context);
      }
    } on TravelGroupException catch (error) {
      if (context.mounted) {
        showTravelGroupMessage(context, error.message, error: true);
      }
    }
  }

  Future<void> _openMap(BuildContext context) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
          builder: (_) => ActiveItineraryMapScreen(controller: controller)),
    );
    await controller.refreshWorkspace();
  }
}

class _ItineraryStopCard extends StatelessWidget {
  const _ItineraryStopCard({
    required this.stop,
    required this.index,
    required this.canReorder,
    this.onComplete,
  });

  final ItineraryStop stop;
  final int index;
  final bool canReorder;
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
    return AppPanel(
      color: color,
      borderColor: border,
      padding: const EdgeInsets.fromLTRB(11, 9, 13, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (completed)
            const SizedBox(
                width: 26,
                child: Icon(Icons.check, color: AppColors.success, size: 22))
          else if (canReorder)
            ReorderableDragStartListener(
              index: index,
              child: const SizedBox(
                  width: 26,
                  child: Icon(Icons.drag_indicator,
                      color: AppColors.secondaryText, size: 21)),
            )
          else
            SizedBox(
                width: 26,
                child: Center(
                    child: Text('${index + 1}',
                        style: const TextStyle(color: AppColors.primary)))),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                        child: Text(stop.placeName,
                            style: const TextStyle(fontSize: 15))),
                    Container(
                      height: 22,
                      padding: const EdgeInsets.symmetric(horizontal: 15),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(
                            color: completed
                                ? AppColors.success
                                : AppColors.primary),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Text(status,
                          style: TextStyle(
                              fontSize: 9,
                              color: completed
                                  ? AppColors.success
                                  : AppColors.primary)),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                    '${stop.estimatedDurationMinutes} min duration  •  ${stop.travelTimeFromPreviousMinutes} min travel',
                    style: const TextStyle(fontSize: 11)),
                const SizedBox(height: 6),
                if (onComplete != null)
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: onComplete,
                      style: FilledButton.styleFrom(
                          minimumSize: const Size(128, 28),
                          padding: const EdgeInsets.symmetric(horizontal: 13)),
                      child: const Text('Mark completed'),
                    ),
                  )
                else
                  Text(
                    completed
                        ? 'Travel time recalculated for the next stop'
                        : index == 0
                            ? 'Starting point'
                            : 'Confirmed by the group creator',
                    style: const TextStyle(
                        fontSize: 10, color: AppColors.secondaryText),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
