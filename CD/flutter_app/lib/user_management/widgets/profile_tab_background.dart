import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Matches the Profile screen while keeping content clear and unblurred.
class ProfileTabBackground extends StatelessWidget {
  const ProfileTabBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      ClipRect(
        child: ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: 3.5, sigmaY: 3.5),
          child: Transform.scale(
            scale: 1.02,
            child: Image.asset(
              'assets/images/user_management/profile_bg.png',
              fit: BoxFit.cover,
            ),
          ),
        ),
      ),
      const ColoredBox(color: Color(0x18FFFDF8)),
      // Scaffold already includes the overlaid app bar in the body's top
      // safe-area inset. Extra toolbar padding would count that space twice.
      SafeArea(child: child),
    ],
  );
}
