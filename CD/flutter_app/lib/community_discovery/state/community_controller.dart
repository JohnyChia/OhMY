import 'package:flutter/foundation.dart';

import '../data/community_repository.dart';
import '../models/community_comment.dart';
import '../models/community_post.dart';
import '../models/completed_trip.dart';
import '../models/discovery_tag.dart';

class CommunityController extends ChangeNotifier {
  CommunityController(this._repository);

  final CommunityRepository _repository;
  List<CommunityPost> _posts = const [];
  Set<int> _selectedTagIds = {};
  List<DiscoveryTag> _tags = const [];
  String _query = '';
  bool _isLoading = false;
  String? _error;

  List<CommunityPost> get posts => List.unmodifiable(_posts);
  Set<int> get selectedTagIds => Set.unmodifiable(_selectedTagIds);
  List<DiscoveryTag> get tags => List.unmodifiable(_tags);
  String get query => _query;
  bool get isLoading => _isLoading;
  String? get error => _error;

  CommunityPost postById(String id) =>
      _posts.firstWhere((post) => post.id == id);

  Future<void> loadPosts({String? query, Set<int>? tagIds}) async {
    _query = query ?? _query;
    _selectedTagIds = tagIds ?? _selectedTagIds;
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      if (_tags.isEmpty) _tags = await _repository.getTags();
      _posts = await _repository.getPosts(
        query: _query,
        tagIds: _selectedTagIds,
      );
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
    final index = _posts.indexWhere((post) => post.id == postId);
    if (index < 0) return;
    final before = _posts[index];
    final liked = !before.isLiked;
    _posts[index] = before.copyWith(
      isLiked: liked,
      likeCount: before.likeCount + (liked ? 1 : -1),
    );
    notifyListeners();
    try {
      await _repository.setLiked(postId, liked);
    } catch (error) {
      _posts[index] = before;
      _error = _message(error);
      notifyListeners();
    }
  }

  Future<void> toggleBookmark(String postId) async {
    final index = _posts.indexWhere((post) => post.id == postId);
    if (index < 0) return;
    final before = _posts[index];
    final bookmarked = !before.isBookmarked;
    _posts[index] = before.copyWith(isBookmarked: bookmarked);
    notifyListeners();
    try {
      await _repository.setBookmarked(postId, bookmarked);
    } catch (error) {
      _posts[index] = before;
      _error = _message(error);
      notifyListeners();
    }
  }

  Future<List<CommunityComment>> getComments(String postId) =>
      _repository.getComments(postId);

  Future<CommunityComment> addComment(String postId, String content) async {
    final comment = await _repository.addComment(postId, content);
    final index = _posts.indexWhere((post) => post.id == postId);
    if (index >= 0) {
      _posts[index] = _posts[index].copyWith(
        commentCount: _posts[index].commentCount + 1,
      );
      notifyListeners();
    }
    return comment;
  }

  Future<List<CompletedTrip>> getEligibleTrips() =>
      _repository.getEligibleTrips();

  Future<CommunityPost> createPost(CreatePostInput input) async {
    final post = await _repository.createPost(input);
    _posts = [post, ..._posts];
    notifyListeners();
    return post;
  }

  String _message(Object error) => error
      .toString()
      .replaceFirst('Exception: ', '')
      .replaceFirst('Bad state: ', '');
}
