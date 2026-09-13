import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../controllers/travel_group_controller.dart';

class TravelGroupScaffold extends StatelessWidget {
  const TravelGroupScaffold({
    super.key,
    required this.controller,
    required this.child,
    this.showBottomNavigation = false,
    this.floatingActionButton,
  });

  final TravelGroupController controller;
  final Widget child;
  final bool showBottomNavigation;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.light,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FBFF),
        body: Stack(
          fit: StackFit.expand,
          children: [const _GroupTripBackground(), child],
        ),
        floatingActionButton: floatingActionButton,
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
        bottomNavigationBar: showBottomNavigation
            ? const _PrototypeNavigation()
            : null,
      ),
    );
  }
}

class _GroupTripBackground extends StatelessWidget {
  const _GroupTripBackground();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 1.5, sigmaY: 1.5),
            child: Opacity(
              opacity: .30,
              child: Image.asset(
                'assets/images/start_trip_selection/startTripSelectionBg.png',
                fit: BoxFit.cover,
                alignment: Alignment.bottomCenter,
              ),
            ),
          ),
          const ColoredBox(color: Color(0x99F8FBFF)),
        ],
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
              color: Color(0x1A000000),
              blurRadius: 8,
              offset: Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: List.generate(items.length, (index) {
            final selected = index == 2;
            return Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    items[index].$1,
                    size: 22,
                    color: selected
                        ? const Color(0xFF3266CC)
                        : const Color(0xFF60646B),
                  ),
                  const SizedBox(height: 2),
                  Text(items[index].$2, style: const TextStyle(fontSize: 8)),
                ],
              ),
            );
          }),
        ),
      ),
    );
  }
}
