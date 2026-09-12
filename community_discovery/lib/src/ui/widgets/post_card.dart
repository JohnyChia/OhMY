import 'package:flutter/material.dart';

import '../../integration/community_integration_callbacks.dart';
import '../../models/community_post.dart';
import '../../state/community_controller.dart';
import '../post_detail_screen.dart';
import 'post_image.dart';

class PostCard extends StatelessWidget {
  const PostCard({
    super.key,
    required this.post,
    required this.controller,
    this.integrationCallbacks = const CommunityIntegrationCallbacks(),
  });

  final CommunityPost post;
  final CommunityController controller;
  final CommunityIntegrationCallbacks integrationCallbacks;

  void _openPost(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PostDetailScreen(
        postId: post.id,
        controller: controller,
        integrationCallbacks: integrationCallbacks,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: () => _openPost(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.primaryContainer,
                  child: Text(
                    _initial(post.authorName),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        post.authorName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        _relativeTime(post.createdAt),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          PostImage(post: post, height: 218),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 0),
            child: Text(
              post.title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
            child: Text(
              post.description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(height: 1.35),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Icon(
                  Icons.location_on_outlined,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    post.attractionName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 3, 6, 5),
            child: Row(
              children: [
                IconButton(
                  tooltip: post.isLiked ? 'Unlike' : 'Like',
                  onPressed: () => controller.toggleLike(post.id),
                  icon: Icon(
                    post.isLiked ? Icons.favorite : Icons.favorite_border,
                    color: post.isLiked ? Colors.pink : null,
                    size: 22,
                  ),
                ),
                Text('${post.likeCount}'),
                IconButton(
                  tooltip: 'Comments',
                  onPressed: () => _openPost(context),
                  icon: const Icon(Icons.chat_bubble_outline, size: 21),
                ),
                Text('${post.commentCount}'),
                const Spacer(),
                if (!post.isOwner)
                  IconButton(
                    tooltip: post.isBookmarked ? 'Remove bookmark' : 'Bookmark',
                    onPressed: () => controller.toggleBookmark(post.id),
                    icon: Icon(
                      post.isBookmarked
                          ? Icons.bookmark
                          : Icons.bookmark_border,
                      color: post.isBookmarked
                          ? Theme.of(context).colorScheme.primary
                          : null,
                      size: 22,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

String _initial(String name) {
  final trimmed = name.trim();
  return trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();
}

String _relativeTime(DateTime value) {
  final difference = DateTime.now().difference(value);
  if (difference.inMinutes < 1) return 'Now';
  if (difference.inHours < 1) return '${difference.inMinutes}m';
  if (difference.inDays < 1) return '${difference.inHours}h';
  return '${difference.inDays}d';
}
