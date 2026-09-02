import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../controllers/travel_group_controller.dart';
import '../models/travel_group_models.dart';
import '../widgets/travel_group_scaffold.dart';
import '../widgets/travel_group_widgets.dart';
import 'create_group_sheet.dart';
import 'group_details_screen.dart';
import 'group_lobby_screen.dart';
import 'verification_required_screen.dart';

class TravelGroupDiscoveryScreen extends StatefulWidget {
  const TravelGroupDiscoveryScreen({super.key, required this.controller});

  final TravelGroupController controller;

  @override
  State<TravelGroupDiscoveryScreen> createState() =>
      _TravelGroupDiscoveryScreenState();
}

class _TravelGroupDiscoveryScreenState
    extends State<TravelGroupDiscoveryScreen> {
  TravelGroupController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.loadGroups();
  }

  @override
  Widget build(BuildContext context) {
    return TravelGroupScaffold(
      controller: controller,
      onSearchChanged: controller.setSearch,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 22, 16, 24),
            children: [
              Text('Nearby lobbies',
                  style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 4),
              const Text('Impromptu trips happening around you',
                  style:
                      TextStyle(fontSize: 12, color: AppColors.secondaryText)),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton(
                  onPressed: _openCreateGroup,
                  style: FilledButton.styleFrom(
                      minimumSize: const Size(116, 34),
                      padding: const EdgeInsets.symmetric(horizontal: 15)),
                  child: const Text('+ Create Group'),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                    color: const Color(0xFFE9F2FF),
                    borderRadius: BorderRadius.circular(12)),
                child: const Row(
                  children: [
                    Icon(Icons.location_on_rounded,
                        size: 18, color: AppColors.primary),
                    SizedBox(width: 8),
                    Expanded(
                        child: Text('Bukit Bintang, Kuala Lumpur',
                            style: TextStyle(
                                fontSize: 13, color: AppColors.primaryDark))),
                    Text('Change ›',
                        style:
                            TextStyle(fontSize: 11, color: AppColors.primary)),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    const AppPill('Nearest', selected: true),
                    const SizedBox(width: 8),
                    AppPill('Open',
                        selected: controller.openOnly,
                        onTap: controller.toggleOpenOnly),
                    const SizedBox(width: 8),
                    PopupMenuButton<double>(
                      onSelected: controller.setRadius,
                      itemBuilder: (_) => const [2.0, 5.0, 10.0, 20.0]
                          .map((radius) => PopupMenuItem(
                              value: radius,
                              child: Text('Within ${radius.toInt()} km')))
                          .toList(),
                      child:
                          AppPill('Within ${controller.radiusKm.toInt()} km'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              if (controller.isLoading)
                const Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(child: CircularProgressIndicator()))
              else if (controller.groups.isEmpty)
                const AppPanel(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 28),
                    child: Center(
                        child: Text('No nearby groups match these filters.')),
                  ),
                )
              else
                ...controller.groups.map((group) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _LobbyCard(
                          group: group, onOpen: () => _openGroup(group)),
                    )),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openCreateGroup() async {
    if (!controller.currentUser.isVerified) {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
            builder: (_) => VerificationRequiredScreen(controller: controller)),
      );
      return;
    }
    final created = await showModalBottomSheet<TravelGroup>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      builder: (_) => CreateGroupSheet(controller: controller),
    );
    if (!mounted || created == null) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
          builder: (_) => GroupLobbyScreen(controller: controller)),
    );
  }

  Future<void> _openGroup(TravelGroup group) async {
    await controller.openGroup(group.id);
    if (!mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
          builder: (_) => GroupDetailsScreen(controller: controller)),
    );
    await controller.loadGroups();
  }
}

class _LobbyCard extends StatelessWidget {
  const _LobbyCard({required this.group, required this.onOpen});

  final TravelGroup group;
  final VoidCallback onOpen;

  Color get surface {
    if (group.tags.contains('Nature')) return AppColors.surfaceLavender;
    if (group.tags.contains('Heritage')) return AppColors.surfaceWarm;
    return AppColors.surfaceBlue;
  }

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      color: surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                  child: Text(group.name,
                      style:
                          const TextStyle(fontSize: 17, color: AppColors.ink))),
              Container(
                width: 74,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12)),
                child: Text('${group.distanceKm.toStringAsFixed(1)} km',
                    style: const TextStyle(
                        fontSize: 10, color: AppColors.primary)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '👥  ${group.memberIds.length}/${group.maxMembers} travellers  •  ${group.joinMode == JoinMode.open ? 'Open' : 'Request'}',
            style: const TextStyle(fontSize: 12, color: Color(0xFF50617C)),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 7,
            children: group.tags
                .take(2)
                .map((tag) => AppPill(tag, backgroundColor: Colors.white))
                .toList(),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              MemberAvatar(
                  label: group.creatorName
                      .split(' ')
                      .map((part) => part[0])
                      .take(2)
                      .join()),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${group.creatorName}  •  Verified',
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF263A5C))),
                    const Text('Lobby creator',
                        style:
                            TextStyle(fontSize: 9, color: Color(0xFF7A879B))),
                  ],
                ),
              ),
              FilledButton(
                onPressed: onOpen,
                style: FilledButton.styleFrom(
                    minimumSize: const Size(70, 31),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12))),
                child: Text(group.isFull ? 'Full' : 'View'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
