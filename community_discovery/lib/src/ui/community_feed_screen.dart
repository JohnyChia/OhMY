import 'dart:async';

import 'package:flutter/material.dart';

import '../models/community_post.dart';
import '../models/discovery_tag.dart';
import '../state/community_controller.dart';
import '../integration/community_integration_callbacks.dart';
import '../theme/community_theme.dart';
import 'bookmarked_posts_screen.dart';
import 'widgets/post_engagement.dart';
import 'widgets/post_card.dart';

enum _PostSort { latest, mostLiked }

class CommunityFeedScreen extends StatefulWidget {
  const CommunityFeedScreen({
    super.key,
    required this.controller,
    this.integrationCallbacks = const CommunityIntegrationCallbacks(),
    this.showBottomNavigation = true,
    this.preferredTagNames,
    this.includeDemoLikes = false,
  });

  final CommunityController controller;
  final CommunityIntegrationCallbacks integrationCallbacks;
  final List<String>? preferredTagNames;
  final bool includeDemoLikes;

  /// Keep this enabled only when Community Discovery runs as a standalone app.
  /// The host OhMY shell owns the real navigation after integration.
  final bool showBottomNavigation;

  @override
  State<CommunityFeedScreen> createState() => _CommunityFeedScreenState();
}

class _CommunityFeedScreenState extends State<CommunityFeedScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  _PostSort _sort = _PostSort.latest;

  @override
  void initState() {
    super.initState();
    unawaited(widget.controller.loadTags());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !widget.controller.isLoading) {
        unawaited(widget.controller.loadPosts());
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _search(String value) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => widget.controller.loadPosts(query: value),
    );
  }

  List<DiscoveryTag> _visibleTags(List<DiscoveryTag> tags) {
    final preferences = widget.preferredTagNames;
    if (preferences == null) return tags;
    final normalized = preferences
        .map((value) => value.trim().toLowerCase())
        .where((value) => value.isNotEmpty)
        .toSet();
    return tags
        .where((tag) => normalized.contains(tag.name.trim().toLowerCase()))
        .toList(growable: false);
  }

  List<CommunityPost> _sortedPosts(List<CommunityPost> posts) {
    final sorted = List<CommunityPost>.of(posts);
    switch (_sort) {
      case _PostSort.latest:
        sorted.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case _PostSort.mostLiked:
        sorted.sort((a, b) {
          final likes =
              displayedLikeCount(
                b,
                includeDemo: widget.includeDemoLikes,
              ).compareTo(
                displayedLikeCount(a, includeDemo: widget.includeDemoLikes),
              );
          return likes != 0 ? likes : b.createdAt.compareTo(a.createdAt);
        });
        break;
    }
    return sorted;
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final state = widget.controller;
      final visibleTags = _visibleTags(state.tags);
      final visiblePosts = _sortedPosts(state.posts);
      return Scaffold(
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: () async {
              await Future.wait([
                state.loadTags(force: true),
                state.loadPosts(),
              ]);
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: _Header(
                    controller: _searchController,
                    onSearch: _search,
                    onFilter: _showFilters,
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Community finds',
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              if (state.selectedTagIds.isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Text(
                                  '${state.selectedTagIds.length} discovery filter(s) selected',
                                ),
                              ],
                            ],
                          ),
                        ),
                        PopupMenuButton<_PostSort>(
                          tooltip: 'Arrange posts',
                          initialValue: _sort,
                          onSelected: (value) => setState(() => _sort = value),
                          itemBuilder: (context) => const [
                            PopupMenuItem(
                              value: _PostSort.latest,
                              child: Text('Latest'),
                            ),
                            PopupMenuItem(
                              value: _PostSort.mostLiked,
                              child: Text('Most liked'),
                            ),
                          ],
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 9,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: Theme.of(
                                  context,
                                ).colorScheme.outlineVariant,
                              ),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.swap_vert, size: 18),
                                const SizedBox(width: 5),
                                Text(
                                  _sort == _PostSort.latest
                                      ? 'Latest'
                                      : 'Most liked',
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: visibleTags.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.fromLTRB(18, 0, 18, 10),
                          child: Text(
                            'No saved preference tags are available.',
                          ),
                        )
                      : SizedBox(
                          height: 46,
                          child: ListView(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            scrollDirection: Axis.horizontal,
                            children: visibleTags.map((tag) {
                              final selected = state.selectedTagIds.contains(
                                tag.id,
                              );
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                child: FilterChip(
                                  label: Text(tag.name),
                                  selected: selected,
                                  onSelected: (_) => state.toggleTag(tag.id),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                ),
                if (state.isLoading)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (state.error != null)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _MessageState(
                      icon: Icons.cloud_off_outlined,
                      title: 'Community posts could not be loaded',
                      message: state.error!,
                      actionLabel: 'Try again',
                      onAction: state.loadPosts,
                    ),
                  )
                else if (state.posts.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _MessageState(
                      icon: Icons.travel_explore,
                      title: state.query.isEmpty && state.selectedTagIds.isEmpty
                          ? 'No community posts yet'
                          : 'No posts found',
                      message:
                          state.query.isEmpty && state.selectedTagIds.isEmpty
                          ? 'Completed-trip stories will appear here.'
                          : 'Try a different destination, attraction, description, or tag.',
                      actionLabel:
                          state.query.isEmpty && state.selectedTagIds.isEmpty
                          ? null
                          : 'Clear filters',
                      onAction:
                          state.query.isEmpty && state.selectedTagIds.isEmpty
                          ? null
                          : () {
                              _searchController.clear();
                              state.loadPosts(query: '', tagIds: {});
                            },
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
                    sliver: SliverList.separated(
                      itemCount: visiblePosts.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 14),
                      itemBuilder: (context, index) => PostCard(
                        post: visiblePosts[index],
                        controller: state,
                        integrationCallbacks: widget.integrationCallbacks,
                        includeDemoLikes: widget.includeDemoLikes,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        bottomNavigationBar: widget.showBottomNavigation
            ? NavigationBar(
                selectedIndex: 3,
                onDestinationSelected: (index) {
                  if (index == 4) {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => BookmarkedPostsScreen(
                          controller: state,
                          integrationCallbacks: widget.integrationCallbacks,
                        ),
                      ),
                    );
                  } else if (index != 3) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'This build contains Community Discovery only.',
                        ),
                      ),
                    );
                  }
                },
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.home_outlined),
                    label: 'Home',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.smart_toy_outlined),
                    label: 'AI Chat',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.luggage_outlined),
                    label: 'Start Trip',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.map_outlined),
                    label: 'Community',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.person_outline),
                    label: 'Profile',
                  ),
                ],
              )
            : null,
      );
    },
  );

  Future<void> _showFilters() async {
    final result = await showModalBottomSheet<Set<int>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _TagFilterSheet(controller: widget.controller),
    );
    if (result != null) await widget.controller.loadPosts(tagIds: result);
  }
}

