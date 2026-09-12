import 'dart:math' as math;

import 'package:flutter/material.dart';

class NovaWaveform extends StatefulWidget {
  const NovaWaveform({super.key, required this.phase, this.amplitude = 0});

  final String phase;
  final double amplitude;

  @override
  State<NovaWaveform> createState() => _NovaWaveformState();
}

class _NovaWaveformState extends State<NovaWaveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (_, _) {
      final active = widget.phase != 'idle';
      final energy = active
          ? (0.32 + widget.amplitude.clamp(0, 1) * .68).toDouble()
          : .14;
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(17, (index) {
          final wave =
              (math.sin(_controller.value * math.pi * 2 + index * .68) + 1) / 2;
          final height =
              (5 + (active ? wave * 26 * energy : (index.isEven ? 2 : 0)))
                  .toDouble();
          return AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            margin: const EdgeInsets.symmetric(horizontal: 2),
            width: 3.5,
            height: height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF9EE8FF),
                  Color(0xFF5D6EFF),
                  Color(0xFFC46DFF),
                ],
              ),
            ),
          );
        }),
      );
    },
  );
}
