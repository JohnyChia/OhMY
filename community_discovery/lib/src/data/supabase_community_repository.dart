import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/community_comment.dart';
import '../models/community_post.dart';
import '../models/completed_trip.dart';
import '../models/discovery_tag.dart';
import 'community_repository.dart';
import 'community_validation_api.dart';

class SupabaseCommunityRepository implements CommunityRepository {
  SupabaseCommunityRepository(this._client, {required String communityApiUrl})
    : _validationApi = CommunityValidationApi(
        baseUrl: communityApiUrl,
        supabase: _client,
      ) {
    _channel = _client
        .channel('community-discovery-v2')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'community_posts',
          callback: (_) => _notifyChanged(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'community_post_likes',
          callback: (_) => _notifyChanged(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'community_post_bookmarks',
          callback: (_) => _notifyChanged(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'community_post_comments',
          callback: (_) => _notifyChanged(),
        )
        .subscribe();
  }

  final SupabaseClient _client;
  final CommunityValidationApi _validationApi;
  final _changes = StreamController<void>.broadcast();
  late final RealtimeChannel _channel;

  void _notifyChanged() => _changes.add(null);

  @override
  Stream<void> get changes => _changes.stream;

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) {
      throw StateError('Please sign in before using Community Discovery.');
    }
    return id;
  }

