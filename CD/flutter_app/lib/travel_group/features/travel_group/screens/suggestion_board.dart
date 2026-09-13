import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../controllers/travel_group_controller.dart';
import '../models/travel_group_models.dart';
import '../services/travel_place_search_service.dart';
import '../widgets/travel_place_photo.dart';
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
        InkWell(
          key: const Key('suggest_place_search'),
          onTap: () => _showPlaces(context),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              children: [
                Icon(Icons.search_rounded, color: AppColors.primary),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Suggest a nearby place',
                    style: TextStyle(color: AppColors.secondaryText),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _SuggestionMap(controller: controller),
        const SizedBox(height: 14),
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
                placeSearchService: _placeSearch,
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
  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  List<NearbyPlace> _nearbyPlaces = const [];
  List<NearbyPlace> _places = const [];
  String? _error;
  bool _loading = true;
  bool _nearbyLoading = true;
  bool _showingSearchResults = false;
  int _requestId = 0;

  TravelGroup get _group => widget.controller.activeGroup!;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _nearbyLoading = true;
      _loading = true;
      _error = null;
    });
    final group = _group;
    final anchor = recommendationAnchorFor(group, widget.controller.itinerary);
    try {
      if (anchor == null) {
        throw const TravelGroupException(
          'This group has no destination coordinates to search around.',
          'no_destination_coordinates',
        );
      }
      final places = await widget.placeSearch.nearbySuggestions(
        latitude: anchor.latitude,
        longitude: anchor.longitude,
        destinationPlaceId: anchor.id,
        preferences: group.tags,
      );
      if (!mounted) return;
      setState(() {
        _nearbyPlaces = places;
        _nearbyLoading = false;
        if (!_showingSearchResults) {
          _places = places;
          _loading = false;
          if (places.isEmpty) {
            _error =
                'No Google Places suggestions matched this destination yet.';
          }
        }
      });
    } on TravelGroupException catch (error) {
      if (!mounted) return;
      setState(() {
        _nearbyLoading = false;
        if (!_showingSearchResults) {
          _loading = false;
          _error = error.message;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _nearbyLoading = false;
        if (!_showingSearchResults) {
          _loading = false;
          _error =
              'Could not reach the recommendation service. Is the backend running?';
        }
      });
    }
  }

  void _searchChanged(String value) {
    _searchDebounce?.cancel();
    final query = value.trim();
    final requestId = ++_requestId;
    if (query.length < 2) {
      setState(() {
        _showingSearchResults = false;
        _places = _nearbyPlaces;
        _loading = _nearbyLoading;
        _error = null;
      });
      return;
    }
    setState(() {
      _showingSearchResults = true;
      _loading = true;
      _error = null;
    });
    _searchDebounce = Timer(
      const Duration(milliseconds: 300),
      () => _runSearch(query, requestId),
    );
  }

  Future<void> _runSearch(String query, int requestId) async {
    final anchor = recommendationAnchorFor(_group, widget.controller.itinerary);
    if (anchor == null) {
      if (mounted && requestId == _requestId) {
        setState(() {
          _loading = false;
          _error = 'This group has no location to search around.';
        });
      }
      return;
    }
    try {
      final places = await widget.placeSearch.searchNearbyByText(
        query: query,
        latitude: anchor.latitude,
        longitude: anchor.longitude,
      );
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _places = places;
        _loading = false;
        _error = places.isEmpty
            ? 'No places found within 10 km of ${anchor.name}.'
            : null;
      });
    } on TravelGroupException catch (error) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _loading = false;
        _error = error.message;
      });
    } catch (_) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _loading = false;
        _error = 'Could not search Google Places. Is the backend running?';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final anchor = recommendationAnchorFor(_group, widget.controller.itinerary);
    return FractionallySizedBox(
      heightFactor: .82,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          4,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Suggest a nearby place',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'Recommended for this group near ${anchor?.name ?? _group.destination}.',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.secondaryText,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('nearby_place_search_field'),
              controller: _searchController,
              onChanged: _searchChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search another nearby place',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        onPressed: () {
                          _searchController.clear();
                          _searchChanged('');
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _showingSearchResults
                  ? 'Search results within 10 km'
                  : 'Nearby suggestions',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12),
                    ),
                    if (!_showingSearchResults) ...[
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _load,
                        child: const Text('Retry'),
                      ),
                    ],
                  ],
                ),
              )
            else
              Expanded(
                child: ListView(
                  children: [
                    for (final place in _places)
                      _NearbyPlaceCard(
                        place: place,
                        placeSearch: widget.placeSearch,
                        onAdd: () => _addPlace(place),
                      ),
                  ],
                ),
              ),
          ],
        ),
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

class _NearbyPlaceCard extends StatelessWidget {
  const _NearbyPlaceCard({
    required this.place,
    required this.placeSearch,
    required this.onAdd,
  });

