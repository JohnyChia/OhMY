import 'package:flutter/material.dart';

import '../../models/community_post.dart';
import '../../state/community_controller.dart';
import '../post_detail_screen.dart';
import 'post_image.dart';

class PostCard extends StatelessWidget {
  const PostCard({super.key, required this.post, required this.controller});

  final CommunityPost post;
  final CommunityController controller;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              PostDetailScreen(postId: post.id, controller: controller),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PostImage(post: post),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 13,
                  child: Icon(Icons.person, size: 16),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('${post.authorName}  •  Verified traveller'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              post.attractionName,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
            child: Text('${post.locationName} • ${post.tags.join(' • ')}'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              post.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
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
