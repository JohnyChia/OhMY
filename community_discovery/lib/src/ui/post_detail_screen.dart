import 'package:flutter/material.dart';

import '../models/community_comment.dart';
import '../integration/community_integration_callbacks.dart';
import '../state/community_controller.dart';
import 'create_post_screen.dart';
import 'widgets/post_image.dart';

class PostDetailScreen extends StatefulWidget {
  const PostDetailScreen({
    super.key,
    required this.postId,
    required this.controller,
    this.integrationCallbacks = const CommunityIntegrationCallbacks(),
  });

  final String postId;
  final CommunityController controller;
  final CommunityIntegrationCallbacks integrationCallbacks;

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final _commentController = TextEditingController();
  late Future<List<CommunityComment>> _comments;
  bool _submitting = false;
  late int _lastCommentCount;

  @override
  void initState() {
    super.initState();
    _comments = widget.controller.getComments(widget.postId);
    _lastCommentCount = widget.controller.postById(widget.postId).commentCount;
    widget.controller.addListener(_syncComments);
  }

  void _syncComments() {
    final count = widget.controller.postById(widget.postId).commentCount;
    if (count == _lastCommentCount || !mounted) return;
    _lastCommentCount = count;
    setState(() => _comments = widget.controller.getComments(widget.postId));
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncComments);
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submitComment() async {
    if (_submitting) return;
    final content = _commentController.text.trim();
    if (content.isEmpty || content.length > 500) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Comments must be 1–500 characters.')),
      );
      return;
    }
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
        appBar: AppBar(
          actions: [
            if (post.isOwner)
              IconButton(
                tooltip: 'Edit post',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => CreatePostScreen(
                        controller: widget.controller,
                        post: post,
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.only(bottom: 30),
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(18),
              ),
              child: PostImage(
                post: post,
                height: 360,
                fit: BoxFit.contain,
                openFullscreenOnTap: true,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 4),
              child: Text(
                post.title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: ListTile(
                leading: const Icon(Icons.location_on_outlined),
                title: Text(post.attractionName),
                subtitle: Text(post.locationName),
                trailing: const Icon(Icons.directions_outlined),
                onTap: () async {
                  final callback = widget.integrationCallbacks.onStartJourney;
                  if (callback == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Connect onStartJourney to open this location in the main app.',
                        ),
                      ),
                    );
                    return;
                  }
                  await callback(
                    StartJourneyRequest(
                      postId: post.id,
                      attractionName: post.attractionName,
                      destinationName: post.locationName,
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
              child: Text(post.description),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 2),
              child: Text(
                '${post.authorName} · Verified traveller · ${_relativeTime(post.createdAt)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
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
                        (comment) => Container(
                          margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF4F7FC),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: ListTile(
                            dense: true,
                            leading: const CircleAvatar(
                              radius: 16,
                              child: Icon(Icons.person, size: 16),
                            ),
                            title: Text(
                              comment.authorName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(comment.content),
                            trailing: Text(_relativeTime(comment.createdAt)),
                          ),
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
