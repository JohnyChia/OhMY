import 'dart:async';
import 'dart:ui' as ui;

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
        backgroundColor: const Color(0xFFFFFCF8),
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          toolbarHeight: 68,
          leadingWidth: 68,
          leading: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            child: Material(
              color: const Color(0xF7FFFFFF),
              elevation: 3,
              shadowColor: const Color(0x33000000),
              shape: const CircleBorder(
                side: BorderSide(color: Color(0xFFBFD3F2)),
              ),
              child: IconButton(
                tooltip: 'Back',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(
                  Icons.arrow_back,
                  color: Color(0xFF28599F),
                  size: 25,
                ),
              ),
            ),
          ),
          title: const Text(
            'Saved posts',
            style: TextStyle(
              color: Color(0xFF17345F),
              fontSize: 27,
              fontWeight: FontWeight.w800,
              fontFamily: 'serif',
            ),
          ),
          centerTitle: false,
        ),
        body: Stack(
          fit: StackFit.expand,
          children: [
            ClipRect(
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 3.5, sigmaY: 3.5),
                child: Transform.scale(
                  scale: 1.02,
                  child: Image.asset(
                    'assets/images/user_management/saved_post_bg.png',
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
            const ColoredBox(color: Color(0x14FFFFFF)),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(top: 68),
                child: SavedPostsSection(
                  controller: widget.controller,
                  integrationCallbacks: widget.integrationCallbacks,
                  posts: posts,
                ),
              ),
            ),
          ],
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