  final NearbyPlace place;
  final TravelPlaceSearchService placeSearch;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: AppColors.surfaceBlue,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: AppColors.border),
        borderRadius: BorderRadius.circular(15),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onAdd,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PlaceThumbnail(
              photoName: place.photoName,
              placeSearch: placeSearch,
              width: double.infinity,
              height: 220,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 11, 8, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          place.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '${place.distanceKm.toStringAsFixed(1)} km  •  ${place.category}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.secondaryText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Add ${place.name}',
                    onPressed: onAdd,
                    icon: const Icon(
                      Icons.add_circle,
                      color: AppColors.primary,
                      size: 31,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaceThumbnail extends StatelessWidget {
  const _PlaceThumbnail({
    required this.photoName,
    required this.placeSearch,
    this.width = 104,
    this.height = 88,
  });

  final String? photoName;
  final TravelPlaceSearchService placeSearch;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final name = photoName;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        key: const Key('nearby_place_thumbnail'),
        width: width,
        height: height,
        child: name == null || name.isEmpty
            ? const ColoredBox(
                color: AppColors.surfaceBlue,
                child: Icon(Icons.place_outlined, color: AppColors.primary),
              )
            : Image.network(
                placeSearch.photoUrl(name),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const ColoredBox(
                  color: AppColors.surfaceBlue,
                  child: Icon(Icons.place_outlined, color: AppColors.primary),
                ),
              ),
      ),
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({
    required this.controller,
    required this.suggestion,
    required this.placeSearchService,
  });

  final TravelGroupController controller;
  final GroupSuggestion suggestion;
  final TravelPlaceSearchService placeSearchService;

  @override
  Widget build(BuildContext context) {
    final upvoted = suggestion.upvoterIds.contains(controller.currentUser.id);
    final downvoted = suggestion.downvoterIds.contains(
      controller.currentUser.id,
    );
    final estimatedTravelMinutes = math.max(
      1,
      (suggestion.distanceKm / 30 * 60).round(),
    );
    return AppPanel(
      color: Colors.white,
      padding: const EdgeInsets.all(10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TravelPlacePhoto(
            key: Key('suggestion_photo_${suggestion.id}'),
            placeName: suggestion.placeName,
            placeSearchService: placeSearchService,
            width: 112,
            height: 160,
            borderRadius: 10,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 160,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          suggestion.placeName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (controller.isCreator ||
                          suggestion.suggestedByUserId ==
                              controller.currentUser.id)
                        IconButton(
                          tooltip: 'Remove suggestion',
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints.tightFor(
                            width: 32,
                            height: 32,
                          ),
                          onPressed: () => _remove(context),
                          icon: const Icon(Icons.close_rounded, size: 19),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    suggestion.category,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.secondaryText,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${suggestion.distanceKm.toStringAsFixed(1)} km · $estimatedTravelMinutes min estimated',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.secondaryText,
                    ),
                  ),
                  const Spacer(),
                  if (suggestion.isConfirmed)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.successSurface,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_rounded,
                            size: 13,
                            color: AppColors.success,
                          ),
                          SizedBox(width: 3),
                          Text(
                            'In itinerary',
                            style: TextStyle(
                              fontSize: 9,
                              color: AppColors.success,
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (controller.isCreator)
                    FilledButton(
                      onPressed: () => controller.confirmSuggestion(suggestion),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(58, 28),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      child: const Text('Add'),
                    ),
                  const SizedBox(height: 5),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _VoteButton(
                        label: '▲ ${suggestion.upvoterIds.length}',
                        selected: upvoted,
                        onTap: () => controller.vote(suggestion, true),
                      ),
                      const SizedBox(width: 5),
                      _VoteButton(
                        label: '▼ ${suggestion.downvoterIds.length}',
                        selected: downvoted,
                        onTap: () => controller.vote(suggestion, false),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 44,
                        child: Text(
                          'Score ${suggestion.score}',
                          style: const TextStyle(
                            fontSize: 9,
                            color: AppColors.secondaryText,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

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

class _SuggestionMap extends StatelessWidget {
  const _SuggestionMap({required this.controller});

  final TravelGroupController controller;

  @override
  Widget build(BuildContext context) {
    final group = controller.activeGroup!;
    final latitude = group.destinationLatitude;
    final longitude = group.destinationLongitude;
    if (latitude == null || longitude == null) return const SizedBox.shrink();
    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('initial_destination'),
        position: LatLng(latitude, longitude),
        infoWindow: InfoWindow(title: group.destination),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
      ),
      for (final suggestion in controller.suggestions)
        if (suggestion.latitude != null && suggestion.longitude != null)
          Marker(
            markerId: MarkerId(suggestion.id),
            position: LatLng(suggestion.latitude!, suggestion.longitude!),
            infoWindow: InfoWindow(title: suggestion.placeName),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              suggestion.isConfirmed
                  ? BitmapDescriptor.hueGreen
                  : BitmapDescriptor.hueViolet,
            ),
          ),
    };
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 190,
        child: GoogleMap(
          initialCameraPosition: CameraPosition(
            target: LatLng(latitude, longitude),
            zoom: 12.8,
          ),
          markers: markers,
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
