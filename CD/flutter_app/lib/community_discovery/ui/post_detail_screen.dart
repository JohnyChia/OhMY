import 'package:flutter/material.dart';

import '../models/community_comment.dart';
import '../state/community_controller.dart';
import 'widgets/post_image.dart';

class PostDetailScreen extends StatefulWidget {
  const PostDetailScreen({
    super.key,
    required this.postId,
    required this.controller,
  });

  final String postId;
  final CommunityController controller;

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final _commentController = TextEditingController();
  late Future<List<CommunityComment>> _comments;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _comments = widget.controller.getComments(widget.postId);
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submitComment() async {
    final content = _commentController.text.trim();
    if (content.isEmpty || content.length > 500) return;
    setState(() => _submitting = true);
    try {
      await widget.controller.addComment(widget.postId, content);
      _commentController.clear();
      setState(() => _comments = widget.controller.getComments(widget.postId));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Comment was not sent: $error')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final post = widget.controller.postById(widget.postId);
      return Scaffold(
        appBar: AppBar(title: const Text('Post details')),
        body: ListView(
          padding: const EdgeInsets.only(bottom: 30),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
              child: Row(
                children: [
                  const CircleAvatar(child: Icon(Icons.person_outline)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          post.authorName,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const Text('Verified traveller'),
                      ],
                    ),
                  ),
                  Text(_relativeTime(post.createdAt)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Text(
                post.attractionName,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 2, 18, 10),
              child: Text('${post.locationName} • ${post.tags.join(' • ')}'),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
              child: Text(post.description),
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: PostImage(post: post, height: 320),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: () => widget.controller.toggleLike(post.id),
                    icon: Icon(
                      post.isLiked ? Icons.favorite : Icons.favorite_border,
                      color: post.isLiked ? Colors.pink : null,
                    ),
                    label: Text(post.isLiked ? 'Liked' : 'Like'),
                  ),
                  Text('${post.likeCount}'),
                  const SizedBox(width: 8),
                  const Icon(Icons.chat_bubble_outline, size: 19),
                  const SizedBox(width: 5),
                  Text('${post.commentCount}'),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => widget.controller.toggleBookmark(post.id),
                    icon: Icon(
                      post.isBookmarked
                          ? Icons.bookmark
                          : Icons.bookmark_border,
                    ),
                    label: Text(post.isBookmarked ? 'Bookmarked' : 'Bookmark'),
                  ),
                ],
              ),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 8),
              child: Text(
                'Comments',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            FutureBuilder<List<CommunityComment>>(
              future: _comments,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(18),
                    child: Text(
                      'Comments could not be loaded: ${snapshot.error}',
                    ),
                  );
                }
                final comments = snapshot.data ?? const [];
                if (comments.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    child: Text('No comments yet. Be the first to comment.'),
                  );
                }
                return Column(
                  children: comments
                      .map(
                        (comment) => ListTile(
                          leading: const CircleAvatar(
                            child: Icon(Icons.person, size: 18),
                          ),
                          title: Text(comment.authorName),
                          subtitle: Text(comment.content),
                          trailing: Text(_relativeTime(comment.createdAt)),
                        ),
                      )
                      .toList(),
                );
              },
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _commentController,
                      minLines: 1,
                      maxLines: 3,
                      maxLength: 500,
                      decoration: const InputDecoration(
                        hintText: 'Add a comment…',
                        counterText: '',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'Send comment',
                    onPressed: _submitting ? null : _submitComment,
                    icon: _submitting
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

String _relativeTime(DateTime value) {
  final difference = DateTime.now().difference(value);
  if (difference.inMinutes < 1) return 'Now';
  if (difference.inHours < 1) return '${difference.inMinutes}m';
  if (difference.inDays < 1) return '${difference.inHours}h';
  return '${difference.inDays}d';
}
