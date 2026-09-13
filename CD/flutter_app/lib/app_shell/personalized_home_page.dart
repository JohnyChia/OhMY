import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:community_discovery/community_discovery.dart';

import '../shared/widgets/wau_loading_indicator.dart';
import '../shared/utils/duration_format.dart';
import '../shared/utils/place_description.dart';
import '../user_management/services/traveler_profile_service.dart';
import '../user_management/services/saved_location_service.dart';

typedef OpenSoloPlace = void Function(Map<String, dynamic>? recommendation);

class PersonalizedHomePage extends StatefulWidget {
  const PersonalizedHomePage({
    super.key,
    required this.communityController,
    required this.onOpenSoloMap,
    required this.onOpenCommunity,
    required this.onOpenPost,
  });

  final CommunityController communityController;
  final OpenSoloPlace onOpenSoloMap;
  final VoidCallback onOpenCommunity;
  final ValueChanged<CommunityPost> onOpenPost;

  @override
  State<PersonalizedHomePage> createState() => _PersonalizedHomePageState();
}

class _PersonalizedHomePageState extends State<PersonalizedHomePage>
    with WidgetsBindingObserver {
  static const _backend = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'http://127.0.0.1:3000',
  );

  List<Map<String, dynamic>> _places = const [];
  final Set<String> _bookmarkedPlaceIds = {};
  bool _loadingPlaces = true;
  int _loadGeneration = 0;
  String _lastPreferenceKey = '';
  Timer? _placeRetryTimer;
  int _placeRetryAttempt = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lastPreferenceKey = _preferenceKey(currentTravelerPreferences.value);
    currentTravelerPreferences.addListener(_preferencesChanged);
    savedLocationService.changes.addListener(_savedLocationsChanged);
    unawaited(_loadSavedLocations());
    unawaited(_loadPlaces());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          widget.communityController.posts.isNotEmpty ||
          widget.communityController.isLoading) {
        return;
      }
      unawaited(widget.communityController.loadPosts());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _placeRetryTimer?.cancel();
    currentTravelerPreferences.removeListener(_preferencesChanged);
    savedLocationService.changes.removeListener(_savedLocationsChanged);
    super.dispose();
  }

  Future<void> _loadSavedLocations() async {
    try {
      await savedLocationService.fetch(force: true);
      _savedLocationsChanged();
    } on SavedLocationFailure {
      // The bookmark action will show an error if saving is requested.
    }
  }

  void _savedLocationsChanged() {
    if (!mounted) return;
    setState(() {
      _bookmarkedPlaceIds
        ..clear()
        ..addAll(
          savedLocationService.cached
              .map((location) => location.googlePlaceId)
              .whereType<String>(),
        );
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _places.isEmpty) {
      _placeRetryAttempt = 0;
      unawaited(_loadPlaces());
    }
  }

  void _preferencesChanged() {
    final key = _preferenceKey(currentTravelerPreferences.value);
    if (key == _lastPreferenceKey) return;
    _lastPreferenceKey = key;
    unawaited(_loadPlaces());
  }

  String _preferenceKey(List<String> values) {
    final normalized =
        values.map((value) => value.trim().toLowerCase()).toList()..sort();
    return normalized.join('|');
  }

  Future<void> _loadPlaces() async {
    _placeRetryTimer?.cancel();
    final generation = ++_loadGeneration;
    if (mounted) setState(() => _loadingPlaces = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw Exception('Location services are disabled.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('Location permission is required.');
      }

      Position? location;
      try {
        location = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 20),
          ),
        );
      } catch (_) {
        location = await Geolocator.getLastKnownPosition();
      }
      if (location == null) throw Exception('Current location is unavailable.');

      // Use the same compulsory, freshly fetched profile preferences as the
      // working Nearby Matches action on the Solo Trip map.
      final preferences = await TravelerProfileService()
          .requireCurrentPreferences();
      _lastPreferenceKey = _preferenceKey(preferences);

      final response = await http
          .post(
            Uri.parse('$_backend/api/recommendations/nearby-tagged'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'latitude': location.latitude,
              'longitude': location.longitude,
              'mode': 'preferences',
              'preferences': preferences,
            }),
          )
          .timeout(const Duration(seconds: 120));

      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          payload['details'] ??
              payload['error'] ??
              'Nearby recommendations are unavailable.',
        );
      }

      final ranked = List<Map<String, dynamic>>.from(
        payload['matchedPlaces'] ?? const [],
      ).take(10).toList(growable: false);
      if (!mounted || generation != _loadGeneration) return;
      _placeRetryAttempt = 0;
      setState(() => _places = ranked);
    } catch (_) {
      // Home can be created while the local backend bridge, GPS, or auth
      // session is still warming up. Retry a few times instead of leaving the
      // page permanently empty after that first transient failure.
      if (mounted && generation == _loadGeneration && _places.isEmpty) {
        _schedulePlaceRetry();
      }
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() => _loadingPlaces = false);
      }
    }
  }

  void _schedulePlaceRetry() {
    if (_placeRetryAttempt >= 3 || _placeRetryTimer?.isActive == true) return;
    _placeRetryAttempt++;
    _placeRetryTimer = Timer(Duration(seconds: 2 * _placeRetryAttempt), () {
      if (mounted && _places.isEmpty) unawaited(_loadPlaces());
    });
  }

  String? _photoName(Map<String, dynamic> place) {
    final primary = (place['photo'] as Map?)?['name']?.toString().trim();
    if (primary != null && primary.isNotEmpty) return primary;
    final photos = place['photos'];
    if (photos is! List || photos.isEmpty || photos.first is! Map) return null;
    final first = (photos.first as Map)['name']?.toString().trim();
    return first == null || first.isEmpty ? null : first;
  }

  Map<String, dynamic> _place(Map<String, dynamic> item) =>
      Map<String, dynamic>.from(item['place'] as Map? ?? const {});

  String _name(Map<String, dynamic> item) =>
      (_place(item)['displayName'] as Map?)?['text']?.toString() ??
      'Nearby attraction';

  String _description(Map<String, dynamic> item) {
    final place = _place(item);
    final description = usablePlaceDescription(place['description']);
    if (description != null) return description;
    final type = place['primaryTypeDisplayName']?.toString().trim() ?? '';
    final address = place['formattedAddress']?.toString().trim() ?? '';
    if (type.isNotEmpty && address.isNotEmpty) return '$type • $address';
    if (address.isNotEmpty) return address;
    return 'A personalised place matching your travel preferences.';
  }

  String? _photoUrl(Map<String, dynamic> item) {
    final name = _photoName(_place(item));
    if (name == null || name.isEmpty) return null;
    return '$_backend/api/places/photo?name=${Uri.encodeQueryComponent(name)}';
  }

  String _distance(Map<String, dynamic> item) {
    final place = _place(item);
    final value = place['routeDistanceKm'] ?? place['distanceKm'];
    return value is num ? '${value.toStringAsFixed(1)} km' : '-- km';
  }

  String _eta(Map<String, dynamic> item) {
    final value = _place(item)['etaMinutes'];
    return value is num ? formatTravelDuration(value.round()) : '-- min';
  }

  List<String> _tags(Map<String, dynamic> item) {
    final values = <dynamic>[
      ...?item['matchedPreferences'] as List?,
      ...?(item['ranking'] as Map?)?['matchingTags'] as List?,
      ...?(item['analysis'] as Map?)?['culturalTags'] as List?,
      ...?(item['analysis'] as Map?)?['generalTags'] as List?,
    ];
    final seen = <String>{};
    return values
        .map((value) => value.toString().trim())
        .where((value) => value.isNotEmpty && seen.add(value.toLowerCase()))
        .take(3)
        .toList(growable: false);
  }

  Future<void> _togglePlaceBookmark(Map<String, dynamic> item) async {
    try {
      await savedLocationService.toggle(item);
    } on SavedLocationFailure catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final featured = _places.isEmpty ? null : _places.first;
    // The featured recommendation can also remain discoverable in the nearby
    // carousel, especially when strict cultural evidence yields few matches.
    final nearby = _places;
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFD),
      body: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([
            _loadPlaces(),
            widget.communityController.loadPosts(),
          ]);
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: _FeaturedPlace(
                item: featured,
                loading: _loadingPlaces,
                backend: _backend,
                name: featured == null ? null : _name(featured),
                description: featured == null ? null : _description(featured),
                photoUrl: featured == null ? null : _photoUrl(featured),
                tags: featured == null ? const [] : _tags(featured),
                onSearchSelected: widget.onOpenSoloMap,
                onExplore: featured == null
                    ? () => widget.onOpenSoloMap(null)
                    : () => widget.onOpenSoloMap(featured),
              ),
            ),
            SliverToBoxAdapter(
              child: _PlacesNearYou(
                places: nearby,
                loading: _loadingPlaces,
                nameOf: _name,
                photoOf: _photoUrl,
                distanceOf: _distance,
                etaOf: _eta,
                tagsOf: _tags,
                bookmarkedIds: _bookmarkedPlaceIds,
                placeOf: _place,
                onOpen: (item) => widget.onOpenSoloMap(item),
                onBookmark: (item) => unawaited(_togglePlaceBookmark(item)),
              ),
            ),
            SliverToBoxAdapter(
              child: _CommunityPreview(
                controller: widget.communityController,
                onSeeMore: widget.onOpenCommunity,
                onOpenPost: widget.onOpenPost,
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }
}

