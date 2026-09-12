import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../models/travel_group_models.dart';
import '../widgets/travel_group_widgets.dart';

class GroupMemberProfileScreen extends StatelessWidget {
  const GroupMemberProfileScreen({
    super.key,
    required this.member,
    required this.groupName,
    required this.isCurrentUser,
    this.onRemoveFromGroup,
  });

  final GroupMemberProfile member;
  final String groupName;
  final bool isCurrentUser;
  final Future<void> Function()? onRemoveFromGroup;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Traveller profile')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          Center(child: _ProfileAvatar(member: member, radius: 42)),
          const SizedBox(height: 14),
          Text(
            member.displayName,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 5),
          Text(
            [
              member.isCreator ? 'Group creator' : 'Group member',
              if (isCurrentUser) 'You',
            ].join('  •  '),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.secondaryText),
          ),
          const SizedBox(height: 22),
          AppPanel(
            color: AppColors.paleBlue,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'TRAVELLING TOGETHER IN',
                  style: TextStyle(fontSize: 10, color: AppColors.primary),
                ),
                const SizedBox(height: 5),
                Text(groupName, style: const TextStyle(fontSize: 15)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AppPanel(
            child: Row(
              children: [
                Expanded(
                  child: _ProfileStat(
                    value: member.completedTrips,
                    label: 'Trips completed',
                  ),
                ),
                Container(width: 1, height: 42, color: AppColors.border),
                Expanded(
                  child: _ProfileStat(
                    value: member.communityPostCount,
                    label: 'Community posts',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AppPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Travel preferences',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                _ProfileDetail(
                  icon: Icons.explore_outlined,
                  label: 'Travel style',
                  value: member.travelStyle,
                ),
                _ProfileDetail(
                  icon: Icons.translate_rounded,
                  label: 'Preferred language',
                  value: member.preferredLanguage,
                ),
                _ProfileDetail(
                  icon: Icons.account_balance_wallet_outlined,
                  label: 'Budget',
                  value: member.budgetPreference,
                ),
                const SizedBox(height: 6),
                const Text(
                  'Interests',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.secondaryText,
                  ),
                ),
                const SizedBox(height: 7),
                if (member.interests.isEmpty)
                  const Text('No interests shared yet.')
                else
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: member.interests
                        .map((interest) => AppPill(interest))
                        .toList(growable: false),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (onRemoveFromGroup != null) ...[
            OutlinedButton.icon(
              key: const Key('remove_group_member_button'),
              onPressed: () => _confirmRemoval(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFB3261E),
                side: const BorderSide(color: Color(0xFFB3261E)),
                minimumSize: const Size.fromHeight(48),
              ),
              icon: const Icon(Icons.person_remove_outlined),
              label: const Text('Remove from group'),
            ),
            const SizedBox(height: 12),
          ],
          const Text(
            'Only travel information shared with this group is shown. Email and account details remain private.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: AppColors.secondaryText),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmRemoval(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Remove ${member.displayName}?'),
        content: const Text(
          'They will leave this lobby and can join again while the group is recruiting.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm_remove_group_member_button'),
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB3261E),
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await onRemoveFromGroup!();
      if (!context.mounted) return;
      Navigator.pop(context);
    } on TravelGroupException catch (error) {
      if (context.mounted) {
        showTravelGroupMessage(context, error.message, error: true);
      }
    }
  }
}

class _ProfileStat extends StatelessWidget {
  const _ProfileStat({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          '$value',
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 10, color: AppColors.secondaryText),
        ),
      ],
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.member, required this.radius});

  final GroupMemberProfile member;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final url = member.avatarUrl;
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.primary,
      foregroundImage: url == null || url.isEmpty ? null : NetworkImage(url),
      child: Text(
        member.initials,
        style: TextStyle(
          color: Colors.white,
          fontSize: radius * .55,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ProfileDetail extends StatelessWidget {
  const _ProfileDetail({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final displayValue = value?.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.secondaryText,
                  ),
                ),
                Text(
                  displayValue == null || displayValue.isEmpty
                      ? 'Not specified'
                      : displayValue,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
