import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/community_repository.dart';
import '../models/community_comment.dart';
import '../models/community_post.dart';
import '../models/completed_trip.dart';
import '../models/discovery_tag.dart';

class CommunityController extends ChangeNotifier {
  CommunityController(this._repository) {
    _changesSubscription = _repository.changes.listen((_) {
      _realtimeDebounce?.cancel();
      _realtimeDebounce = Timer(const Duration(milliseconds: 250), () {
        unawaited(loadPosts(silent: true));
        if (_bookmarksLoaded) unawaited(loadBookmarkedPosts());
      });
    });
  }

  final CommunityRepository _repository;
  List<CommunityPost> _posts = const [];
  List<CommunityPost> _bookmarkedPosts = const [];
  final Map<String, CommunityPost> _postCache = {};
  bool _bookmarksLoaded = false;
  Set<int> _selectedTagIds = {};
  List<DiscoveryTag> _tags = const [];
  String _query = '';
  bool _isLoading = false;
  bool _tagsLoading = false;
  bool _tagsLoaded = false;
  String? _tagsError;
  String? _error;
  StreamSubscription<void>? _changesSubscription;
  Timer? _realtimeDebounce;

  List<CommunityPost> get posts => List.unmodifiable(_posts);
  List<CommunityPost> get bookmarkedPosts =>
      List.unmodifiable(_bookmarkedPosts);
  Set<int> get selectedTagIds => Set.unmodifiable(_selectedTagIds);
  List<DiscoveryTag> get tags => List.unmodifiable(_tags);
  String get query => _query;
  bool get isLoading => _isLoading;
  bool get tagsLoading => _tagsLoading;
  bool get tagsLoaded => _tagsLoaded;
  String? get tagsError => _tagsError;
  String? get error => _error;

  CommunityPost postById(String id) {
    return _postCache[id] ??
        _posts.followedBy(_bookmarkedPosts).firstWhere((post) => post.id == id);
  }

  void _replacePost(CommunityPost post) {
    _postCache[post.id] = post;
    final feedIndex = _posts.indexWhere((item) => item.id == post.id);
    if (feedIndex >= 0) _posts[feedIndex] = post;
    final bookmarkIndex = _bookmarkedPosts.indexWhere(
      (item) => item.id == post.id,
    );
    if (bookmarkIndex >= 0) _bookmarkedPosts[bookmarkIndex] = post;
  }

  Future<void> loadPosts({
    String? query,
    Set<int>? tagIds,
    bool silent = false,
  }) async {
    _query = query ?? _query;
    _selectedTagIds = tagIds ?? _selectedTagIds;
    _isLoading = !silent;
    _error = null;
    notifyListeners();
    try {
      _posts = await _repository.getPosts(
        query: _query,
        tagIds: _selectedTagIds,
      );
      for (final post in _posts) {
        _postCache[post.id] = post;
      }
    } catch (error) {
      _error = _message(error);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> toggleTag(int tagId) async {
    final next = Set<int>.from(_selectedTagIds);
    next.contains(tagId) ? next.remove(tagId) : next.add(tagId);
    await loadPosts(tagIds: next);
  }

  Future<void> clearTags() => loadPosts(tagIds: {});

  Future<void> toggleLike(String postId) async {
    final before = postById(postId);
    final liked = !before.isLiked;
    _replacePost(
      before.copyWith(
        isLiked: liked,
        likeCount: before.likeCount + (liked ? 1 : -1),
      ),
    );
    notifyListeners();
    try {
      await _repository.setLiked(postId, liked);
    } catch (error) {
      _replacePost(before);
      _error = _message(error);
      notifyListeners();
    }
  }

  Future<void> toggleBookmark(String postId) async {
    final before = postById(postId);
    final bookmarked = !before.isBookmarked;
    _replacePost(before.copyWith(isBookmarked: bookmarked));
    notifyListeners();
    try {
      await _repository.setBookmarked(postId, bookmarked);
      if (_bookmarksLoaded) await loadBookmarkedPosts();
    } catch (error) {
      _replacePost(before);
      _error = _message(error);
      notifyListeners();
    }
  }

  Future<List<CommunityComment>> getComments(String postId) =>
      _repository.getComments(postId);

  Future<CommunityComment> addComment(String postId, String content) async {
    final comment = await _repository.addComment(postId, content);
    final before = postById(postId);
    _replacePost(before.copyWith(commentCount: before.commentCount + 1));
    notifyListeners();
    return comment;
  }

  Future<List<CompletedTrip>> getEligibleTrips() =>
      _repository.getEligibleTrips();

  Future<CommunityPost?> getPostForTripSession(String tripSessionId) =>
      _repository.getPostForTripSession(tripSessionId);

  Future<void> loadTags({bool force = false}) async {
    if (_tagsLoading || (_tagsLoaded && !force)) return;
    _tagsLoading = true;
    _tagsError = null;
    notifyListeners();
    try {
      _tags = await _repository.getTags();
      _tagsLoaded = true;
    } catch (error) {
      _tagsError = _message(error);
    } finally {
      _tagsLoading = false;
      notifyListeners();
    }
  }

  Future<void> ensureTags() => loadTags();

  Future<void> loadBookmarkedPosts() async {
    _bookmarksLoaded = true;
    try {
      _bookmarkedPosts = await _repository.getPosts(bookmarkedOnly: true);
      for (final post in _bookmarkedPosts) {
        _postCache[post.id] = post;
      }
      notifyListeners();
    } catch (error) {
      _error = _message(error);
      notifyListeners();
    }
  }

  Future<CommunityPost> createPost(CreatePostInput input) async {
    final post = await _repository.createPost(input);
    _posts = [post, ..._posts];
    _postCache[post.id] = post;
    notifyListeners();
    return post;
  }

  Future<CommunityPost> updatePost(UpdatePostInput input) async {
    final post = await _repository.updatePost(input);
    _replacePost(post);
    notifyListeners();
    return post;
  }

  @override
  void dispose() {
    _realtimeDebounce?.cancel();
    _changesSubscription?.cancel();
    unawaited(_repository.dispose());
    super.dispose();
  }

  String _message(Object error) => error
      .toString()
      .replaceFirst('Exception: ', '')
      .replaceFirst('Bad state: ', '');
}
