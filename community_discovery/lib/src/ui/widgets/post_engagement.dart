import '../../models/community_post.dart';

int displayedLikeCount(CommunityPost post, {required bool includeDemo}) {
  if (!includeDemo) return post.likeCount;
  return post.likeCount + 24 + (_stableSeed(post.id) % 97);
}

int _stableSeed(String value) => value.codeUnits.fold<int>(
  0,
  (total, codeUnit) => (total * 31 + codeUnit) & 0x7fffffff,
);
