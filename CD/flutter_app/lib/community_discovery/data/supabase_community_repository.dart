import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/community_comment.dart';
import '../models/community_post.dart';
import '../models/completed_trip.dart';
import '../models/discovery_tag.dart';
import 'community_repository.dart';

class SupabaseCommunityRepository implements CommunityRepository {
  SupabaseCommunityRepository(this._client);

  final SupabaseClient _client;

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
  }) async {
    final rows = await _client.rpc(
      'community_feed',
      params: {
        'search_query': query.trim(),
        'tag_filters': tagIds.toList(),
        'result_limit': 50,
        'result_offset': 0,
      },
    );
    return (rows as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map((row) {
          final imagePath = row['image_path'] as String?;
          final imageUrl = imagePath == null
              ? null
              : _client.storage.from('community-posts').getPublicUrl(imagePath);
          return CommunityPost.fromFeedMap(
            row,
            isLiked: row['is_liked'] as bool? ?? false,
            isBookmarked: row['is_bookmarked'] as bool? ?? false,
            publicImageUrl: imageUrl,
          );
        })
        .toList(growable: false);
  }

  @override
  Future<List<DiscoveryTag>> getTags() async {
    final rows = await _client
        .from('tags')
        .select('id, name, tag_type')
        .order('tag_type')
        .order('name');
    return rows.map(DiscoveryTag.fromMap).toList(growable: false);
  }

  @override
  Future<List<CommunityComment>> getComments(String postId) async {
    final rows = await _client
        .from('community_post_comments')
        .select('id, post_id, author_name, content, created_at')
        .eq('post_id', postId)
        .order('created_at');
    return rows.map(CommunityComment.fromMap).toList(growable: false);
  }

  @override
  Future<List<CompletedTrip>> getEligibleTrips() async {
    final rows = await _client.rpc('eligible_community_trips');
    return (rows as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(CompletedTrip.fromMap)
        .toList(growable: false);
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
    final row = await _client
        .from('community_post_comments')
        .insert({
          'post_id': postId,
          'user_id': _userId,
          'content': content.trim(),
        })
        .select('id, post_id, author_name, content, created_at')
        .single();
    return CommunityComment.fromMap(row);
  }

  @override
  Future<CommunityPost> createPost(CreatePostInput input) async {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final imagePath = '$_userId/$timestamp.${input.imageExtension}';
    final contentType = switch (input.imageExtension) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };
    await _client.storage
        .from('community-posts')
        .uploadBinary(
          imagePath,
          input.imageBytes,
          fileOptions: FileOptions(
            cacheControl: '3600',
            contentType: contentType,
          ),
        );
    try {
      final postId =
          await _client.rpc(
                'create_community_post',
                params: {
                  'trip_session_id': input.completedTripId,
                  'post_description': input.description.trim(),
                  'post_image_path': imagePath,
                  'post_tag_ids': input.tagIds,
                },
              )
              as String;
      final posts = await getPosts();
      return posts.firstWhere((post) => post.id == postId);
    } catch (_) {
      await _client.storage.from('community-posts').remove([imagePath]);
      rethrow;
    }
  }
}
