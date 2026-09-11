import 'package:flutter/material.dart';

import '../../models/community_post.dart';
import '../../integration/community_integration_callbacks.dart';
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

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PostDetailScreen(
            postId: post.id,
            controller: controller,
            integrationCallbacks: integrationCallbacks,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PostImage(post: post),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 13,
                  child: Icon(Icons.person, size: 16),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${post.authorName}  •  Verified traveller',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text(
              post.title,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 2, 14, 6),
            child: Text(
              '${post.attractionName} • ${post.locationName}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text(
              post.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 2, 4, 4),
            child: Row(
              children: [
                IconButton(
                  tooltip: post.isLiked ? 'Unlike' : 'Like',
                  onPressed: () => controller.toggleLike(post.id),
                  icon: Icon(
                    post.isLiked ? Icons.favorite : Icons.favorite_border,
                    color: post.isLiked ? Colors.pink : null,
                  ),
                ),
                Text('${post.likeCount}'),
                IconButton(
                  tooltip: 'Comments',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PostDetailScreen(
                        postId: post.id,
                        controller: controller,
                        integrationCallbacks: integrationCallbacks,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.chat_bubble_outline),
                ),
                Text('${post.commentCount}'),
                const Spacer(),
                IconButton(
                  tooltip: post.isBookmarked ? 'Remove bookmark' : 'Bookmark',
                  onPressed: () => controller.toggleBookmark(post.id),
                  icon: Icon(
                    post.isBookmarked ? Icons.bookmark : Icons.bookmark_border,
                    color: post.isBookmarked
                        ? Theme.of(context).colorScheme.primary
                        : null,
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
