import 'package:flutter/material.dart';
import 'package:community_discovery/community_discovery.dart';

/// Compatibility wrapper for callers outside Profile. New code should use
/// [openCommunityBookmarks] from the Community package.
class BookmarksScreen extends StatelessWidget {
  const BookmarksScreen({super.key, required this.controller});

  final CommunityController controller;

  @override
  Widget build(BuildContext context) =>
      BookmarkedPostsScreen(controller: controller);
}
