import '../models/community_comment.dart';
import '../models/community_post.dart';
import '../models/completed_trip.dart';
import '../models/discovery_tag.dart';
import 'community_repository.dart';

class DemoCommunityRepository implements CommunityRepository {
  static const _tags = <DiscoveryTag>[
    DiscoveryTag(id: 1, name: 'Restaurant', type: 'general'),
    DiscoveryTag(id: 2, name: 'Cafe', type: 'general'),
    DiscoveryTag(id: 3, name: 'Museum', type: 'general'),
    DiscoveryTag(id: 4, name: 'Market', type: 'general'),
    DiscoveryTag(id: 5, name: 'Landmark', type: 'general'),
    DiscoveryTag(id: 6, name: 'Shopping', type: 'general'),
    DiscoveryTag(id: 7, name: 'Park', type: 'general'),
    DiscoveryTag(id: 8, name: 'Nature', type: 'general'),
    DiscoveryTag(id: 9, name: 'Adventure', type: 'general'),
    DiscoveryTag(id: 10, name: 'Educational', type: 'general'),
    DiscoveryTag(id: 11, name: 'Entertainment', type: 'general'),
    DiscoveryTag(id: 12, name: 'International Cuisine', type: 'general'),
    DiscoveryTag(id: 13, name: 'Heritage', type: 'cultural'),
    DiscoveryTag(id: 14, name: 'Cultural Learning', type: 'cultural'),
    DiscoveryTag(id: 15, name: 'Historical Landmark', type: 'cultural'),
    DiscoveryTag(id: 16, name: 'Traditional Architecture', type: 'cultural'),
    DiscoveryTag(id: 17, name: 'Traditional Craft', type: 'cultural'),
    DiscoveryTag(id: 18, name: 'Religious Heritage', type: 'cultural'),
    DiscoveryTag(id: 19, name: 'Cultural Festival', type: 'cultural'),
    DiscoveryTag(id: 20, name: 'Local Cuisine', type: 'cultural'),
    DiscoveryTag(id: 21, name: 'Cultural Experience', type: 'cultural'),
  ];

  final List<CommunityPost> _posts = [
    CommunityPost(
      id: 'post-1',
      authorName: 'Aina',
      locationName: 'Kuala Lumpur',
      attractionName: 'Kwai Chai Hong',
      description:
          'Go before 9 AM for quieter lanes, beautiful murals and great morning light. A lovely stop for a heritage walk.',
      tags: const ['Cultural Experience', 'Heritage'],
      createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      likeCount: 128,
      commentCount: 1,
      isLiked: false,
      isBookmarked: false,
      imageUrl:
          'https://images.unsplash.com/photo-1596422846543-75c6fc197f07?w=1200',
    ),
    CommunityPost(
      id: 'post-2',
      authorName: 'Ravi',
      locationName: 'Penang',
      attractionName: 'George Town',
      description:
          'Street art, family-run cafes and an easy walking route through the old town. Save room for lunch.',
      tags: const ['Local Cuisine', 'Cafe', 'Heritage'],
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
      likeCount: 84,
      commentCount: 0,
      isLiked: true,
      isBookmarked: true,
      imageUrl:
          'https://images.unsplash.com/photo-1581793745862-99fde7fa73d2?w=1200',
    ),
  ];

  final List<CompletedTrip> _trips = [
    CompletedTrip(
      id: 'trip-1',
      title: 'Batu Caves morning trip',
      locationName: 'Selangor',
      attractionName: 'Batu Caves',
      completedAt: DateTime.now().subtract(const Duration(days: 3)),
    ),
    CompletedTrip(
      id: 'trip-2',
      title: 'Melaka heritage walk',
      locationName: 'Melaka',
      attractionName: 'Jonker Street',
      completedAt: DateTime.now().subtract(const Duration(days: 8)),
    ),
  ];

