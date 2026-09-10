import 'dart:async';

import 'package:flutter/material.dart';

import '../state/community_controller.dart';
import '../integration/community_integration_callbacks.dart';
import '../models/community_post.dart';
import 'widgets/post_card.dart';

class BookmarkedPostsScreen extends StatefulWidget {
  const BookmarkedPostsScreen({
    super.key,
    required this.controller,
    this.integrationCallbacks = const CommunityIntegrationCallbacks(),
  });

  final CommunityController controller;
  final CommunityIntegrationCallbacks integrationCallbacks;

  @override
  State<BookmarkedPostsScreen> createState() => _BookmarkedPostsScreenState();
}

class _BookmarkedPostsScreenState extends State<BookmarkedPostsScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.controller.loadBookmarkedPosts());
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final posts = widget.controller.bookmarkedPosts;
      return Scaffold(
        appBar: AppBar(title: const Text('Saved posts')),
        body: SavedPostsSection(
          controller: widget.controller,
          integrationCallbacks: widget.integrationCallbacks,
          posts: posts,
        ),
      );
    },
  );
}

/// Embeddable Profile section. The parent Profile owns its surrounding page.
class SavedPostsSection extends StatelessWidget {
  const SavedPostsSection({
    super.key,
    required this.controller,
    this.integrationCallbacks = const CommunityIntegrationCallbacks(),
    this.posts,
  });

  final CommunityController controller;
  final CommunityIntegrationCallbacks integrationCallbacks;
  final List<CommunityPost>? posts;

  @override
  Widget build(BuildContext context) {
    final saved = posts ?? controller.bookmarkedPosts;
    return RefreshIndicator(
      onRefresh: controller.loadBookmarkedPosts,
      child: saved.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 180),
                Icon(Icons.bookmark_border, size: 56),
                SizedBox(height: 12),
                Center(child: Text('No saved community posts yet.')),
              ],
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
              itemCount: saved.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (_, index) => PostCard(
                post: saved[index],
                controller: controller,
                integrationCallbacks: integrationCallbacks,
              ),
            ),
    );
  }
}
