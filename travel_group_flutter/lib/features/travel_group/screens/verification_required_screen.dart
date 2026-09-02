import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../controllers/travel_group_controller.dart';
import '../widgets/travel_group_scaffold.dart';
import '../widgets/travel_group_widgets.dart';

class VerificationRequiredScreen extends StatelessWidget {
  const VerificationRequiredScreen({super.key, required this.controller});

  final TravelGroupController controller;

  @override
  Widget build(BuildContext context) {
    return TravelGroupScaffold(
      controller: controller,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 22, 16, 24),
        children: [
          Text('Travel Group',
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 4),
          const Text('Meet safely with verified travellers'),
          const SizedBox(height: 22),
          AppPanel(
            color: AppColors.paleBlue,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
              child: Column(
                children: [
                  Container(
                    width: 92,
                    height: 92,
                    decoration: const BoxDecoration(
                        color: AppColors.primary, shape: BoxShape.circle),
                    child: const Icon(Icons.verified_user_rounded,
                        size: 46, color: Colors.white),
                  ),
                  const SizedBox(height: 22),
                  const Text('Verification required',
                      style: TextStyle(fontSize: 21, color: AppColors.ink)),
                  const SizedBox(height: 8),
                  const Text(
                    'Verify your traveller profile before creating or joining a nearby group.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.secondaryText),
                  ),
                  const SizedBox(height: 18),
                  const _GatePoint(
                      icon: Icons.shield_outlined,
                      label: 'A safer experience for every groupmate'),
                  const _GatePoint(
                      icon: Icons.badge_outlined,
                      label: 'Your verified status is shown in the lobby'),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        controller.completeDemoVerification();
                        showTravelGroupMessage(
                            context, 'Demo verification completed.');
                        Navigator.pop(context);
                      },
                      child: const Text('Complete demo verification'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GatePoint extends StatelessWidget {
  const _GatePoint({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }
}
