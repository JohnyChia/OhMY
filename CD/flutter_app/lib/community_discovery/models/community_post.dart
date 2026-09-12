import 'dart:typed_data';

class CommunityPost {
  const CommunityPost({
    required this.id,
    required this.authorName,
    required this.locationName,
    required this.attractionName,
    required this.description,
    required this.tags,
    required this.createdAt,
    required this.likeCount,
    required this.commentCount,
    required this.isLiked,
    required this.isBookmarked,
    this.imageUrl,
    this.imageBytes,
  });

  final String id;
  final String authorName;
  final String locationName;
  final String attractionName;
  final String description;
  final List<String> tags;
  final DateTime createdAt;
  final int likeCount;
  final int commentCount;
  final bool isLiked;
  final bool isBookmarked;
  final String? imageUrl;
  final Uint8List? imageBytes;

  CommunityPost copyWith({
    int? likeCount,
    int? commentCount,
    bool? isLiked,
    bool? isBookmarked,
  }) => CommunityPost(
    id: id,
    authorName: authorName,
    locationName: locationName,
    attractionName: attractionName,
    description: description,
    tags: tags,
    createdAt: createdAt,
    likeCount: likeCount ?? this.likeCount,
    commentCount: commentCount ?? this.commentCount,
    isLiked: isLiked ?? this.isLiked,
    isBookmarked: isBookmarked ?? this.isBookmarked,
    imageUrl: imageUrl,
    imageBytes: imageBytes,
  );

  factory CommunityPost.fromFeedMap(
    Map<String, dynamic> map, {
    required bool isLiked,
    required bool isBookmarked,
    String? publicImageUrl,
  }) => CommunityPost(
    id: map['id'] as String,
    authorName: map['author_name'] as String? ?? 'Traveller',
    locationName: map['location_name'] as String,
    attractionName: map['attraction_name'] as String,
    description: map['description'] as String,
    tags: List<String>.from(map['tags'] as List? ?? const []),
    createdAt: DateTime.parse(map['created_at'] as String),
    likeCount: (map['like_count'] as num?)?.toInt() ?? 0,
    commentCount: (map['comment_count'] as num?)?.toInt() ?? 0,
    isLiked: isLiked,
    isBookmarked: isBookmarked,
    imageUrl: publicImageUrl,
  );
}