  final Map<String, List<CommunityComment>> _comments = {
    'post-1': [
      CommunityComment(
        id: 'comment-1',
        postId: 'post-1',
        authorName: 'Nurul',
        content: 'The murals are even better in person!',
        createdAt: DateTime.now().subtract(const Duration(hours: 1)),
      ),
    ],
  };
  final Set<String> _usedTripIds = {};

  Future<void> _pause() =>
      Future<void>.delayed(const Duration(milliseconds: 250));

  @override
  Future<List<CommunityPost>> getPosts({
    String query = '',
    Set<int> tagIds = const {},
  }) async {
    await _pause();
    final needle = query.trim().toLowerCase();
    return _posts
        .where((post) {
          final searchable = [
            post.description,
            post.locationName,
            post.attractionName,
            ...post.tags,
          ].join(' ').toLowerCase();
          final matchesQuery = needle.isEmpty || searchable.contains(needle);
          final selectedNames = _tags
              .where((tag) => tagIds.contains(tag.id))
              .map((tag) => tag.name)
              .toSet();
          final matchesTags =
              selectedNames.isEmpty || post.tags.any(selectedNames.contains);
          return matchesQuery && matchesTags;
        })
        .toList(growable: false);
  }

  @override
  Future<List<DiscoveryTag>> getTags() async {
    await _pause();
    return _tags;
  }

  @override
  Future<List<CommunityComment>> getComments(String postId) async {
    await _pause();
    return List.unmodifiable(_comments[postId] ?? const []);
  }

  @override
  Future<List<CompletedTrip>> getEligibleTrips() async {
    await _pause();
    return _trips.where((trip) => !_usedTripIds.contains(trip.id)).toList();
  }

  @override
  Future<void> setLiked(String postId, bool liked) async {
    await _pause();
    final index = _posts.indexWhere((post) => post.id == postId);
    if (index < 0) return;
    final post = _posts[index];
    if (post.isLiked == liked) return;
    _posts[index] = post.copyWith(
      isLiked: liked,
      likeCount: post.likeCount + (liked ? 1 : -1),
    );
  }

  @override
  Future<void> setBookmarked(String postId, bool bookmarked) async {
    await _pause();
    final index = _posts.indexWhere((post) => post.id == postId);
    if (index < 0) return;
    _posts[index] = _posts[index].copyWith(isBookmarked: bookmarked);
  }

  @override
  Future<CommunityComment> addComment(String postId, String content) async {
    await _pause();
    final comment = CommunityComment(
      id: 'comment-${DateTime.now().microsecondsSinceEpoch}',
      postId: postId,
      authorName: 'You',
      content: content.trim(),
      createdAt: DateTime.now(),
    );
    (_comments[postId] ??= []).add(comment);
    final index = _posts.indexWhere((post) => post.id == postId);
    if (index >= 0) {
      _posts[index] = _posts[index].copyWith(
        commentCount: _posts[index].commentCount + 1,
      );
    }
    return comment;
  }

  @override
  Future<CommunityPost> createPost(CreatePostInput input) async {
    await _pause();
    final trip = _trips.firstWhere((item) => item.id == input.completedTripId);
    if (_usedTripIds.contains(trip.id)) {
      throw StateError('This completed trip already has a community post.');
    }
    final post = CommunityPost(
      id: 'post-${DateTime.now().microsecondsSinceEpoch}',
      authorName: 'You',
      locationName: trip.locationName,
      attractionName: trip.attractionName,
      description: input.description.trim(),
      tags: List.unmodifiable(
        _tags
            .where((tag) => input.tagIds.contains(tag.id))
            .map((tag) => tag.name),
      ),
      createdAt: DateTime.now(),
      likeCount: 0,
      commentCount: 0,
      isLiked: false,
      isBookmarked: false,
      imageBytes: input.imageBytes,
    );
    _usedTripIds.add(trip.id);
    _posts.insert(0, post);
    return post;
  }
}
