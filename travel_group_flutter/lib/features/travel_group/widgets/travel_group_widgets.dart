import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

class AppPill extends StatelessWidget {
  const AppPill(
    this.label, {
    super.key,
    this.selected = false,
    this.onTap,
    this.backgroundColor,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: backgroundColor ??
              (selected ? AppColors.primary : const Color(0xFFF3F6FC)),
          border: selected ? null : Border.all(color: const Color(0xFFCCD9EF)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          label,
          style: TextStyle(
              fontSize: 11,
              color: selected ? Colors.white : const Color(0xFF536681)),
        ),
      ),
    );
  }
}

class MemberAvatar extends StatelessWidget {
  const MemberAvatar(
      {super.key, required this.label, this.color = AppColors.primary});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 17,
      backgroundColor: color,
      child: Text(label,
          style: const TextStyle(color: Colors.white, fontSize: 10)),
    );
  }
}

class GroupTabs extends StatelessWidget {
  const GroupTabs({super.key, required this.index, required this.onChanged});

  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    const labels = ['Lobby', 'Suggestions', 'Itinerary'];
    return Container(
      height: 34,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F7FC),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        children: List.generate(labels.length, (itemIndex) {
          final selected = itemIndex == index;
          return Expanded(
            child: InkWell(
              onTap: () => onChanged(itemIndex),
              borderRadius: BorderRadius.circular(9),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? AppColors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  labels[itemIndex],
                  style: TextStyle(
                      fontSize: 11,
                      color: selected ? Colors.white : AppColors.ink),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class AppPanel extends StatelessWidget {
  const AppPanel({
    super.key,
    required this.child,
    this.color = Colors.white,
    this.borderColor = AppColors.border,
    this.padding = const EdgeInsets.all(13),
  });

  final Widget child;
  final Color color;
  final Color borderColor;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(15),
      ),
      child: child,
    );
  }
}

void showTravelGroupMessage(BuildContext context, String message,
    {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? const Color(0xFFBF2424) : AppColors.ink,
        behavior: SnackBarBehavior.floating,
      ),
    );
}
