import 'package:community_discovery/src/data/community_repository.dart';
import 'package:community_discovery/src/models/community_comment.dart';
import 'package:community_discovery/src/models/community_post.dart';
import 'package:community_discovery/src/models/completed_trip.dart';
import 'package:community_discovery/src/models/discovery_tag.dart';

class FakeCommunityRepository implements CommunityRepository {
  FakeCommunityRepository({bool isOwner = false})
    : _post = CommunityPost(
        id: 'post-1',
        title: 'Morning light at Kwai Chai Hong',
        authorName: 'Aina',
        locationName: 'Kuala Lumpur',
        attractionName: 'Kwai Chai Hong',
        description: 'A compact Kuala Lumpur heritage walk.',
        tags: const ['Heritage'],
        tagIds: const [13],
        createdAt: DateTime(2026),
        likeCount: 0,
        commentCount: 0,
        isLiked: false,
        isBookmarked: false,
        isOwner: isOwner,
        moderationStatus: 'approved',
      );

  final CommunityPost _post;
  final List<CommunityComment> _comments = [];

  @override
  Stream<void> get changes => const Stream.empty();

  @override
  Future<List<CommunityPost>> getPosts({
    String query = '',
    Set<int> tagIds = const {},
    bool bookmarkedOnly = false,
  }) async {
    final matches =
        query.isEmpty ||
        '${_post.title} ${_post.locationName} ${_post.tags.join(' ')}'
            .toLowerCase()
            .contains(query.toLowerCase());
    return List<CommunityPost>.unmodifiable(
      matches && !bookmarkedOnly ? [_post] : const [],
    );
  }

  @override
  Future<List<DiscoveryTag>> getTags() async => const [
    DiscoveryTag(id: 13, name: 'Heritage', type: 'cultural'),
  ];

  @override
  Future<List<CommunityComment>> getComments(String postId) async =>
      List.unmodifiable(_comments);

  @override
  Future<List<CompletedTrip>> getEligibleTrips() async => const [];

  @override
  Future<CommunityPost?> getPostForHistoryEntry(String historyEntryId) async =>
      null;

  @override
  Future<void> setLiked(String postId, bool liked) async {}

  @override
  Future<void> setBookmarked(String postId, bool bookmarked) async {}

  @override
  Future<CommunityComment> addComment(String postId, String content) async {
    final comment = CommunityComment(
      id: 'comment-${_comments.length + 1}',
      postId: postId,
      userId: 'user-1',
      authorName: 'Aina',
      content: content,
      createdAt: DateTime(2026),
      isOwner: true,
    );
    _comments.add(comment);
    return comment;
  }

  @override
  Future<void> deleteComment(String commentId) async {}

  @override
  Future<CommunityPost> createPost(CreatePostInput input) =>
      throw UnimplementedError();

  @override
  Future<CommunityPost> updatePost(UpdatePostInput input) =>
      throw UnimplementedError();

  @override
  Future<void> deletePost(String postId, List<String> imagePaths) async {}

  @override
  Future<void> dispose() async {}
}
