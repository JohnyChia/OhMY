import 'package:flutter/material.dart';

/// The application-wide loading indicator.
///
/// Use a small [size] inside buttons and a larger size for page-level loading.
class WauLoadingIndicator extends StatefulWidget {
  const WauLoadingIndicator({
    super.key,
    this.size = 64,
    this.label,
    this.labelColor = const Color(0xFF3266CC),
  });

  final double size;
  final String? label;
  final Color labelColor;

  @override
  State<WauLoadingIndicator> createState() => _WauLoadingIndicatorState();
}

class _WauLoadingIndicatorState extends State<WauLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat();

  @override
  Widget build(BuildContext context) {
    final effectiveLabel =
        widget.label ?? (widget.size >= 40 ? 'Loading...' : null);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        RotationTransition(
          turns: CurvedAnimation(parent: _controller, curve: Curves.linear),
          child: Image.asset(
            'assets/images/preference_recommender/wau.png',
            width: widget.size,
            height: widget.size,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            semanticLabel: 'Loading',
          ),
        ),
        if (effectiveLabel != null) ...[
          const SizedBox(height: 8),
          Text(
            effectiveLabel,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: widget.labelColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
