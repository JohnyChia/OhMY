import 'dart:async';

import 'package:community_discovery/community_discovery.dart';
import 'package:flutter/material.dart';

import '../../preference_recommender/pages/place_map_page.dart';
import '../../shared/widgets/ohmy_snack_bar.dart';
import '../models/saved_location.dart';
import '../services/saved_location_service.dart';

class BookmarksScreen extends StatefulWidget {
  const BookmarksScreen({super.key, required this.communityController});

  final CommunityController communityController;

  @override
  State<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends State<BookmarksScreen> {
  static const _backend = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'http://127.0.0.1:3000',
  );

  int _tab = 0;
  bool _loadingLocations = true;
  String? _locationError;
  List<SavedLocation> _locations = const [];

  @override
  void initState() {
    super.initState();
    unawaited(widget.communityController.loadBookmarkedPosts());
    unawaited(_loadLocations());
    savedLocationService.changes.addListener(_savedLocationsChanged);
  }

  @override
  void dispose() {
    savedLocationService.changes.removeListener(_savedLocationsChanged);
    super.dispose();
  }

  void _savedLocationsChanged() {
    if (!mounted) return;
    setState(() => _locations = savedLocationService.cached);
  }

  Future<void> _loadLocations() async {
    if (mounted) {
      setState(() {
        _loadingLocations = true;
        _locationError = null;
      });
    }
    try {
      final locations = await savedLocationService.fetch(force: true);
      if (mounted) setState(() => _locations = locations);
    } on SavedLocationFailure catch (error) {
      if (mounted) setState(() => _locationError = error.message);
    } finally {
      if (mounted) setState(() => _loadingLocations = false);
    }
  }

  Future<void> _remove(SavedLocation location) async {
    try {
      await savedLocationService.remove(location);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const OhMySnackBar(content: Text('Location removed from bookmarks.')),
      );
    } on SavedLocationFailure catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        OhMySnackBar(content: Text(error.message), backgroundColor: Colors.red),
      );
    }
  }

  String? _photoUrl(SavedLocation location) {
    final photoName = location.photoName;
    if (photoName == null) return null;
    return '$_backend/api/places/photo?name=${Uri.encodeQueryComponent(photoName)}';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF7FAFF),
    appBar: AppBar(
      title: const Text(
        'Bookmarks',
        style: TextStyle(color: Color(0xFF123A78), fontWeight: FontWeight.w700),
      ),
      backgroundColor: const Color(0xFFF7FAFF),
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(
                value: 0,
                icon: Icon(Icons.article_outlined),
                label: Text('Saved posts'),
              ),
              ButtonSegment(
                value: 1,
                icon: Icon(Icons.location_on),
                label: Text('Saved locations'),
              ),
            ],
            selected: {_tab},
            showSelectedIcon: false,
            onSelectionChanged: (selection) {
              setState(() => _tab = selection.first);
            },
          ),
        ),
        Expanded(
          child: _tab == 0
              ? AnimatedBuilder(
                  animation: widget.communityController,
                  builder: (_, _) => SavedPostsSection(
                    controller: widget.communityController,
                    posts: widget.communityController.bookmarkedPosts,
                  ),
                )
              : _locationContent(),
        ),
      ],
    ),
  );

  Widget _locationContent() {
    if (_loadingLocations) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_locationError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 48),
              const SizedBox(height: 12),
              Text(_locationError!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _loadLocations,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (_locations.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadLocations,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 150),
            Icon(Icons.bookmark_border, size: 58, color: Color(0xFF58709F)),
            SizedBox(height: 12),
            Center(child: Text('No saved locations yet.')),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadLocations,
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 28),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 12,
          childAspectRatio: .76,
        ),
        itemCount: _locations.length,
        itemBuilder: (_, index) {
          final location = _locations[index];
          return _SavedLocationCard(
            location: location,
            photoUrl: _photoUrl(location),
            onRemove: () => _remove(location),
            onOpen: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => PlaceDetailPage(
                  item: location.toRecommendationItem(),
                  backend: _backend,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SavedLocationCard extends StatelessWidget {
  const _SavedLocationCard({
    required this.location,
    required this.photoUrl,
    required this.onRemove,
    required this.onOpen,
  });

  final SavedLocation location;
  final String? photoUrl;
  final VoidCallback onRemove;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    elevation: 1,
    borderRadius: BorderRadius.circular(12),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (photoUrl != null)
                  Image.network(
                    photoUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const _PlacePlaceholder(),
                  )
                else
                  const _PlacePlaceholder(),
                Positioned(
                  right: 7,
                  top: 7,
                  child: IconButton.filled(
                    tooltip: 'Remove bookmark',
                    onPressed: onRemove,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF174B9B),
                    ),
                    icon: const Icon(Icons.bookmark, size: 20),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  location.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF103E82),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(
                      Icons.location_on_outlined,
                      size: 14,
                      color: Color(0xFF3266CC),
                    ),
                    const SizedBox(width: 3),
                    Expanded(
                      child: Text(
                        location.locationLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFF58709F),
                        ),
                      ),
                    ),
                  ],
                ),
                if (location.tags.isNotEmpty) ...[
                  const SizedBox(height: 7),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF1FF),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      location.tags.first,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 9,
                        color: Color(0xFF3266CC),
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
  );
}

class _PlacePlaceholder extends StatelessWidget {
  const _PlacePlaceholder();

  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: Color(0xFFE7EEFB),
    child: Center(
      child: Icon(Icons.landscape_outlined, size: 44, color: Color(0xFF7890BB)),
    ),
  );
}
