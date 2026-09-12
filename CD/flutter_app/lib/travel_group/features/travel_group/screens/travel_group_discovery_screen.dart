import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../controllers/travel_group_controller.dart';
import '../models/travel_group_models.dart';
import '../services/travel_place_search_service.dart';
import '../widgets/travel_group_scaffold.dart';
import 'create_group_sheet.dart';
import 'group_details_screen.dart';
import 'group_lobby_screen.dart';
import 'verification_required_screen.dart';

class TravelGroupDiscoveryScreen extends StatefulWidget {
  const TravelGroupDiscoveryScreen({
    super.key,
    required this.controller,
    this.placeSearchService,
  });

  final TravelGroupController controller;
  final TravelPlaceSearchService? placeSearchService;

  @override
  State<TravelGroupDiscoveryScreen> createState() =>
      _TravelGroupDiscoveryScreenState();
}

class _TravelGroupDiscoveryScreenState
    extends State<TravelGroupDiscoveryScreen> {
  static const _areas = [
    'Bukit Bintang, Kuala Lumpur',
    'Kuala Lumpur City Centre',
    'Subang Jaya',
    'Setapak, Kuala Lumpur',
  ];

  late final TravelPlaceSearchService _placeSearch;
  late final bool _ownsPlaceSearch;
  final Map<String, Future<String?>> _photoFutures = {};
  TravelGroupController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _ownsPlaceSearch = widget.placeSearchService == null;
    _placeSearch = widget.placeSearchService ?? TravelPlaceSearchService();
    controller.loadGroups();
  }

  @override
  void dispose() {
    if (_ownsPlaceSearch) _placeSearch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TravelGroupScaffold(
      controller: controller,
      floatingActionButton: FloatingActionButton(
        key: const Key('create_group_fab'),
        tooltip: 'Create travel group',
        onPressed: _openCreateGroup,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        shape: const CircleBorder(),
        child: const Icon(Icons.add_rounded, size: 32),
      ),
      child: SafeArea(
        bottom: false,
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 92),
            children: [
              Text(
                'Travel Groups',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              const Text(
                'Find travellers. Explore together.',
                style: TextStyle(fontSize: 13, color: AppColors.secondaryText),
              ),
              const SizedBox(height: 14),
              _areaSelector(),
              const SizedBox(height: 14),
              if (controller.isLoading)
                const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (controller.groups.isEmpty)
                const _EmptyGroups()
              else
                ...controller.groups.map(
                  (group) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _DestinationGroupCard(
                      group: group,
                      photoUrl: _photoFutures.putIfAbsent(
                        group.id,
                        () => _placeSearch.photoForDestination(
                          group.destination,
                          knownPhotoName: group.destinationPhotoName,
                        ),
                      ),
                      onOpen: () => _openGroup(group),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _areaSelector() {
    return PopupMenuButton<String>(
      key: const Key('area_dropdown'),
      initialValue: controller.selectedArea,
      onSelected: controller.setArea,
      itemBuilder: (context) => _areas
          .map((area) => PopupMenuItem<String>(value: area, child: Text(area)))
          .toList(),
      child: Container(
        height: 50,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F8FF),
          border: Border.all(color: const Color(0xFFC6D8F8)),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.location_on_rounded,
              size: 20,
              color: AppColors.primary,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                controller.selectedArea,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryDark,
                ),
              ),
            ),
            const Text(
              'Change',
              style: TextStyle(fontSize: 11, color: AppColors.primary),
            ),
            const SizedBox(width: 3),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: AppColors.primary,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openCreateGroup() async {
    if (!controller.currentUser.isVerified) {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => VerificationRequiredScreen(controller: controller),
        ),
      );
      return;
    }
    final created = await showModalBottomSheet<TravelGroup>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      builder: (_) => CreateGroupSheet(
        controller: controller,
        placeSearchService: _placeSearch,
      ),
    );
    if (!mounted || created == null) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => GroupLobbyScreen(controller: controller),
      ),
    );
  }

  Future<void> _openGroup(TravelGroup group) async {
    await controller.openGroup(group.id);
    if (!mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => GroupDetailsScreen(controller: controller),
      ),
    );
    await controller.loadGroups();
  }
}

class _DestinationGroupCard extends StatelessWidget {
  const _DestinationGroupCard({
    required this.group,
    required this.photoUrl,
    required this.onOpen,
  });

  final TravelGroup group;
  final Future<String?> photoUrl;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final isOpen = group.joinMode == JoinMode.open && !group.isFull;
    return Semantics(
      button: true,
      label:
          '${group.destination}, ${group.name}, created by ${group.creatorName}',
      child: Material(
        color: const Color(0xFF174982),
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
          child: SizedBox(
            height: 190,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _GroupPhoto(photoUrl: photoUrl),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      stops: [0, .48, 1],
                      colors: [
                        Color(0xED082A55),
                        Color(0xB8174A7F),
                        Color(0x1A0A2445),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group.destination,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 27,
                          height: 1.05,
                          fontWeight: FontWeight.w800,
                          shadows: [
                            Shadow(blurRadius: 5, color: Colors.black45),
                          ],
                        ),
                      ),
                      const SizedBox(height: 3),
                      SizedBox(
                        width: 225,
                        child: Text(
                          group.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 9),
                      _DetailLine(
                        icon: Icons.person_outline_rounded,
                        text: 'Created by ${group.creatorName}',
                      ),
                      const SizedBox(height: 4),
                      _DetailLine(
                        icon: Icons.groups_rounded,
                        text:
                            '${group.memberIds.length} / ${group.maxMembers} travellers',
                      ),
                      const SizedBox(height: 4),
                      _DetailLine(
                        icon: Icons.circle,
                        iconColor: isOpen
                            ? const Color(0xFF42D477)
                            : const Color(0xFFFFB24A),
                        text: isOpen ? 'Open' : 'Closed',
                      ),
                      const Spacer(),
                      Container(
                        height: 34,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1673F9),
                          borderRadius: BorderRadius.circular(17),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'View group',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SizedBox(width: 4),
                            Icon(
                              Icons.chevron_right_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GroupPhoto extends StatelessWidget {
  const _GroupPhoto({required this.photoUrl});

  final Future<String?> photoUrl;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: photoUrl,
      builder: (context, snapshot) {
        final url = snapshot.data;
        if (url == null) return const _PhotoFallback();
        return Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const _PhotoFallback(),
        );
      },
    );
  }
}

class _PhotoFallback extends StatelessWidget {
  const _PhotoFallback();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(colors: [Color(0xFF174982), Color(0xFF8EB7E8)]),
    ),
    child: Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Icon(Icons.landscape_rounded, size: 72, color: Colors.white38),
      ),
    ),
  );
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.icon, required this.text, this.iconColor});

  final IconData icon;
  final String text;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        icon,
        size: icon == Icons.circle ? 11 : 16,
        color: iconColor ?? Colors.white,
      ),
      const SizedBox(width: 7),
      Flexible(
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ),
    ],
  );
}

class _EmptyGroups extends StatelessWidget {
  const _EmptyGroups();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 48, horizontal: 24),
    child: Column(
      children: [
        Icon(Icons.groups_outlined, size: 42, color: AppColors.primary),
        SizedBox(height: 10),
        Text('No travel groups in this area yet.'),
        SizedBox(height: 4),
        Text(
          'Tap + to start one.',
          style: TextStyle(color: AppColors.secondaryText),
        ),
      ],
    ),
  );
}