class _InlineHomeSearch extends StatefulWidget {
  const _InlineHomeSearch({required this.backend, required this.onSelected});

  final String backend;
  final ValueChanged<Map<String, dynamic>> onSelected;

  @override
  State<_InlineHomeSearch> createState() => _InlineHomeSearchState();
}

class _InlineHomeSearchState extends State<_InlineHomeSearch> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _fieldKey = GlobalKey();
  final _layerLink = LayerLink();
  final _tapGroup = Object();
  final _overlayController = OverlayPortalController();
  Timer? _debounce;
  List<Map<String, dynamic>> _results = const [];
  bool _searching = false;
  bool _selecting = false;
  int _requestId = 0;
  String? _message;
  double _fieldWidth = 0;
  bool _dropdownWanted = false;

  void _showDropdown() {
    _dropdownWanted = true;
    if (!_overlayController.isShowing) _overlayController.show();
  }

  void _dismissDropdown() {
    _dropdownWanted = false;
    _focusNode.unfocus();
    if (_overlayController.isShowing) _overlayController.hide();
  }

  void _refreshDropdown() {
    if (_dropdownWanted && !_overlayController.isShowing) {
      _overlayController.show();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _changed(String value) {
    _debounce?.cancel();
    final query = value.trim();
    final request = ++_requestId;
    if (query.isEmpty) {
      setState(() {
        _results = const [];
        _message = null;
        _searching = false;
      });
      _dismissDropdown();
      return;
    }
    setState(() {
      _searching = true;
      _message = null;
    });
    _showDropdown();
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => unawaited(_search(query, request)),
    );
  }

  Future<void> _search(String query, int request) async {
    setState(() {
      _searching = true;
      _message = null;
    });
    try {
      final response = await http
          .post(
            Uri.parse('${widget.backend}/api/places/search'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'query': query}),
          )
          .timeout(const Duration(seconds: 30));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(data['error'] ?? 'Google Places search failed.');
      }
      if (!mounted || request != _requestId) return;
      final results = List<Map<String, dynamic>>.from(
        data['places'] ?? const [],
      );
      setState(() {
        _results = results;
        _message = results.isEmpty
            ? 'No Malaysian areas or places found.'
            : null;
      });
      _refreshDropdown();
    } catch (error) {
      if (!mounted || request != _requestId) return;
      setState(() {
        _results = const [];
        _message = error.toString().replaceFirst('Exception: ', '');
      });
      _refreshDropdown();
    } finally {
      if (mounted && request == _requestId) {
        setState(() => _searching = false);
      }
    }
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final response = await http
        .post(
          Uri.parse('${widget.backend}$path'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 60));
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(data['error'] ?? 'Unable to load this place.');
    }
    return data;
  }

  Future<void> _select(Map<String, dynamic> result) async {
    final placeId = result['id']?.toString();
    if (placeId == null || placeId.isEmpty || _selecting) return;
    if (result['isArea'] == true) {
      _dismissDropdown();
      widget.onSelected({
        'place': Map<String, dynamic>.from(result),
        'analysis': const <String, dynamic>{
          'generalTags': <String>[],
          'culturalTags': <String>[],
        },
        'areaSelection': true,
      });
      return;
    }
    setState(() {
      _selecting = true;
      _message = 'Loading place details…';
    });
    try {
      Map<String, dynamic> item;
      try {
        item = await _post('/api/places/analyze', {'placeId': placeId});
      } catch (_) {
        item = await _post('/api/places/details', {'placeId': placeId});
        item['analysis'] = const <String, dynamic>{
          'generalTags': <String>[],
          'culturalTags': <String>[],
        };
      }
      if (mounted) {
        _dismissDropdown();
        widget.onSelected(item);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = error.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      if (mounted) setState(() => _selecting = false);
    }
  }

  Widget _dropdown() {
    final visibleItems = _results.length.clamp(1, 4);
    final height = _results.isNotEmpty
        ? visibleItems * 68.0 + (_searching || _selecting ? 2 : 0)
        : 54.0;
    final renderBox = _fieldKey.currentContext?.findRenderObject();
    final targetLeft = renderBox is RenderBox
        ? renderBox.localToGlobal(Offset.zero).dx
        : 0.0;
    final availableWidth = MediaQuery.sizeOf(context).width - targetLeft - 12;
    final dropdownWidth = availableWidth > 0 && availableWidth < _fieldWidth
        ? availableWidth
        : _fieldWidth;
    return CompositedTransformFollower(
      link: _layerLink,
      showWhenUnlinked: false,
      targetAnchor: Alignment.bottomLeft,
      followerAnchor: Alignment.topLeft,
      offset: Offset.zero,
      child: UnconstrainedBox(
        alignment: Alignment.topLeft,
        child: TapRegion(
          groupId: _tapGroup,
          child: SizedBox(
            key: const ValueKey('home-search-dropdown'),
            width: dropdownWidth,
            height: height.clamp(54.0, 274.0),
            child: Material(
              color: Colors.white,
              elevation: 10,
              shadowColor: Colors.black38,
              clipBehavior: Clip.antiAlias,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10),
                bottom: Radius.circular(20),
              ),
              child: Column(
                children: [
                  if (_searching || _selecting)
                    const LinearProgressIndicator(minHeight: 2),
                  if (_message != null)
                    Expanded(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: Text(
                            _message!,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Color(0xFF687184)),
                          ),
                        ),
                      ),
                    )
                  else if (_results.isEmpty)
                    const Expanded(
                      child: Center(
                        child: Text(
                          'Searching...',
                          style: TextStyle(color: Color(0xFF687184)),
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.separated(
                        padding: EdgeInsets.zero,
                        itemCount: _results.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (_, index) {
                          final place = _results[index];
                          final name =
                              (place['displayName'] as Map?)?['text']
                                  ?.toString() ??
                              'Place';
                          return SizedBox(
                            height: 68,
                            child: ListTile(
                              enabled: !_selecting,
                              dense: true,
                              leading: Icon(
                                place['isArea'] == true
                                    ? Icons.map_outlined
                                    : Icons.location_on_outlined,
                                color: const Color(0xFF3266CC),
                              ),
                              title: Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                place['formattedAddress']?.toString() ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => unawaited(_select(place)),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      _fieldWidth = constraints.maxWidth;
      return TapRegion(
        groupId: _tapGroup,
        onTapOutside: (_) => _dismissDropdown(),
        child: CompositedTransformTarget(
          key: _fieldKey,
          link: _layerLink,
          child: OverlayPortal(
            controller: _overlayController,
            overlayChildBuilder: (_) => _dropdown(),
            child: Material(
              color: const Color(0xFFF8F6FB),
              elevation: 3,
              borderRadius: BorderRadius.circular(28),
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                height: 54,
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  enabled: !_selecting,
                  onTap: () {
                    if (_controller.text.trim().isNotEmpty) _showDropdown();
                  },
                  onChanged: _changed,
                  onSubmitted: (value) {
                    _debounce?.cancel();
                    final query = value.trim();
                    if (query.isNotEmpty) {
                      _showDropdown();
                      unawaited(_search(query, ++_requestId));
                    }
                  },
                  decoration: InputDecoration(
                    hintText: 'Search Attractions ...',
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.fromLTRB(17, 16, 4, 14),
                    suffixIcon: _controller.text.isEmpty
                        ? const Icon(Icons.search_rounded, size: 24)
                        : IconButton(
                            tooltip: 'Clear search',
                            onPressed: () {
                              _controller.clear();
                              _changed('');
                              _focusNode.requestFocus();
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _FeaturedPlace extends StatelessWidget {
  const _FeaturedPlace({
    required this.item,
    required this.loading,
    required this.backend,
    required this.name,
    required this.description,
    required this.photoUrl,
    required this.tags,
    required this.onSearchSelected,
    required this.onExplore,
  });

  final Map<String, dynamic>? item;
  final bool loading;
  final String backend;
  final String? name;
  final String? description;
  final String? photoUrl;
  final List<String> tags;
  final ValueChanged<Map<String, dynamic>> onSearchSelected;
  final VoidCallback onExplore;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(26)),
      child: SizedBox(
        height: 330 + top,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _PlaceImage(url: photoUrl),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x33000000),
                    Colors.transparent,
                    Color(0xE6000000),
                  ],
                  stops: [0, .36, 1],
                ),
              ),
            ),
            Positioned(
              top: top + 12,
              left: 18,
              right: 18,
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: const [
                        BoxShadow(color: Colors.black26, blurRadius: 12),
                      ],
                    ),
                    child: Image.asset(
                      'assets/images/branding/ohmy_icon.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _InlineHomeSearch(
                      backend: backend,
                      onSelected: onSearchSelected,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 24,
              right: 24,
              bottom: 22,
              child: loading
                  ? const Center(child: WauLoadingIndicator(size: 52))
                  : item == null
                  ? _EmptyFeatured(onExplore: onExplore)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'PERSONALISED FEATURED PLACE',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.1,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          name!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            height: 1.04,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          description!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: Wrap(
                                spacing: 6,
                                runSpacing: 5,
                                children: tags
                                    .take(2)
                                    .map(
                                      (tag) => _TagChip(label: tag, dark: true),
                                    )
                                    .toList(),
                              ),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.icon(
                              onPressed: onExplore,
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.white.withValues(
                                  alpha: .22,
                                ),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 17,
                                  vertical: 12,
                                ),
                              ),
                              iconAlignment: IconAlignment.end,
                              icon: const Icon(Icons.arrow_forward_rounded),
                              label: const Text('Explore'),
                            ),
                          ],
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

class _EmptyFeatured extends StatelessWidget {
  const _EmptyFeatured({required this.onExplore});
  final VoidCallback onExplore;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'DISCOVER MALAYSIA',
        style: TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
        ),
      ),
      const SizedBox(height: 8),
      const Text(
        'Find a place matched to you',
        style: TextStyle(
          color: Colors.white,
          fontSize: 25,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 7),
      const Text(
        'Enable location and refresh to discover attractions within 10 km.',
        style: TextStyle(color: Colors.white, height: 1.35),
      ),
      const SizedBox(height: 12),
      FilledButton(onPressed: onExplore, child: const Text('Explore map')),
    ],
  );
}

class _PlacesNearYou extends StatelessWidget {
  const _PlacesNearYou({
    required this.places,
    required this.loading,
    required this.nameOf,
    required this.photoOf,
    required this.distanceOf,
    required this.etaOf,
    required this.tagsOf,
    required this.bookmarkedIds,
    required this.placeOf,
    required this.onOpen,
    required this.onBookmark,
  });

  final List<Map<String, dynamic>> places;
  final bool loading;
  final String Function(Map<String, dynamic>) nameOf;
  final String? Function(Map<String, dynamic>) photoOf;
  final String Function(Map<String, dynamic>) distanceOf;
  final String Function(Map<String, dynamic>) etaOf;
  final List<String> Function(Map<String, dynamic>) tagsOf;
  final Set<String> bookmarkedIds;
  final Map<String, dynamic> Function(Map<String, dynamic>) placeOf;
  final ValueChanged<Map<String, dynamic>> onOpen;
  final ValueChanged<Map<String, dynamic>> onBookmark;

  @override
  Widget build(BuildContext context) {
    final width = (MediaQuery.sizeOf(context).width - 60) / 2.15;
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Places Near You',
                    style: TextStyle(
                      color: Color(0xFF123A78),
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (places.length > 2)
                  const Text(
                    'Swipe for more  →',
                    style: TextStyle(color: Color(0xFF687184), fontSize: 12),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (loading)
            const SizedBox(
              height: 220,
              child: Center(child: WauLoadingIndicator(size: 46)),
            )
          else if (places.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 26),
              child: Text(
                'No preference-matched attractions were found nearby.',
                style: TextStyle(color: Color(0xFF687184)),
              ),
            )
          else
            SizedBox(
              height: 226,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                scrollDirection: Axis.horizontal,
                itemCount: places.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final item = places[index];
                  final id = placeOf(item)['id']?.toString() ?? '';
                  return _NearbyPlaceCard(
                    width: width,
                    name: nameOf(item),
                    photoUrl: photoOf(item),
                    distance: distanceOf(item),
                    eta: etaOf(item),
                    tags: tagsOf(item),
                    bookmarked: bookmarkedIds.contains(id),
                    onTap: () => onOpen(item),
                    onBookmark: () => onBookmark(item),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _NearbyPlaceCard extends StatelessWidget {
  const _NearbyPlaceCard({
    required this.width,
    required this.name,
    required this.photoUrl,
    required this.distance,
    required this.eta,
    required this.tags,
    required this.bookmarked,
    required this.onTap,
    required this.onBookmark,
  });

  final double width;
  final String name;
  final String? photoUrl;
  final String distance;
  final String eta;
  final List<String> tags;
  final bool bookmarked;
  final VoidCallback onTap;
  final VoidCallback onBookmark;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Card(
      margin: EdgeInsets.zero,
      elevation: 1,
      shadowColor: const Color(0x220D2F69),
      color: Colors.white.withValues(alpha: .94),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: Color(0xFFB8D1FA), width: 1.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 105,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _PlaceImage(url: photoUrl),
                  Positioned(
                    top: 5,
                    right: 5,
                    child: IconButton.filled(
                      visualDensity: VisualDensity.compact,
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black45,
                        foregroundColor: Colors.white,
                      ),
                      tooltip: bookmarked ? 'Remove bookmark' : 'Bookmark',
                      onPressed: onBookmark,
                      icon: Icon(
                        bookmarked
                            ? Icons.bookmark_rounded
                            : Icons.bookmark_border_rounded,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 9, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF123A78),
                        fontSize: 13,
                        height: 1.1,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 24,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: tags.take(2).length,
                        separatorBuilder: (_, _) => const SizedBox(width: 4),
                        itemBuilder: (_, index) => _TagChip(label: tags[index]),
                      ),
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        const Icon(Icons.location_on_outlined, size: 15),
                        const SizedBox(width: 2),
                        Flexible(
                          child: Text(
                            distance,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 10),
                          ),
                        ),
                        const SizedBox(width: 7),
                        const SizedBox(
                          height: 13,
                          child: VerticalDivider(width: 1),
                        ),
                        const SizedBox(width: 7),
                        const Icon(Icons.directions_car_outlined, size: 15),
                        const SizedBox(width: 2),
                        Flexible(
                          child: Text(
                            eta,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 10),
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
      ),
    ),
  );
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.label, this.dark = false});
  final String label;
  final bool dark;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(maxWidth: 100),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: dark
          ? Colors.black.withValues(alpha: .28)
          : const Color(0xFFEAF1FF),
      borderRadius: BorderRadius.circular(999),
      border: dark
          ? Border.all(color: Colors.white38)
          : Border.all(color: const Color(0xFFB8D1FA)),
    ),
    child: Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: dark ? Colors.white : const Color(0xFF315FAE),
        fontSize: 9,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class _CommunityPreview extends StatelessWidget {
  const _CommunityPreview({
    required this.controller,
    required this.onSeeMore,
    required this.onOpenPost,
  });

  final CommunityController controller;
  final VoidCallback onSeeMore;
  final ValueChanged<CommunityPost> onOpenPost;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final posts = controller.posts.take(4).toList(growable: false);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Discover Posts by Other Travellers',
                    maxLines: 2,
                    style: TextStyle(
                      color: Color(0xFF123A78),
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: onSeeMore,
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF28599F),
                  ),
                  iconAlignment: IconAlignment.end,
                  icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                  label: const Text('See More'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (controller.isLoading && posts.isEmpty)
            const SizedBox(
              height: 190,
              child: Center(child: WauLoadingIndicator(size: 46)),
            )
          else if (posts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: InkWell(
                onTap: onSeeMore,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .94),
                    border: Border.all(color: const Color(0xFFB8D1FA)),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Text(
                    'Open Community Discovery to find stories from other travellers.',
                  ),
                ),
              ),
            )
          else
            SizedBox(
              height: 205,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                scrollDirection: Axis.horizontal,
                itemCount: posts.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (_, index) => _CommunityPostPreviewCard(
                  post: posts[index],
                  controller: controller,
                  onTap: () => onOpenPost(posts[index]),
                ),
              ),
            ),
        ],
      );
    },
  );
}

class _CommunityPostPreviewCard extends StatelessWidget {
  const _CommunityPostPreviewCard({
    required this.post,
    required this.controller,
    required this.onTap,
  });

  final CommunityPost post;
  final CommunityController controller;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 246,
    child: Card(
      margin: EdgeInsets.zero,
      elevation: 1,
      shadowColor: const Color(0x220D2F69),
      color: Colors.white.withValues(alpha: .94),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: Color(0xFFB8D1FA), width: 1.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: onTap,
        child: Column(
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _CommunityImage(post: post),
                  Positioned(
                    top: 5,
                    right: 5,
                    child: IconButton.filled(
                      visualDensity: VisualDensity.compact,
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black45,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: controller.isBookmarkPending(post.id)
                          ? null
                          : () => controller.toggleBookmark(post.id),
                      icon: Icon(
                        post.isBookmarked
                            ? Icons.bookmark_rounded
                            : Icons.bookmark_border_rounded,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 15, 8),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 14,
                    child: Icon(Icons.person_rounded, size: 16),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          post.authorName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF123A78),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          _relativeDate(post.createdAt),
                          style: const TextStyle(
                            color: Color(0xFF7B8494),
                            fontSize: 9,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 38,
                    child: Row(
                      children: [
                        SizedBox(
                          width: 24,
                          height: 30,
                          child: IconButton(
                            style: IconButton.styleFrom(
                              minimumSize: const Size(24, 30),
                              padding: EdgeInsets.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            tooltip: post.isLiked ? 'Unlike' : 'Like',
                            onPressed: controller.isLikePending(post.id)
                                ? null
                                : () => controller.toggleLike(post.id),
                            icon: Icon(
                              post.isLiked
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              color: post.isLiked ? Colors.redAccent : null,
                              size: 18,
                            ),
                          ),
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '${post.likeCount}',
                          style: const TextStyle(fontSize: 9),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 38,
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 24,
                          height: 30,
                          child: Center(
                            child: Icon(
                              Icons.chat_bubble_outline_rounded,
                              size: 18,
                            ),
                          ),
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '${post.commentCount}',
                          style: const TextStyle(fontSize: 9),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  static String _relativeDate(DateTime createdAt) {
    final elapsed = DateTime.now().difference(createdAt);
    if (elapsed.inDays > 0) return '${elapsed.inDays}d ago';
    if (elapsed.inHours > 0) return '${elapsed.inHours}h ago';
    return '${elapsed.inMinutes.clamp(1, 59)}m ago';
  }
}

class _CommunityImage extends StatelessWidget {
  const _CommunityImage({required this.post});
  final CommunityPost post;

  @override
  Widget build(BuildContext context) {
    if (post.imageBytes != null) {
      return Image.memory(post.imageBytes!, fit: BoxFit.cover);
    }
    if (post.imageUrl != null && post.imageUrl!.isNotEmpty) {
      return Image.network(
        post.imageUrl!,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const _BrandImageFallback(),
      );
    }
    return const _BrandImageFallback();
  }
}

class _PlaceImage extends StatelessWidget {
  const _PlaceImage({required this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) return const _BrandImageFallback();
    return Image.network(
      url!,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => const _BrandImageFallback(),
    );
  }
}

class _BrandImageFallback extends StatelessWidget {
  const _BrandImageFallback();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xFFDBE8FC),
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Image.asset(
          'assets/images/branding/ohmy_icon.png',
          fit: BoxFit.contain,
        ),
      ),
    ),
  );
}
