import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../controllers/travel_group_controller.dart';
import '../models/travel_group_models.dart';
import '../services/travel_place_search_service.dart';
import '../widgets/travel_group_widgets.dart';

class SuggestionBoard extends StatefulWidget {
  const SuggestionBoard({
    super.key,
    required this.controller,
    this.placeSearchService,
  });

  final TravelGroupController controller;
  final TravelPlaceSearchService? placeSearchService;

  @override
  State<SuggestionBoard> createState() => _SuggestionBoardState();
}

class _SuggestionBoardState extends State<SuggestionBoard> {
  late final TravelPlaceSearchService _placeSearch;
  late final bool _ownsPlaceSearch;

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
    final controller = widget.controller;
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
        const Text(
          'Ranked by member votes  •  Highest first',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: AppColors.secondaryText),
        ),
        const SizedBox(height: 10),
        const Text('Member suggestions', style: TextStyle(fontSize: 14)),
        const SizedBox(height: 10),
        if (controller.suggestions.isEmpty)
          const AppPanel(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No suggestions yet.'),
              ),
            ),
          )
        else
          ...List.generate(controller.suggestions.length, (index) {
            final suggestion = controller.suggestions[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _SuggestionCard(
                controller: controller,
                suggestion: suggestion,
                rank: index + 1,
              ),
            );
          }),
      ],
    );
  }

  Future<void> _showPlaces(BuildContext context) async {
    final group = widget.controller.activeGroup;
    if (group == null) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (sheetContext) => _NearbySuggestionsSheet(
        placeSearch: _placeSearch,
        controller: widget.controller,
      ),
    );
  }
}

class _NearbySuggestionsSheet extends StatefulWidget {
  const _NearbySuggestionsSheet({
    required this.placeSearch,
    required this.controller,
  });

  final TravelPlaceSearchService placeSearch;
  final TravelGroupController controller;

  @override
  State<_NearbySuggestionsSheet> createState() =>
      _NearbySuggestionsSheetState();
}

class _NearbySuggestionsSheetState extends State<_NearbySuggestionsSheet> {
  List<NearbyPlace> _places = const [];
  String? _error;
  bool _loading = true;

  TravelGroup get _group => widget.controller.activeGroup!;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final group = _group;
    final latitude = group.destinationLatitude;
    final longitude = group.destinationLongitude;
    try {
      if (latitude == null || longitude == null) {
        throw const TravelGroupException(
          'This group has no destination coordinates to search around.',
          'no_destination_coordinates',
        );
      }
      final places = await widget.placeSearch.nearbySuggestions(
        latitude: latitude,
        longitude: longitude,
        destinationPlaceId: group.destinationPlaceId,
        preferences: group.tags,
      );
      if (!mounted) return;
      setState(() {
        _places = places;
        _loading = false;
        if (places.isEmpty) {
          _error = 'No Google Places suggestions matched this destination yet.';
        }
      });
    } on TravelGroupException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error =
            'Could not reach the recommendation service. Is the backend running?';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Suggest a nearby place',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            'Live Google Places recommendations near ${_group.destination}.',
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.secondaryText,
            ),
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(28),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _load, child: const Text('Retry')),
                ],
              ),
            )
          else
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final place in _places)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const CircleAvatar(
                        backgroundColor: AppColors.surfaceBlue,
                        child: Icon(
                          Icons.place_outlined,
                          color: AppColors.primary,
                        ),
                      ),
                      title: Text(place.name),
                      subtitle: Text(
                        '${place.distanceKm.toStringAsFixed(1)} km · ${place.category}',
                      ),
                      trailing: const Icon(
                        Icons.add_circle,
                        color: AppColors.primary,
                      ),
                      onTap: () => _addPlace(place),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _addPlace(NearbyPlace place) async {
    try {
      await widget.controller.addSuggestion(place);
    } on TravelGroupException catch (error) {
      if (!mounted) return;
      showTravelGroupMessage(context, error.message, error: true);
      return;
    }
    if (!mounted) return;
    Navigator.pop(context);
  }
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({
    required this.controller,
    required this.suggestion,
    required this.rank,
  });

  final TravelGroupController controller;
  final GroupSuggestion suggestion;
  final int rank;

  @override
  Widget build(BuildContext context) {
    final upvoted = suggestion.upvoterIds.contains(controller.currentUser.id);
    final downvoted = suggestion.downvoterIds.contains(
      controller.currentUser.id,
    );
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
                child: Text(
                  '#$rank',
                  style: TextStyle(
                    fontSize: 11,
                    color: rank == 1 ? Colors.white : AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      suggestion.placeName,
                      style: const TextStyle(fontSize: 16),
                    ),
                    Text(
                      suggestion.source,
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
              if (controller.isCreator ||
                  suggestion.suggestedByUserId == controller.currentUser.id)
                IconButton(
                  tooltip: 'Remove suggestion',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _remove(context),
                  icon: const Icon(Icons.close_rounded, size: 20),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${_duration(suggestion.durationMinutes)}  •  ${suggestion.distanceKm} km  •  ${suggestion.crowdLevel} crowd',
            style: const TextStyle(fontSize: 11),
          ),
          const SizedBox(height: 7),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              suggestion.tags.join('  •  '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.secondaryText,
              ),
            ),
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              _VoteButton(
                label: '▲ ${suggestion.upvoterIds.length}',
                selected: upvoted,
                onTap: () => controller.vote(suggestion, true),
              ),
              const SizedBox(width: 4),
              _VoteButton(
                label: '▼ ${suggestion.downvoterIds.length}',
                selected: downvoted,
                onTap: () => controller.vote(suggestion, false),
              ),
              const SizedBox(width: 8),
              Text(
                'Score ${suggestion.score}',
                style: const TextStyle(
                  fontSize: 9,
                  color: AppColors.secondaryText,
                ),
              ),
            ],
          ),
          if (suggestion.isConfirmed || controller.isCreator) ...[
            const SizedBox(height: 7),
            Align(
              alignment: Alignment.centerRight,
              child: suggestion.isConfirmed
                  ? const Text(
                      '✓ CONFIRMED',
                      style: TextStyle(fontSize: 10, color: AppColors.success),
                    )
                  : FilledButton(
                      onPressed: () => controller.confirmSuggestion(suggestion),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(96, 30),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      child: const Text('Confirm'),
                    ),
            ),
          ],
        ],
      ),
    );
  }

  String _duration(int minutes) => minutes >= 60
      ? '${minutes ~/ 60} hr${minutes % 60 == 0 ? '' : ' ${minutes % 60} min'}'
      : '$minutes min';

  Future<void> _remove(BuildContext context) async {
    try {
      await controller.removeSuggestion(suggestion);
    } on TravelGroupException catch (error) {
      if (context.mounted) {
        showTravelGroupMessage(context, error.message, error: true);
      }
    }
  }
}

class _VoteButton extends StatelessWidget {
  const _VoteButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

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
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: selected ? Colors.white : AppColors.primary,
          ),
        ),
      ),
    );
  }
}
