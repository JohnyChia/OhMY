import 'dart:async';

import 'package:community_discovery/src/state/community_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_community_repository.dart';

void main() {
  test('rapid like and bookmark taps do not overlap requests', () async {
    final repository = _DelayedCommunityRepository();
    final controller = CommunityController(repository);
    addTearDown(controller.dispose);
    await controller.loadPosts();

    final firstLike = controller.toggleLike('post-1');
    final secondLike = controller.toggleLike('post-1');
    expect(controller.isLikePending('post-1'), isTrue);
    expect(repository.likeCalls, 1);
    repository.likeRequest.complete();
    await Future.wait([firstLike, secondLike]);

    final firstBookmark = controller.toggleBookmark('post-1');
    final secondBookmark = controller.toggleBookmark('post-1');
    expect(controller.isBookmarkPending('post-1'), isTrue);
    expect(repository.bookmarkCalls, 1);
    repository.bookmarkRequest.complete();
    await Future.wait([firstBookmark, secondBookmark]);

    expect(controller.isLikePending('post-1'), isFalse);
    expect(controller.isBookmarkPending('post-1'), isFalse);
    expect(controller.error, isNull);
  });

  test('failed engagement action rolls back without hiding the feed', () async {
    final controller = CommunityController(_FailingCommunityRepository());
    addTearDown(controller.dispose);
    await controller.loadPosts();

    await controller.toggleLike('post-1');

    expect(controller.posts.single.isLiked, isFalse);
    expect(controller.posts.single.likeCount, 0);
    expect(controller.error, isNull);
  });
}

class _DelayedCommunityRepository extends FakeCommunityRepository {
  final likeRequest = Completer<void>();
  final bookmarkRequest = Completer<void>();
  int likeCalls = 0;
  int bookmarkCalls = 0;

  @override
  Future<void> setLiked(String postId, bool liked) {
    likeCalls++;
    return likeRequest.future;
  }

  @override
  Future<void> setBookmarked(String postId, bool bookmarked) {
    bookmarkCalls++;
    return bookmarkRequest.future;
  }
}

class _FailingCommunityRepository extends FakeCommunityRepository {
  @override
  Future<void> setLiked(String postId, bool liked) =>
      Future<void>.error(StateError('RLS rejected the request'));
}
