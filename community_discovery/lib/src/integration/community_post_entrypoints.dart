import 'package:flutter/material.dart';

import '../models/community_post.dart';
import '../models/completed_trip.dart';
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

/// Preferred Profile Travel History entrypoint. A persisted history entry is
/// sufficient eligibility; the server still verifies that it belongs to the
/// signed-in user before creating or editing a post.
Future<PostEditorResult?> openTripHistoryPostAction(
  BuildContext context, {
  required CommunityController controller,
  required CompletedTrip historyEntry,
}) async {
  final existing = await controller.getPostForHistoryEntry(historyEntry.id);
  if (!context.mounted) return null;
  return Navigator.of(context).push(
    MaterialPageRoute<PostEditorResult>(
      builder: (_) => CreatePostScreen(
        controller: controller,
        completedTrip: existing == null ? historyEntry : null,
        post: existing,
      ),
    ),
  );
}

/// Opens Create Post for a persisted Profile Travel History row.
Future<PostEditorResult?> openTripHistoryPostEditor(
  BuildContext context, {
  required CommunityController controller,
  required CompletedTrip historyEntry,
}) async {
  return Navigator.of(context).push(
    MaterialPageRoute<PostEditorResult>(
      builder: (_) =>
          CreatePostScreen(controller: controller, completedTrip: historyEntry),
    ),
  );
}

/// Use from a Trip History row that already has a Community post. Saving edits
/// the same post; it never creates a second post for the trip.
Future<PostEditorResult?> openTripHistoryExistingPostEditor(
  BuildContext context, {
  required CommunityController controller,
  required CommunityPost post,
}) async {
  return Navigator.of(context).push(
    MaterialPageRoute<PostEditorResult>(
      builder: (_) => CreatePostScreen(controller: controller, post: post),
    ),
  );
}
