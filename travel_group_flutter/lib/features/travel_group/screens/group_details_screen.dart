import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../controllers/travel_group_controller.dart';
import '../models/travel_group_models.dart';
import '../widgets/travel_group_scaffold.dart';
import '../widgets/travel_group_widgets.dart';
import 'group_lobby_screen.dart';
import 'verification_required_screen.dart';

class GroupDetailsScreen extends StatelessWidget {
  const GroupDetailsScreen({super.key, required this.controller});

  final TravelGroupController controller;

  @override
  Widget build(BuildContext context) {
    return TravelGroupScaffold(
      controller: controller,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final group = controller.activeGroup!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
            children: [
              InkWell(
                onTap: () => Navigator.pop(context),
                child: const Text('‹ Nearby lobbies',
                    style: TextStyle(color: AppColors.primary, fontSize: 11)),
              ),
              const SizedBox(height: 9),
              Text(group.name,
                  style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 4),
              Text(
                  '${group.distanceKm.toStringAsFixed(1)} km away  •  ${group.joinMode == JoinMode.open ? 'Open group' : 'Approval required'}'),
              const SizedBox(height: 14),
              AppPanel(
                color: AppColors.paleBlue,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(group.description,
                        style: const TextStyle(fontSize: 14, height: 1.4)),
                    const SizedBox(height: 14),
                    Wrap(
                        spacing: 7,
                        children: group.tags
                            .map((tag) =>
                                AppPill(tag, backgroundColor: Colors.white))
                            .toList()),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              AppPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('MEETUP POINT',
                        style:
                            TextStyle(fontSize: 10, color: AppColors.primary)),
                    const SizedBox(height: 5),
                    Text(group.meetupPoint,
                        style: const TextStyle(fontSize: 15)),
                    const SizedBox(height: 5),
                    Text(
                        '${group.memberIds.length} of ${group.maxMembers} travellers  •  Hosted by ${group.creatorName}'),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                  width: double.infinity, child: _actionButton(context, group)),
            ],
          );
        },
      ),
    );
  }

  Widget _actionButton(BuildContext context, TravelGroup group) {
    if (controller.isMember) {
      return FilledButton(
          onPressed: () => _openLobby(context),
          child: const Text('Enter lobby'));
    }
    if (group.isFull) {
      return const FilledButton(onPressed: null, child: Text('Group full'));
    }
    if (controller.hasPendingRequestForCurrentUser()) {
      return const FilledButton(
          onPressed: null, child: Text('Request pending'));
    }
    return FilledButton(
      onPressed: () => _join(context),
      child: Text(
          group.joinMode == JoinMode.open ? 'Join now' : 'Request to join'),
    );
  }

  Future<void> _join(BuildContext context) async {
    try {
      await controller.joinActiveGroup();
      if (!context.mounted) return;
      if (controller.activeGroup!.joinMode == JoinMode.open) {
        await _openLobby(context);
      } else {
        showTravelGroupMessage(context, 'Join request sent to the creator.');
      }
    } on TravelGroupException catch (error) {
      if (!context.mounted) return;
      if (error.code == 'verification_required') {
        await Navigator.push<void>(
          context,
          MaterialPageRoute(
              builder: (_) =>
                  VerificationRequiredScreen(controller: controller)),
        );
      } else {
        showTravelGroupMessage(context, error.message, error: true);
      }
    }
  }

  Future<void> _openLobby(BuildContext context) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
          builder: (_) => GroupLobbyScreen(controller: controller)),
    );
  }
}
