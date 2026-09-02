import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../controllers/travel_group_controller.dart';
import '../models/travel_group_models.dart';
import '../widgets/travel_group_scaffold.dart';
import '../widgets/travel_group_widgets.dart';
import 'itinerary_board.dart';
import 'suggestion_board.dart';

class GroupLobbyScreen extends StatefulWidget {
  const GroupLobbyScreen({super.key, required this.controller});

  final TravelGroupController controller;

  @override
  State<GroupLobbyScreen> createState() => _GroupLobbyScreenState();
}

class _GroupLobbyScreenState extends State<GroupLobbyScreen> {
  int _tabIndex = 0;

  TravelGroupController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.refreshWorkspace();
  }

  @override
  Widget build(BuildContext context) {
    return TravelGroupScaffold(
      controller: controller,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final group = controller.activeGroup!;
          if (!controller.isMember) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: AppPanel(
                  color: AppColors.paleBlue,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.lock_outline_rounded,
                          color: AppColors.primary, size: 34),
                      const SizedBox(height: 10),
                      const Text('This lobby is for joined travellers',
                          style: TextStyle(fontSize: 16)),
                      const SizedBox(height: 5),
                      const Text(
                          'Return to the group details to join or request access.'),
                      const SizedBox(height: 12),
                      FilledButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Back to group details')),
                    ],
                  ),
                ),
              ),
            );
          }
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: () => Navigator.pop(context),
                      child: const Text('‹ Nearby lobbies',
                          style: TextStyle(
                              fontSize: 11, color: AppColors.primary)),
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        Expanded(
                            child: Text(group.name,
                                style: Theme.of(context).textTheme.titleLarge)),
                        _StatusBadge(status: group.status),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(group.tags.join('  •  '),
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.secondaryText)),
                    const SizedBox(height: 10),
                    GroupTabs(
                        index: _tabIndex,
                        onChanged: (index) =>
                            setState(() => _tabIndex = index)),
                  ],
                ),
              ),
              Expanded(
                child: IndexedStack(
                  index: _tabIndex,
                  children: [
                    _LobbyTab(
                        controller: controller,
                        onSuggest: () => setState(() => _tabIndex = 1)),
                    SuggestionBoard(controller: controller),
                    ItineraryBoard(controller: controller),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final GroupStatus status;

  @override
  Widget build(BuildContext context) {
    final label = switch (status) {
      GroupStatus.waiting => 'WAITING TO START',
      GroupStatus.active => 'TRIP ACTIVE',
      GroupStatus.completed => 'COMPLETED',
    };
    final color =
        status == GroupStatus.completed ? AppColors.success : AppColors.primary;
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 13),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: status == GroupStatus.completed
            ? AppColors.successSurface
            : AppColors.paleBlue,
        border: Border.all(
            color: status == GroupStatus.completed
                ? const Color(0xFF8CDBB0)
                : AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label, style: TextStyle(fontSize: 9, color: color)),
    );
  }
}

class _LobbyTab extends StatelessWidget {
  const _LobbyTab({required this.controller, required this.onSuggest});

  final TravelGroupController controller;
  final VoidCallback onSuggest;