  @override
  Future<List<CommunityPost>> getPosts({
    String query = '',
    Set<int> tagIds = const {},
    bool bookmarkedOnly = false,
  }) async {
    final normalizedQuery = query.trim().toLowerCase();
    final rows = await _client.rpc(
      'community_feed_v5',
      params: {
        'search_query': query.trim(),
        'tag_filters': tagIds.toList(),
        'result_limit': 50,
        'result_offset': 0,
        'bookmarked_only': bookmarkedOnly,
      },
    );
    return (rows as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map((row) {
          final imagePath = row['image_path'] as String?;
          final imagePaths = List<String>.from(
            row['image_paths'] as List? ?? const [],
          );
          final directImageUrls = List<String>.from(
            row['image_urls'] as List? ?? const [],
          );
          final publicImageUrls = <String>[
            ...directImageUrls,
            ...imagePaths.map(
              (path) =>
                  _client.storage.from('community-posts').getPublicUrl(path),
            ),
          ];
          final imageUrl =
              publicImageUrls.firstOrNull ??
              row['image_url'] as String? ??
              (imagePath == null
                  ? null
                  : _client.storage
                        .from('community-posts')
                        .getPublicUrl(imagePath));
          return CommunityPost.fromFeedMap(
            row,
            isLiked: row['is_liked'] as bool? ?? false,
            isBookmarked: row['is_bookmarked'] as bool? ?? false,
            publicImageUrl: imageUrl,
            publicImageUrls: publicImageUrls,
          );
        })
        .where(
          (post) =>
              normalizedQuery.isEmpty ||
              '${post.title} ${post.attractionName} ${post.locationName} '
                      '${post.description} ${post.tags.join(' ')}'
                  .toLowerCase()
                  .contains(normalizedQuery),
        )
        .toList(growable: false);
  }

  @override
  Future<List<DiscoveryTag>> getTags() async {
    final rows = await _client.rpc('get_filter_tags_v1');
    return (rows as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(DiscoveryTag.fromMap)
        .toList(growable: false);
  }

  @override
  Future<List<CommunityComment>> getComments(String postId) async {
    final rows = await _client
        .from('community_post_comments')
        .select('id, post_id, user_id, author_name, content, created_at')
        .eq('post_id', postId)
        .order('created_at');
    return rows
        .map((row) => CommunityComment.fromMap(row, currentUserId: _userId))
        .toList(growable: false);
  }

  @override
  Future<List<CompletedTrip>> getEligibleTrips() async {
    final rows = await _client.rpc('eligible_community_history_entries_v6');
    return (rows as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(CompletedTrip.fromMap)
        .toList(growable: false);
  }

  @override
  Future<CommunityPost?> getPostForHistoryEntry(String historyEntryId) async {
    final postId = await _client.rpc(
      'community_post_id_for_history_v5',
      params: {'p_history_entry_id': historyEntryId},
    );
    if (postId == null) return null;
    final posts = await getPosts();
    return posts.where((post) => post.id == postId).firstOrNull;
  }

  @override
  Future<void> setLiked(String postId, bool liked) async {
    if (liked) {
      await _client.from('community_post_likes').upsert({
        'post_id': postId,
        'user_id': _userId,
      });
    } else {
      await _client
          .from('community_post_likes')
          .delete()
          .eq('post_id', postId)
          .eq('user_id', _userId);
    }
  }

  @override
  Future<void> setBookmarked(String postId, bool bookmarked) async {
    if (bookmarked) {
      await _client.from('community_post_bookmarks').upsert({
        'post_id': postId,
        'user_id': _userId,
      });
    } else {
      await _client
          .from('community_post_bookmarks')
          .delete()
          .eq('post_id', postId)
          .eq('user_id', _userId);
    }
  }

  @override
  Future<CommunityComment> addComment(String postId, String content) async {
    try {
      final rows = await _client.rpc(
        'community_add_comment_v7',
        params: {'p_post_id': postId, 'p_content': content.trim()},
      );
      final row = (rows as List<dynamic>).cast<Map<String, dynamic>>().single;
      return CommunityComment.fromMap(row, currentUserId: _userId);
    } on PostgrestException catch (error) {
      throw StateError(error.message);
    }
  }

  @override
  Future<void> deleteComment(String commentId) async {
    await _client.rpc(
      'community_delete_comment_v6',
      params: {'p_comment_id': commentId},
    );
  }

  @override
  Future<CommunityPost> createPost(CreatePostInput input) async {
    if (input.images.isEmpty || input.images.length > 6) {
      throw ArgumentError('Select between 1 and 6 pictures.');
    }
    final imagePaths = await _uploadImages(input.images);
    try {
      final postId = await _validationApi.createPost(
        historyEntryId: input.historyEntryId,
        title: input.title.trim(),
        description: input.description.trim(),
        imagePaths: imagePaths,
      );
      final posts = await getPosts();
      return posts.firstWhere((post) => post.id == postId);
    } catch (_) {
      await _client.storage.from('community-posts').remove(imagePaths);
      rethrow;
    }
  }

  @override
  Future<CommunityPost> updatePost(UpdatePostInput input) async {
    final newImages = input.images;
    final galleryChanged =
        newImages != null || input.retainedImagePaths != null;
    final retainedPaths = input.retainedImagePaths ?? const <String>[];
    final finalCount = retainedPaths.length + (newImages?.length ?? 0);
    if (retainedPaths.toSet().length != retainedPaths.length) {
      throw ArgumentError('The same picture cannot be added more than once.');
    }
    if (galleryChanged && (finalCount < 1 || finalCount > 6)) {
      throw ArgumentError('Select between 1 and 6 pictures.');
    }
    final uploadedPaths = newImages == null || newImages.isEmpty
        ? <String>[]
        : await _uploadImages(newImages);
    final imagePaths = galleryChanged
        ? [...retainedPaths, ...uploadedPaths]
        : <String>[];
    try {
      await _validationApi.updatePost(
        postId: input.postId,
        title: input.title.trim(),
        description: input.description.trim(),
        imagePaths: imagePaths,
      );
      if (galleryChanged && input.existingImagePaths.isNotEmpty) {
        final removedPaths = input.existingImagePaths
            .where((path) => !retainedPaths.contains(path))
            .toList(growable: false);
        try {
          if (removedPaths.isNotEmpty) {
            await _client.storage.from('community-posts').remove(removedPaths);
          }
        } catch (_) {
          // The database update succeeded; orphan cleanup can be retried later.
        }
      }
      final posts = await getPosts();
      return posts.firstWhere((post) => post.id == input.postId);
    } catch (_) {
      if (uploadedPaths.isNotEmpty) {
        await _client.storage.from('community-posts').remove(uploadedPaths);
      }
      rethrow;
    }
  }

  @override
  Future<void> deletePost(String postId, List<String> imagePaths) async {
    await _client.rpc(
      'community_delete_post_v6',
      params: {'p_post_id': postId},
    );
    if (imagePaths.isNotEmpty) {
      try {
        await _client.storage.from('community-posts').remove(imagePaths);
      } catch (_) {
        // The post is deleted; orphaned storage cleanup can be retried later.
      }
    }
  }

  @override
  Future<void> dispose() async {
    _validationApi.close();
    await _client.removeChannel(_channel);
    await _changes.close();
  }

  void _validateImage(List<int> bytes, String extension) {
    if (!{'jpg', 'jpeg', 'png'}.contains(extension.toLowerCase())) {
      throw ArgumentError('Only JPG, JPEG, and PNG are accepted.');
    }
    if (bytes.length > 10 * 1024 * 1024) {
      throw ArgumentError('Picture must not exceed 10 MB.');
    }
  }

  Future<List<String>> _uploadImages(List<PostImageUpload> images) async {
    for (var index = 0; index < images.length; index++) {
      for (var previous = 0; previous < index; previous++) {
        if (_sameBytes(images[index].bytes, images[previous].bytes)) {
          throw ArgumentError(
            'The same picture cannot be added more than once.',
          );
        }
      }
    }
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final paths = <String>[];
    try {
      for (var index = 0; index < images.length; index++) {
        final image = images[index];
        _validateImage(image.bytes, image.extension);
        final extension = image.extension.toLowerCase();
        final path = '$_userId/${timestamp}_$index.$extension';
        final contentType = extension == 'png' ? 'image/png' : 'image/jpeg';
        await _client.storage
            .from('community-posts')
            .uploadBinary(
              path,
              image.bytes,
              fileOptions: FileOptions(
                cacheControl: '3600',
                contentType: contentType,
              ),
            );
        paths.add(path);
      }
      return paths;
    } catch (_) {
      if (paths.isNotEmpty) {
        await _client.storage.from('community-posts').remove(paths);
      }
      rethrow;
    }
  }

  bool _sameBytes(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}
