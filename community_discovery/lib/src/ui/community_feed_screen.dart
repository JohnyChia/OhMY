import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/community_post.dart';
import '../models/discovery_tag.dart';
import '../state/community_controller.dart';
import '../integration/community_integration_callbacks.dart';
import 'bookmarked_posts_screen.dart';
import 'widgets/post_card.dart';

enum _PostSort { latest, mostLiked }

class CommunityFeedScreen extends StatefulWidget {
  const CommunityFeedScreen({
    super.key,
    required this.controller,
    this.integrationCallbacks = const CommunityIntegrationCallbacks(),
    this.showBottomNavigation = true,
    this.preferredTagNames,
  });

  final CommunityController controller;
  final CommunityIntegrationCallbacks integrationCallbacks;
  final List<String>? preferredTagNames;

  /// Keep this enabled only when Community Discovery runs as a standalone app.
  /// The host OhMY shell owns the real navigation after integration.
  final bool showBottomNavigation;

  @override
  State<CommunityFeedScreen> createState() => _CommunityFeedScreenState();
}

class _CommunityFeedScreenState extends State<CommunityFeedScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _debounce;
  _PostSort _sort = _PostSort.latest;

  @override
  void initState() {
    super.initState();
    unawaited(widget.controller.loadTags());
    unawaited(widget.controller.loadPosts());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
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
          final likes = b.likeCount.compareTo(a.likeCount);
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
        body: Stack(
          children: [
            const Positioned.fill(child: _CommunityBackground()),
            SafeArea(
              child: RefreshIndicator(
                onRefresh: () async {
                  await Future.wait([
                    state.loadTags(force: true),
                    state.loadPosts(),
                  ]);
                },
                child: CustomScrollView(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: _Header(
                        controller: _searchController,
                        onSearch: _search,
                        onFilter: _showFilters,
                        activeFilterCount: state.selectedTagIds.length,
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Community finds',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
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
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                ),
                                scrollDirection: Axis.horizontal,
                                children: visibleTags.map((tag) {
                                  final selected = state.selectedTagIds
                                      .contains(tag.id);
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                    ),
                                    child: FilterChip(
                                      label: Text(tag.name),
                                      selected: selected,
                                      onSelected: (_) =>
                                          state.toggleTag(tag.id),
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
                          title:
                              state.query.isEmpty &&
                                  state.selectedTagIds.isEmpty
                              ? 'No community posts yet'
                              : 'No posts found',
                          message:
                              state.query.isEmpty &&
                                  state.selectedTagIds.isEmpty
                              ? 'Completed-trip stories will appear here.'
                              : 'Try a different destination, attraction, description, or tag.',
                          actionLabel:
                              state.query.isEmpty &&
                                  state.selectedTagIds.isEmpty
                              ? null
                              : 'Clear filters',
                          onAction:
                              state.query.isEmpty &&
                                  state.selectedTagIds.isEmpty
                              ? null
                              : () {
                                  _searchController.clear();
                                  state.loadPosts(query: '', tagIds: {});
                                },
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 110),
                        sliver: SliverList.separated(
                          itemCount: visiblePosts.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 14),
                          itemBuilder: (context, index) => PostCard(
                            post: visiblePosts[index],
                            controller: state,
                            integrationCallbacks: widget.integrationCallbacks,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
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
        floatingActionButton: FloatingActionButton.small(
          tooltip: 'Back to top',
          onPressed: () => _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeOutCubic,
          ),
          child: const Icon(Icons.keyboard_arrow_up_rounded),
        ),
      );
    },
  );

  Future<void> _showFilters() async {
    final result = await showModalBottomSheet<_DiscoveryOptions>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) =>
          _TagFilterSheet(controller: widget.controller, initialSort: _sort),
    );
    if (result != null) {
      setState(() => _sort = result.sort);
      await widget.controller.loadPosts(tagIds: result.tagIds);
    }
  }
}

class _DiscoveryOptions {
  const _DiscoveryOptions({required this.sort, required this.tagIds});

  final _PostSort sort;
  final Set<int> tagIds;
}

class _CommunityBackground extends StatelessWidget {
  const _CommunityBackground();

  @override
  Widget build(BuildContext context) => ClipRect(
    child: ImageFiltered(
      imageFilter: ui.ImageFilter.blur(sigmaX: 5, sigmaY: 5),
      child: Transform.scale(
        scale: 1.08,
        child: Opacity(
          opacity: 0.20,
          child: ColorFiltered(
            colorFilter: const ColorFilter.matrix([
              0.80315,
              0.17880,
              0.01805,
              0,
              0,
              0.05315,
              0.92880,
              0.01805,
              0,
              0,
              0.05315,
              0.17880,
              0.76805,
              0,
              0,
              0,
              0,
              0,
              1,
              0,
            ]),
            child: Image.asset(
              'assets/images/community_bg.png',
              package: 'community_discovery',
              fit: BoxFit.cover,
            ),
          ),
        ),
      ),
    ),
  );
}

class _TagFilterSheet extends StatefulWidget {
  const _TagFilterSheet({required this.controller, required this.initialSort});

  final CommunityController controller;
  final _PostSort initialSort;

  @override
  State<_TagFilterSheet> createState() => _TagFilterSheetState();
}

class _TagFilterSheetState extends State<_TagFilterSheet> {
  late final Set<int> selected;
  late _PostSort sort;

  @override
  void initState() {
    super.initState();
    selected = Set<int>.from(widget.controller.selectedTagIds);
    sort = widget.initialSort;
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
                      'Discover posts',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close filters',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              Text(
                'Choose how your Community feed is arranged.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 22),
              Text(
                'Sort by',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<_PostSort>(
                  segments: const [
                    ButtonSegment(
                      value: _PostSort.latest,
                      icon: Icon(Icons.schedule_outlined),
                      label: Text('Latest'),
                    ),
                    ButtonSegment(
                      value: _PostSort.mostLiked,
                      icon: Icon(Icons.favorite_outline),
                      label: Text('Most liked'),
                    ),
                  ],
                  selected: {sort},
                  onSelectionChanged: (values) =>
                      setState(() => sort = values.first),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Filter by interest',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    '${selected.length} selected',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Posts matching any selected interest will be shown.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
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
                      : () => Navigator.pop(
                          context,
                          _DiscoveryOptions(sort: sort, tagIds: selected),
                        ),
                  child: Text(
                    selected.isEmpty ? 'Apply and show all' : 'Apply filters',
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
    required this.activeFilterCount,
  });

  final TextEditingController controller;
  final ValueChanged<String> onSearch;
  final VoidCallback onFilter;
  final int activeFilterCount;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
    color: Colors.transparent,
    child: Row(
      children: [
        Expanded(
          child: Material(
            color: const Color(0xFFF9F7FC),
            elevation: 3,
            shadowColor: const Color(0x33000000),
            borderRadius: BorderRadius.circular(28),
            child: SizedBox(
              height: 54,
              child: TextField(
                controller: controller,
                onChanged: onSearch,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search posts, places or tags...',
                  suffixIconConstraints: const BoxConstraints(minWidth: 92),
                  suffixIcon: Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.search, size: 23),
                        const SizedBox(width: 4),
                        Badge(
                          isLabelVisible: activeFilterCount > 0,
                          label: Text('$activeFilterCount'),
                          child: IconButton(
                            tooltip: 'Sort and filter',
                            onPressed: onFilter,
                            icon: const Icon(Icons.tune, size: 22),
                          ),
                        ),
                      ],
                    ),
                  ),
                  filled: true,
                  fillColor: Colors.transparent,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
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