  @override
  Widget build(BuildContext context) {
    final group = controller.activeGroup!;
    final pending = controller.joinRequests
        .where((request) => request.status == JoinRequestStatus.pending)
        .toList();
    final confirmed = controller.suggestions
        .where((suggestion) => suggestion.isConfirmed)
        .length;
    final avatarCount = group.memberIds.length > 5 ? 5 : group.memberIds.length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        if (controller.isMember) ...[
          AppPanel(
            color: const Color(0xFFE8FAF0),
            borderColor: const Color(0xFF8CDBB0),
            child: Row(
              children: [
                const CircleAvatar(
                    radius: 16,
                    backgroundColor: AppColors.success,
                    child: Icon(Icons.check, color: Colors.white, size: 20)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('You’re in the lobby',
                          style: TextStyle(fontSize: 14)),
                      Text(
                          '${group.memberIds.length} of ${group.maxMembers} members',
                          style: const TextStyle(
                              fontSize: 10, color: AppColors.secondaryText)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        AppPanel(
          color: AppColors.paleBlue,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                      child: Text('MEETUP POINT',
                          style: TextStyle(
                              fontSize: 10, color: AppColors.primary))),
                  OutlinedButton(
                      onPressed: () => showTravelGroupMessage(context,
                          'Map integration will use the location module.'),
                      child: const Text('View map ›')),
                ],
              ),
              Text(group.meetupPoint, style: const TextStyle(fontSize: 15)),
              const SizedBox(height: 4),
              Text(
                  '${group.distanceKm.toStringAsFixed(1)} km away  •  Walk 10 min'),
              if (group.meetupNote.isNotEmpty) ...[
                const SizedBox(height: 9),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8)),
                  child: Text('●  ${group.meetupNote}',
                      style: const TextStyle(
                          fontSize: 10, color: AppColors.secondaryText)),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        AppPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('Members', style: TextStyle(fontSize: 14)),
                  const SizedBox(width: 12),
                  Text('${group.memberIds.length} / ${group.maxMembers}',
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.primary)),
                  const Spacer(),
                  OutlinedButton(
                      onPressed: () => showTravelGroupMessage(
                          context, 'Group chat is mocked for this module.'),
                      child: const Text('Group chat')),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  for (var index = 0; index < avatarCount; index++) ...[
                    MemberAvatar(
                        label: index == 0 ? 'AS' : 'M$index',
                        color: Colors.primaries[index % Colors.primaries.length]
                            .shade400),
                    const SizedBox(width: 7),
                  ],
                  const Spacer(),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('${group.creatorName} · Creator',
                          style: const TextStyle(fontSize: 11)),
                      const Text('Verified travellers',
                          style: TextStyle(
                              fontSize: 9, color: AppColors.secondaryText)),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        AppPanel(
          color: AppColors.paleBlue,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Planning progress', style: TextStyle(fontSize: 14)),
              const Text('Collaborate before the creator starts the trip.',
                  style:
                      TextStyle(fontSize: 10, color: AppColors.secondaryText)),
              const SizedBox(height: 10),
              Row(
                children: [
                  _ProgressStat(
                      value: '${controller.suggestions.length}',
                      label: 'Suggestions'),
                  const SizedBox(width: 9),
                  _ProgressStat(value: '$confirmed', label: 'Confirmed stops'),
                  const SizedBox(width: 9),
                  _ProgressStat(
                      value: group.status == GroupStatus.waiting
                          ? 'Not started'
                          : group.status.name,
                      label: 'Trip status',
                      warning: group.status == GroupStatus.waiting),
                ],
              ),
            ],
          ),
        ),
        if (controller.isCreator && pending.isNotEmpty) ...[
          const SizedBox(height: 10),
          AppPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Join requests (${pending.length})',
                    style: const TextStyle(fontSize: 14)),
                const SizedBox(height: 8),
                for (final request in pending)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        MemberAvatar(
                            label: request.travellerName.substring(0, 1)),
                        const SizedBox(width: 8),
                        Expanded(child: Text(request.travellerName)),
                        TextButton(
                            onPressed: () =>
                                controller.respondToRequest(request, false),
                            child: const Text('Decline')),
                        FilledButton(
                          onPressed: () =>
                              controller.respondToRequest(request, true),
                          style: FilledButton.styleFrom(
                              minimumSize: const Size(68, 32)),
                          child: const Text('Accept'),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        FilledButton(
            onPressed: onSuggest, child: const Text('+  Suggest a stop')),
        const SizedBox(height: 8),
        Text(
          controller.isCreator
              ? 'You control final stops and when the trip starts.'
              : 'Only the creator can start the group trip.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 10, color: AppColors.secondaryText),
        ),
      ],
    );
  }
}

class _ProgressStat extends StatelessWidget {
  const _ProgressStat(
      {required this.value, required this.label, this.warning = false});

  final String value;
  final String label;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(11)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FittedBox(
                child: Text(value,
                    style: TextStyle(
                        fontSize: value.length > 4 ? 11 : 17,
                        color:
                            warning ? AppColors.warning : AppColors.primary))),
            Text(label,
                style: const TextStyle(
                    fontSize: 9, color: AppColors.secondaryText)),
          ],
        ),
      ),
    );
  }
}
