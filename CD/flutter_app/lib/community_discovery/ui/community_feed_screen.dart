import 'dart:async';

import 'package:flutter/material.dart';

import '../state/community_controller.dart';
import '../theme/community_theme.dart';
import 'widgets/post_card.dart';

class CommunityFeedScreen extends StatefulWidget {
  const CommunityFeedScreen({super.key, required this.controller});

  final CommunityController controller;

  @override
  State<CommunityFeedScreen> createState() => _CommunityFeedScreenState();
}

class _CommunityFeedScreenState extends State<CommunityFeedScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    unawaited(widget.controller.loadPosts());
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

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final state = widget.controller;
      return Scaffold(
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: state.loadPosts,
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
                              const SizedBox(height: 3),
                              Text(
                                state.selectedTagIds.isEmpty
                                    ? 'Posts from completed trips'
                                    : '${state.selectedTagIds.length} discovery filter(s) selected',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 46,
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      scrollDirection: Axis.horizontal,
                      children: state.tags.take(5).map((tag) {
                        final selected = state.selectedTagIds.contains(tag.id);
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
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
                      itemCount: state.posts.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 14),
                      itemBuilder: (context, index) =>
                          PostCard(post: state.posts[index], controller: state),
                    ),
                  ),
              ],
            ),
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: 3,
          onDestinationSelected: (index) {
            if (index != 3) {
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
        ),
      );
    },
  );

  Future<void> _showFilters() async {
    final selected = Set<int>.from(widget.controller.selectedTagIds);
    final result = await showModalBottomSheet<Set<int>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 4, 22, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'All discovery tags',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Choose one or more tags. A post matching any selected tag is shown.',
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: widget.controller.tags
                      .map(
                        (tag) => FilterChip(
                          label: Text(tag.name),
                          selected: selected.contains(tag.id),
                          onSelected: (value) => setModalState(
                            () => value
                                ? selected.add(tag.id)
                                : selected.remove(tag.id),
                          ),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, selected),
                    child: const Text('Apply filters'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (result != null) await widget.controller.loadPosts(tagIds: result);
  }
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
          child: TextField(
            controller: controller,
            onChanged: onSearch,
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              hintText: 'Search posts, places or tags…',
              prefixIcon: Icon(Icons.search),
            ),
          ),
        ),
        const SizedBox(width: 10),
        IconButton.filledTonal(
          tooltip: 'All discovery tags',
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
