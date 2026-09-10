import 'dart:typed_data';

import '../models/community_comment.dart';
import '../models/community_post.dart';
import '../models/completed_trip.dart';
import '../models/discovery_tag.dart';

class PostImageUpload {
  const PostImageUpload({required this.bytes, required this.extension});

  final Uint8List bytes;
  final String extension;
}

class CreatePostInput {
  const CreatePostInput({
    required this.completedTripId,
    required this.title,
    required this.description,
    required this.images,
  });

  final String completedTripId;
  final String title;
  final String description;
  final List<PostImageUpload> images;
}

class UpdatePostInput {
  const UpdatePostInput({
    required this.postId,
    required this.title,
    required this.description,
    this.images,
    this.existingImagePaths = const [],
  });

  final String postId;
  final String title;
  final String description;

  /// Null keeps the current gallery; a non-empty list replaces it.
  final List<PostImageUpload>? images;
  final List<String> existingImagePaths;
}

abstract interface class CommunityRepository {
  Future<List<CommunityPost>> getPosts({
    String query = '',
    Set<int> tagIds = const {},
    bool bookmarkedOnly = false,
  });
  Future<List<DiscoveryTag>> getTags();
  Future<List<CommunityComment>> getComments(String postId);
  Future<List<CompletedTrip>> getEligibleTrips();
  Future<CommunityPost?> getPostForTripSession(String tripSessionId);
  Future<void> setLiked(String postId, bool liked);
  Future<void> setBookmarked(String postId, bool bookmarked);
  Future<CommunityComment> addComment(String postId, String content);
  Future<CommunityPost> createPost(CreatePostInput input);
  Future<CommunityPost> updatePost(UpdatePostInput input);
  Stream<void> get changes;
  Future<void> dispose();
}
