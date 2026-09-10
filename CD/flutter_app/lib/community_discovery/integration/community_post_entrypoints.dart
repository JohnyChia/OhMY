import 'package:flutter/material.dart';

import '../models/community_post.dart';
import '../state/community_controller.dart';
import '../ui/create_post_screen.dart';
import '../ui/bookmarked_posts_screen.dart';
import 'community_integration_callbacks.dart';

Future<void> openCommunityBookmarks(
  BuildContext context, {
  required CommunityController controller,
  CommunityIntegrationCallbacks integrationCallbacks =
      const CommunityIntegrationCallbacks(),
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => BookmarkedPostsScreen(
      controller: controller,
      integrationCallbacks: integrationCallbacks,
    ),
  ),
);

/// Preferred Trip History entrypoint: it looks up the trip and opens Create or
/// Edit automatically. Incomplete trips are rejected by Supabase and Node.
Future<void> openTripHistoryPostAction(
  BuildContext context, {
  required CommunityController controller,
  required String tripSessionId,
}) async {
  final existing = await controller.getPostForTripSession(tripSessionId);
  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => CreatePostScreen(
        controller: controller,
        completedTripId: existing == null ? tripSessionId : null,
        post: existing,
      ),
    ),
  );
}

/// Use only from an eligible Trip History row. Supabase rejects unfinished,
/// unrelated, non-participant, and already-posted trip sessions.
Future<void> openTripHistoryPostEditor(
  BuildContext context, {
  required CommunityController controller,
  required String tripSessionId,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => CreatePostScreen(
      controller: controller,
      completedTripId: tripSessionId,
    ),
  ),
);

/// Use from a Trip History row that already has a Community post. Saving edits
/// the same post; it never creates a second post for the trip.
Future<void> openTripHistoryExistingPostEditor(
  BuildContext context, {
  required CommunityController controller,
  required CommunityPost post,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => CreatePostScreen(controller: controller, post: post),
  ),
);
