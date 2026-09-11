import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_app/shared/widgets/wau_loading_indicator.dart';

import '../../community_discovery/state/community_controller.dart';
import '../../community_discovery/ui/widgets/post_card.dart';

class BookmarksScreen extends StatefulWidget {
  const BookmarksScreen({super.key, required this.controller});

  final CommunityController controller;

  @override
  State<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends State<BookmarksScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() =>
      widget.controller.loadPosts(query: '', tagIds: const {});

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final bookmarks = controller.posts
          .where((post) => post.isBookmarked)
          .toList(growable: false);

      return Scaffold(
        backgroundColor: const Color(0xFFF8FBFF),
        appBar: AppBar(
          backgroundColor: const Color(0xFFF8FBFF),
          surfaceTintColor: Colors.transparent,
          leading: IconButton(
            tooltip: 'Back',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_ios_new),
          ),
          title: const Text('Bookmarks'),
          centerTitle: true,
        ),
        body: SafeArea(
          top: false,
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: controller.isLoading
                ? const Center(child: WauLoadingIndicator(size: 58))
                : controller.error != null
                ? _BookmarkMessage(
                    icon: Icons.cloud_off_outlined,
                    title: 'Bookmarks could not be loaded',
                    message: controller.error!,
                    actionLabel: 'Try again',
                    onAction: _refresh,
                  )
                : bookmarks.isEmpty
                ? const _BookmarkMessage(
                    icon: Icons.bookmark_border,
                    title: 'No bookmarks yet',
                    message:
                        'Posts and locations saved in Community Discovery will appear here.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: bookmarks.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 14),
                    itemBuilder: (context, index) => PostCard(
                      post: bookmarks[index],
                      controller: controller,
                    ),
                  ),
          ),
        ),
      );
    },
  );
}

class _BookmarkMessage extends StatelessWidget {
  const _BookmarkMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.symmetric(horizontal: 28),
    children: [
      const SizedBox(height: 150),
      Icon(icon, size: 58, color: const Color(0xFF65738B)),
      const SizedBox(height: 20),
      Text(
        title,
        textAlign: TextAlign.center,
        style: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 8),
      Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Color(0xFF65738B), height: 1.5),
      ),
      if (actionLabel != null && onAction != null) ...[
        const SizedBox(height: 20),
        Center(
          child: ElevatedButton(onPressed: onAction, child: Text(actionLabel!)),
        ),
      ],
    ],
  );
}
