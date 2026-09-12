import 'package:flutter/material.dart';

import '../integration/community_integration_callbacks.dart';
import '../models/community_comment.dart';
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
  String? _commentError;
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
      setState(() => _commentError = 'Comments must be 1–500 characters.');
      return;
    }
    setState(() {
      _submitting = true;
      _commentError = null;
    });
    try {
      await widget.controller.addComment(widget.postId, content);
      _commentController.clear();
      setState(() => _comments = widget.controller.getComments(widget.postId));
    } catch (error) {
      if (mounted) {
        final message = error
            .toString()
            .replaceFirst('Bad state: ', '')
            .replaceFirst('Exception: ', '');
        setState(() => _commentError = message);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<bool> _confirmDelete(String message) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete permanently?'),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _deletePost() async {
    if (!await _confirmDelete(
      'This post and all of its comments will be deleted.',
    )) {
      return;
    }
    try {
      await widget.controller.deletePost(widget.postId);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Post could not be deleted: $error')),
        );
      }
    }
  }

  Future<void> _deleteComment(CommunityComment comment) async {
    if (!await _confirmDelete('This comment will be deleted.')) return;
    try {
      await widget.controller.deleteComment(widget.postId, comment.id);
      if (mounted) {
        setState(
          () => _comments = widget.controller.getComments(widget.postId),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Comment could not be deleted: $error')),
        );
      }
    }
  }

  Future<void> _startJourney() async {
    final post = widget.controller.postById(widget.postId);
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
  }

  Widget _commentComposer(ColorScheme colorScheme) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            controller: _commentController,
            onChanged: (_) {
              if (_commentError != null) {
                setState(() => _commentError = null);
              }
            },
            minLines: 1,
            maxLines: 3,
            maxLength: 500,
            decoration: InputDecoration(
              hintText: 'Add a comment...',
              counterText: '',
              errorText: _commentError,
              errorMaxLines: 4,
              filled: true,
              fillColor: colorScheme.surface,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: BorderSide(color: colorScheme.outlineVariant),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: BorderSide(
                  color: colorScheme.outlineVariant,
                  width: 1.2,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: BorderSide(color: colorScheme.primary, width: 1.6),
              ),
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
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final post = widget.controller.postById(widget.postId);
      final colorScheme = Theme.of(context).colorScheme;
      final imageHeight = (MediaQuery.sizeOf(context).width * 0.74).clamp(
        240.0,
        300.0,
      );
      return Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          toolbarHeight: 0,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
        body: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            Container(
              color: colorScheme.surface,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back),
                  ),
                  const SizedBox(width: 2),
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: colorScheme.primaryContainer,
                    child: Text(
                      _initial(post.authorName),
                      style: TextStyle(
                        color: colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          post.authorName,
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          _relativeTime(post.createdAt),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  if (post.isOwner)
                    IconButton(
                      tooltip: 'Edit post',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () async {
                        final result = await Navigator.of(context).push(
                          MaterialPageRoute<PostEditorResult>(
                            builder: (_) => CreatePostScreen(
                              controller: widget.controller,
                              post: post,
                            ),
                          ),
                        );
                        if (result == PostEditorResult.deleted &&
                            context.mounted) {
                          Navigator.pop(context, true);
                        }
                      },
                    ),
                  if (post.isOwner)
                    IconButton(
                      tooltip: 'Delete post',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: _deletePost,
                    ),
                ],
              ),
            ),
            PostImage(
              post: post,
              height: imageHeight,
              fit: BoxFit.cover,
              openFullscreenOnTap: true,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Text(
                post.title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                post.description,
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(height: 1.4),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      colorScheme.primaryContainer.withValues(alpha: 0.68),
                      colorScheme.surfaceContainerLow,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: _startJourney,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: colorScheme.surface,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.location_on_outlined,
                              color: colorScheme.primary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'VISIT THIS PLACE',
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: colorScheme.primary,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.7,
                                      ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  post.attractionName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  post.locationName,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          IconButton.filled(
                            tooltip: 'Start trip to this place',
                            onPressed: _startJourney,
                            icon: const Icon(Icons.directions_outlined),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
              child: Row(
                children: [
                  IconButton(
                    tooltip: post.isLiked ? 'Unlike' : 'Like',
                    onPressed: () => widget.controller.toggleLike(post.id),
                    icon: Icon(
                      post.isLiked ? Icons.favorite : Icons.favorite_border,
                      color: post.isLiked ? Colors.pink : null,
                    ),
                  ),
                  Text('${post.likeCount}'),
                  const SizedBox(width: 14),
                  const Icon(Icons.chat_bubble_outline, size: 20),
                  const SizedBox(width: 6),
                  Text('${post.commentCount}'),
                  const Spacer(),
                  if (!post.isOwner)
                    IconButton(
                      tooltip: post.isBookmarked
                          ? 'Remove bookmark'
                          : 'Bookmark',
                      onPressed: () =>
                          widget.controller.toggleBookmark(post.id),
                      icon: Icon(
                        post.isBookmarked
                            ? Icons.bookmark
                            : Icons.bookmark_border,
                        color: post.isBookmarked ? colorScheme.primary : null,
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
              child: Row(
                children: [
                  Text(
                    'Comments',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${post.commentCount}',
                      style: TextStyle(
                        color: colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _commentComposer(colorScheme),
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
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Comments could not be loaded: ${snapshot.error}',
                    ),
                  );
                }
                final comments = snapshot.data ?? const [];
                if (comments.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Text(
                      'No comments yet. Be the first to comment.',
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                  );
                }
                return Column(
                  children: comments
                      .map(
                        (comment) => Padding(
                          padding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: colorScheme.primary,
                                child: Text(
                                  _initial(comment.authorName),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    9,
                                    12,
                                    10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colorScheme.surface,
                                    border: Border.all(
                                      color: colorScheme.outlineVariant,
                                    ),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Color(0x0D000000),
                                        blurRadius: 6,
                                        offset: Offset(0, 2),
                                      ),
                                    ],
                                    borderRadius: const BorderRadius.only(
                                      topLeft: Radius.circular(4),
                                      topRight: Radius.circular(16),
                                      bottomLeft: Radius.circular(16),
                                      bottomRight: Radius.circular(16),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              comment.authorName,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                          Text(
                                            _relativeTime(comment.createdAt),
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color: colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        comment.content,
                                        style: const TextStyle(height: 1.35),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              if (comment.isOwner || post.isOwner)
                                IconButton(
                                  tooltip: 'Delete comment',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () => _deleteComment(comment),
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 20,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            ),
          ],
        ),
      );
    },
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
