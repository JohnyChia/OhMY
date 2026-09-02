import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../controllers/travel_group_controller.dart';
import '../models/travel_group_models.dart';
import '../widgets/travel_group_widgets.dart';

class SuggestionBoard extends StatelessWidget {
  const SuggestionBoard({super.key, required this.controller});

  final TravelGroupController controller;

  static const nearbyPlaces = [
    NearbyPlace(
        name: 'Central Market',
        source: 'Attraction Directory',
        category: 'Cultural',
        distanceKm: 1.2,
        crowdLevel: 'Moderate',
        durationMinutes: 60,
        tags: ['Cultural', 'Heritage']),
    NearbyPlace(
        name: 'Kwai Chai Hong',
        source: 'Attraction Directory',
        category: 'Cultural',
        distanceKm: 1.3,
        crowdLevel: 'Moderate',
        durationMinutes: 45,
        tags: ['Cultural', 'Heritage']),
    NearbyPlace(
        name: 'River of Life',
        source: 'Community Discovery',
        category: 'Nature',
        distanceKm: .9,
        crowdLevel: 'Low',
        durationMinutes: 45,
        tags: ['Nature', 'Casual']),
  ];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            onPressed: () => _showPlaces(context),
            style: FilledButton.styleFrom(minimumSize: const Size(142, 36)),
            child: const Text('+ Suggest place'),
          ),
        ),
        const SizedBox(height: 8),
        const Text('Ranked by member votes  •  Highest first',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: AppColors.secondaryText)),
        const SizedBox(height: 10),
        const Text('Member suggestions', style: TextStyle(fontSize: 14)),
        const SizedBox(height: 10),
        if (controller.suggestions.isEmpty)
          const AppPanel(
              child: Center(
                  child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No suggestions yet.'))))
        else
          ...List.generate(controller.suggestions.length, (index) {
            final suggestion = controller.suggestions[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _SuggestionCard(
                  controller: controller,
                  suggestion: suggestion,
                  rank: index + 1),
            );
          }),
      ],
    );
  }

  Future<void> _showPlaces(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Suggest a nearby place',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            const Text('Mock results from the future Places integration.'),
            const SizedBox(height: 12),
            for (final place in nearbyPlaces)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(
                    backgroundColor: AppColors.surfaceBlue,
                    child:
                        Icon(Icons.place_outlined, color: AppColors.primary)),
                title: Text(place.name),
                subtitle: Text(
                    '${place.distanceKm} km · ${place.category} · ${place.crowdLevel} crowd'),
                trailing:
                    const Icon(Icons.add_circle, color: AppColors.primary),
                onTap: () async {
                  try {
                    await controller.addSuggestion(place);
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                  } on TravelGroupException catch (error) {
                    if (sheetContext.mounted) {
                      showTravelGroupMessage(sheetContext, error.message,
                          error: true);
                    }
                  }
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard(
      {required this.controller, required this.suggestion, required this.rank});

  final TravelGroupController controller;
  final GroupSuggestion suggestion;
  final int rank;

  @override
  Widget build(BuildContext context) {
    final upvoted = suggestion.upvoterIds.contains(controller.currentUser.id);
    final downvoted =
        suggestion.downvoterIds.contains(controller.currentUser.id);
    final color = switch (rank % 3) {
      1 => AppColors.surfaceBlue,
      2 => AppColors.surfaceLavender,
      _ => AppColors.surfaceWarm,
    };
    return AppPanel(
      color: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 15,
                backgroundColor: rank == 1 ? AppColors.primary : Colors.white,
                child: Text('#$rank',
                    style: TextStyle(
                        fontSize: 11,
                        color: rank == 1 ? Colors.white : AppColors.primary)),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(suggestion.placeName,
                        style: const TextStyle(fontSize: 16)),
                    Text(suggestion.source,
                        style: const TextStyle(
                            fontSize: 10, color: AppColors.secondaryText)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
              '${_duration(suggestion.durationMinutes)}  •  ${suggestion.distanceKm} km  •  ${suggestion.crowdLevel} crowd',
              style: const TextStyle(fontSize: 11)),
          const SizedBox(height: 7),
          Row(
            children: [
              AppPill(suggestion.tags.join('  •  '),
                  backgroundColor: Colors.white),
              const Spacer(),
              if (suggestion.isConfirmed)
                const Text('✓ CONFIRMED',
                    style: TextStyle(fontSize: 10, color: AppColors.success))
              else if (controller.isCreator)
                FilledButton(
                  onPressed: () => controller.confirmSuggestion(suggestion),
                  style: FilledButton.styleFrom(
                      minimumSize: const Size(112, 30),
                      padding: const EdgeInsets.symmetric(horizontal: 12)),
                  child: const Text('Confirm stop'),
                ),
            ],
          ),
          const SizedBox(height: 3),
          Row(
            children: [
              _VoteButton(
                  label: '▲ ${suggestion.upvoterIds.length}',
                  selected: upvoted,
                  onTap: () => controller.vote(suggestion, true)),
              const SizedBox(width: 4),
              _VoteButton(
                  label: '▼ ${suggestion.downvoterIds.length}',
                  selected: downvoted,
                  onTap: () => controller.vote(suggestion, false)),
              const SizedBox(width: 8),
              Text('Score ${suggestion.score}',
                  style: const TextStyle(
                      fontSize: 9, color: AppColors.secondaryText)),
            ],
          ),
        ],
      ),
    );
  }

  String _duration(int minutes) => minutes >= 60
      ? '${minutes ~/ 60} hr${minutes % 60 == 0 ? '' : ' ${minutes % 60} min'}'
      : '$minutes min';
}

class _VoteButton extends StatelessWidget {
  const _VoteButton(
      {required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 62,
        height: 25,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.white,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 11,
                color: selected ? Colors.white : AppColors.primary)),
      ),
    );
  }
}