class _TagFilterSheet extends StatefulWidget {
  const _TagFilterSheet({required this.controller});

  final CommunityController controller;

  @override
  State<_TagFilterSheet> createState() => _TagFilterSheetState();
}

class _TagFilterSheetState extends State<_TagFilterSheet> {
  late final Set<int> selected;

  @override
  void initState() {
    super.initState();
    selected = Set<int>.from(widget.controller.selectedTagIds);
    unawaited(widget.controller.loadTags());
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final state = widget.controller;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'All tags',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  Text('${selected.length} selected'),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Choose one or more tags. A post matching any selected tag is shown.',
              ),
              const SizedBox(height: 16),
              if (state.tagsLoading)
                const Center(child: CircularProgressIndicator())
              else if (state.tagsError != null)
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Tags could not be loaded.\n${state.tagsError}',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () => state.loadTags(force: true),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              else if (state.tagsLoaded && state.tags.isEmpty)
                const Center(child: Text('No tags are configured.'))
              else
                Flexible(
                  child: SingleChildScrollView(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: state.tags
                          .map(
                            (tag) => FilterChip(
                              label: Text(tag.name),
                              selected: selected.contains(tag.id),
                              onSelected: (value) => setState(
                                () => value
                                    ? selected.add(tag.id)
                                    : selected.remove(tag.id),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: state.tagsLoading || state.tagsError != null
                      ? null
                      : () => Navigator.pop(context, selected),
                  child: Text(
                    selected.isEmpty
                        ? 'Show all posts'
                        : 'Apply ${selected.length} filter(s)',
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _Header extends StatelessWidget {
  const _Header({
    required this.controller,
    required this.onSearch,
    required this.onFilter,
  });

  final TextEditingController controller;
  final ValueChanged<String> onSearch;
  final VoidCallback onFilter;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        colors: [CommunityColors.headerStart, CommunityColors.headerEnd],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
    ),
    child: Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 49,
            child: TextField(
              controller: controller,
              onChanged: onSearch,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search posts, places or tags…',
                suffixIcon: controller.text.isEmpty
                    ? const Icon(Icons.search)
                    : IconButton(
                        tooltip: 'Clear search',
                        onPressed: () {
                          controller.clear();
                          onSearch('');
                        },
                        icon: const Icon(Icons.close),
                      ),
                filled: true,
                fillColor: const Color(0xFFF7F3FB),
                contentPadding: const EdgeInsets.symmetric(horizontal: 18),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                  borderSide: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        IconButton.filledTonal(
          tooltip: 'All tags',
          onPressed: onFilter,
          icon: const Icon(Icons.tune),
        ),
      ],
    ),
  );
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 60, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 18),
            FilledButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    ),
  );
}
