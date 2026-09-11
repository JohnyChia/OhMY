import 'dart:typed_data';

class CommunityPost {
  const CommunityPost({
    required this.id,
    required this.title,
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
    required this.isOwner,
    required this.tagIds,
    required this.moderationStatus,
    this.authorId,
    this.tripSessionId,
    this.historyEntryId,
    this.imagePath,
    this.imageUrl,
    this.imagePaths = const [],
    this.imageUrls = const [],
    this.imageBytes,
  });

  final String id;
  final String title;
  final String? authorId;
  final String authorName;
  final String? tripSessionId;
  final String? historyEntryId;
  final String locationName;
  final String attractionName;
  final String description;
  final List<String> tags;
  final DateTime createdAt;
  final int likeCount;
  final int commentCount;
  final bool isLiked;
  final bool isBookmarked;
  final bool isOwner;
  final List<int> tagIds;
  final String moderationStatus;
  final String? imagePath;
  final String? imageUrl;
  final List<String> imagePaths;
  final List<String> imageUrls;
  final Uint8List? imageBytes;

  List<String> get allImageUrls => imageUrls.isNotEmpty
      ? imageUrls
      : imageUrl == null || imageUrl!.isEmpty
      ? const []
      : [imageUrl!];

  CommunityPost copyWith({
    String? title,
    String? description,
    List<String>? tags,
    List<int>? tagIds,
    int? likeCount,
    int? commentCount,
    bool? isLiked,
    bool? isBookmarked,
    String? imageUrl,
    String? imagePath,
    List<String>? imagePaths,
    List<String>? imageUrls,
  }) => CommunityPost(
    id: id,
    title: title ?? this.title,
    authorId: authorId,
    authorName: authorName,
    tripSessionId: tripSessionId,
    historyEntryId: historyEntryId,
    locationName: locationName,
    attractionName: attractionName,
    description: description ?? this.description,
    tags: tags ?? this.tags,
    tagIds: tagIds ?? this.tagIds,
    createdAt: createdAt,
    likeCount: likeCount ?? this.likeCount,
    commentCount: commentCount ?? this.commentCount,
    isLiked: isLiked ?? this.isLiked,
    isBookmarked: isBookmarked ?? this.isBookmarked,
    isOwner: isOwner,
    moderationStatus: moderationStatus,
    imagePath: imagePath ?? this.imagePath,
    imageUrl: imageUrl ?? this.imageUrl,
    imagePaths: imagePaths ?? this.imagePaths,
    imageUrls: imageUrls ?? this.imageUrls,
    imageBytes: imageBytes,
  );

  factory CommunityPost.fromFeedMap(
    Map<String, dynamic> map, {
    required bool isLiked,
    required bool isBookmarked,
    String? publicImageUrl,
    List<String> publicImageUrls = const [],
  }) => CommunityPost(
    id: map['id'] as String,
    title: map['title'] as String? ?? map['attraction_name'] as String? ?? '',
    authorId: map['author_id'] as String?,
    authorName: map['author_name'] as String? ?? 'Traveller',
    tripSessionId: map['trip_session_id'] as String?,
    historyEntryId: map['history_entry_id'] as String?,
    locationName: map['location_name'] as String,
    attractionName: map['attraction_name'] as String,
    description: map['description'] as String,
    tags: List<String>.from(map['tags'] as List? ?? const []),
    createdAt: DateTime.parse(map['created_at'] as String),
    likeCount: (map['like_count'] as num?)?.toInt() ?? 0,
    commentCount: (map['comment_count'] as num?)?.toInt() ?? 0,
    isLiked: isLiked,
    isBookmarked: isBookmarked,
    isOwner: map['is_owner'] as bool? ?? false,
    tagIds: (map['tag_ids'] as List? ?? const [])
        .map((value) => (value as num).toInt())
        .toList(growable: false),
    moderationStatus: map['moderation_status'] as String? ?? 'approved',
    imagePath: map['image_path'] as String?,
    imageUrl: publicImageUrl,
    imagePaths: List<String>.from(map['image_paths'] as List? ?? const []),
    imageUrls: publicImageUrls,
  );
}
