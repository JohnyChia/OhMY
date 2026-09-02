import 'dart:typed_data';

import '../models/community_comment.dart';
import '../models/community_post.dart';
import '../models/completed_trip.dart';
import '../models/discovery_tag.dart';

class CreatePostInput {
  const CreatePostInput({
    required this.completedTripId,
    required this.description,
    required this.tagIds,
    required this.imageBytes,
    required this.imageExtension,
  });

  final String completedTripId;
  final String description;
  final List<int> tagIds;
  final Uint8List imageBytes;
  final String imageExtension;
}

abstract interface class CommunityRepository {
  Future<List<CommunityPost>> getPosts({
    String query = '',
    Set<int> tagIds = const {},
  });
  Future<List<DiscoveryTag>> getTags();
  Future<List<CommunityComment>> getComments(String postId);
  Future<List<CompletedTrip>> getEligibleTrips();
  Future<void> setLiked(String postId, bool liked);
  Future<void> setBookmarked(String postId, bool bookmarked);
  Future<CommunityComment> addComment(String postId, String content);
  Future<CommunityPost> createPost(CreatePostInput input);
}
