import 'package:flutter/material.dart';

class WauLoadingIndicator extends StatefulWidget {
  const WauLoadingIndicator({super.key, this.size = 64, this.label});

  final double size;
  final String? label;

  @override
  State<WauLoadingIndicator> createState() => _WauLoadingIndicatorState();
}

class _WauLoadingIndicatorState extends State<WauLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat();

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      RotationTransition(
        turns: CurvedAnimation(parent: controller, curve: Curves.linear),
        child: Image.asset(
          'assets/images/preference_recommender/wau.png',
          width: widget.size,
          height: widget.size,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          semanticLabel: 'Loading',
        ),
      ),
      if (widget.label != null) ...[
        const SizedBox(height: 8),
        Text(
          widget.label!,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xff3266cc),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ],
  );

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}
