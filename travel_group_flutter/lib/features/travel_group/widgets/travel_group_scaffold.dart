import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../controllers/travel_group_controller.dart';

class TravelGroupScaffold extends StatelessWidget {
  const TravelGroupScaffold({
    super.key,
    required this.controller,
    required this.child,
    this.onSearchChanged,
    this.showBottomNavigation = true,
  });

  final TravelGroupController controller;
  final Widget child;
  final ValueChanged<String>? onSearchChanged;
  final bool showBottomNavigation;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _PrototypeHeader(
              controller: controller, onSearchChanged: onSearchChanged),
          Expanded(child: child),
          if (showBottomNavigation) const _PrototypeNavigation(),
        ],
      ),
    );
  }
}

class _PrototypeHeader extends StatelessWidget {
  const _PrototypeHeader({required this.controller, this.onSearchChanged});

  final TravelGroupController controller;
  final ValueChanged<String>? onSearchChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 150,
      padding: EdgeInsets.fromLTRB(
          24, MediaQuery.paddingOf(context).top + 12, 18, 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFC8DAFF), Color(0xFF9CBBFF)],
        ),
      ),
      alignment: Alignment.bottomCenter,
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 49,
              child: TextField(
                onSubmitted: onSearchChanged,
                decoration: const InputDecoration(
                  hintText: 'Search Attractions ...',
                  suffixIcon: Icon(Icons.search_rounded),
                  contentPadding: EdgeInsets.symmetric(horizontal: 24),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          InkWell(
            onTap: () => _showDemoProfile(context),
            borderRadius: BorderRadius.circular(20),
            child: CircleAvatar(
              radius: 20,
              backgroundColor: AppColors.primary,
              child: Text(
                controller.currentUser.name
                    .split(' ')
                    .map((part) => part[0])
                    .take(2)
                    .join(),
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showDemoProfile(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Prototype profile',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            const Text(
                'Switch profiles to test creator and verification flows.'),
            const SizedBox(height: 16),
            for (final user in controller.demoUsers)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(child: Text(user.name.substring(0, 1))),
                title: Text(user.name),
                subtitle: Text(
                    user.isVerified ? 'Verified traveller' : 'Not verified'),
                trailing: controller.currentUser.id == user.id
                    ? const Icon(Icons.check_circle, color: AppColors.primary)
                    : null,
                onTap: () {
                  controller.switchUser(user);
                  Navigator.pop(sheetContext);
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _PrototypeNavigation extends StatelessWidget {
  const _PrototypeNavigation();

  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.home_rounded, 'Home'),
      (Icons.chat_bubble_outline_rounded, 'AI Chat'),
      (Icons.luggage_rounded, 'Start Trip'),
      (Icons.map_outlined, 'Community'),
      (Icons.person_outline_rounded, 'Profile'),
    ];
    return SafeArea(
      top: false,
      child: Container(
        height: 76,
        margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        decoration: BoxDecoration(
          color: Colors.white,
          border: const Border(top: BorderSide(color: Color(0xFFE5E8ED))),
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(
                color: Color(0x1A000000), blurRadius: 8, offset: Offset(0, -2))
          ],
        ),
        child: Row(
          children: List.generate(items.length, (index) {
            final selected = index == 2;
            return Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: selected ? 42 : 28,
                    height: selected ? 38 : 28,
                    decoration: selected
                        ? const BoxDecoration(
                            color: AppColors.primary, shape: BoxShape.circle)
                        : null,
                    child: Icon(items[index].$1,
                        size: 22,
                        color:
                            selected ? Colors.white : const Color(0xFF60646B)),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    items[index].$2,
                    maxLines: 1,
                    style: TextStyle(
                        fontSize: 8,
                        color: selected
                            ? AppColors.primary
                            : const Color(0xFF60646B)),
                  ),
                ],
              ),
            );
          }),
        ),
      ),
    );
  }
}
