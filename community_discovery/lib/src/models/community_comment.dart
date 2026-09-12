class CommunityComment {
  const CommunityComment({
    required this.id,
    required this.postId,
    required this.authorName,
    required this.content,
    required this.createdAt,
    this.userId,
    this.isOwner = false,
  });

  final String id;
  final String postId;
  final String authorName;
  final String content;
  final DateTime createdAt;
  final String? userId;
  final bool isOwner;

  factory CommunityComment.fromMap(
    Map<String, dynamic> map, {
    String? currentUserId,
  }) {
    return CommunityComment(
      id: map['id'] as String,
      postId: map['post_id'] as String,
      authorName: map['author_name'] as String? ?? 'Traveller',
      content: map['content'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      userId: map['user_id'] as String?,
      isOwner:
          currentUserId != null && map['user_id']?.toString() == currentUserId,
    );
  }
}
