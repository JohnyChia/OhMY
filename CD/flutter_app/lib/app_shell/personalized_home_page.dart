import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../community_discovery/models/community_post.dart';
import '../community_discovery/state/community_controller.dart';
import '../shared/widgets/wau_loading_indicator.dart';
import '../user_management/services/traveler_profile_service.dart';

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

class _PersonalizedHomePageState extends State<PersonalizedHomePage> {
  static const _backend = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'http://127.0.0.1:3000',
  );

  List<Map<String, dynamic>> _places = const [];
  final Set<String> _bookmarkedPlaceIds = {};
  bool _loadingPlaces = true;
  int _loadGeneration = 0;
  String _lastPreferenceKey = '';

  @override
  void initState() {
    super.initState();
    currentTravelerPreferences.addListener(_preferencesChanged);
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
    currentTravelerPreferences.removeListener(_preferencesChanged);
    super.dispose();
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
    final generation = ++_loadGeneration;
    if (mounted) setState(() => _loadingPlaces = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      final location = await Geolocator.getCurrentPosition();
      var preferences = currentTravelerPreferences.value;
      if (preferences.isEmpty) {
        preferences =
            (await TravelerProfileService().fetchCurrentProfile())
                ?.favoriteCategories ??
            const [];
      }
      if (preferences.isEmpty) return;
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
              'radiusMetres': 10000,
            }),
          )
          .timeout(const Duration(seconds: 90));
      if (response.statusCode < 200 || response.statusCode >= 300) return;

      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final ranked = List<Map<String, dynamic>>.from(
        payload['matchedPlaces'] ?? const [],
      ).where(_isCompleteNearbyPlace).take(10).toList(growable: false);
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _places = ranked);
    } catch (_) {
      // Home remains navigable if location, Supabase, or the backend is down.
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() => _loadingPlaces = false);
      }
    }
  }

  bool _isCompleteNearbyPlace(Map<String, dynamic> recommendation) {
    final place = _place(recommendation);
    final description = place['description']?.toString().trim() ?? '';
    final photoName = _photoName(place);
    // Nearby Matches uses a geographic radius. A valid nearby attraction can
    // have a driving route longer than 10 km because of the road layout.
    final distance = place['distanceKm'] ?? place['routeDistanceKm'];
    return description.isNotEmpty &&
        photoName != null &&
        distance is num &&
        distance <= 10;
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

  String _description(Map<String, dynamic> item) =>
      _place(item)['description']?.toString().trim() ?? '';

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
    return value is num ? '${value.round()} min' : '-- min';
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

  void _togglePlaceBookmark(Map<String, dynamic> item) {
    final id = _place(item)['id']?.toString();
    if (id == null || id.isEmpty) return;
    setState(() {
      _bookmarkedPlaceIds.contains(id)
          ? _bookmarkedPlaceIds.remove(id)
          : _bookmarkedPlaceIds.add(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final featured = _places.isEmpty ? null : _places.first;
    final nearby = _places.length <= 1 ? _places : _places.skip(1).toList();
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
                onSearch: () => widget.onOpenSoloMap(null),
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
                onBookmark: _togglePlaceBookmark,
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

class _FeaturedPlace extends StatelessWidget {
  const _FeaturedPlace({
    required this.item,
    required this.loading,
    required this.backend,
    required this.name,
    required this.description,
    required this.photoUrl,
    required this.tags,
    required this.onSearch,
    required this.onExplore,
  });

  final Map<String, dynamic>? item;
  final bool loading;
  final String backend;
  final String? name;
  final String? description;
  final String? photoUrl;
  final List<String> tags;
  final VoidCallback onSearch;
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
                    width: 58,
                    height: 58,
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(17),
                      boxShadow: const [
                        BoxShadow(color: Colors.black26, blurRadius: 12),
                      ],
                    ),
                    child: Image.asset(
                      'assets/images/branding/ohmy_icon.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Material(
                      color: const Color(0xFFF8F6FB),
                      elevation: 3,
                      borderRadius: BorderRadius.circular(28),
                      child: InkWell(
                        onTap: onSearch,
                        borderRadius: BorderRadius.circular(28),
                        child: const SizedBox(
                          height: 54,
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 17),
                            child: Row(
                              children: [
                                Icon(Icons.search_rounded, size: 24),
                                SizedBox(width: 11),
                                Expanded(
                                  child: Text(
                                    'Search Attractions ...',
                                    style: TextStyle(
                                      color: Color(0xFF5F6470),
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                                Icon(Icons.tune_rounded, size: 21),
                              ],
                            ),
                          ),
                        ),
                      ),
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
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Places Near You',
                    style: TextStyle(
                      color: Color(0xFF151D31),
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
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
                'No complete personalised attractions were found within 10 km.',
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
      elevation: 2,
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
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
                    top: 4,
                    right: 4,
                    child: IconButton.filledTonal(
                      visualDensity: VisualDensity.compact,
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
                        color: Color(0xFF151D31),
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
      border: dark ? Border.all(color: Colors.white38) : null,
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
                      color: Color(0xFF151D31),
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: onSeeMore,
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
                    color: const Color(0xFFEAF1FF),
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
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
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
                      onPressed: () => controller.toggleBookmark(post.id),
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
              padding: const EdgeInsets.fromLTRB(10, 8, 7, 8),
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
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: post.isLiked ? 'Unlike' : 'Like',
                    onPressed: () => controller.toggleLike(post.id),
                    icon: Icon(
                      post.isLiked
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      color: post.isLiked ? Colors.redAccent : null,
                      size: 18,
                    ),
                  ),
                  Text(
                    '${post.likeCount}',
                    style: const TextStyle(fontSize: 9),
                  ),
                  const SizedBox(width: 5),
                  const Icon(Icons.chat_bubble_outline_rounded, size: 17),
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
