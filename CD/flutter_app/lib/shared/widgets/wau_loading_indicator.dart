import 'package:flutter/material.dart';

/// Pull-to-refresh with the same Wau artwork as all other loading states.
class WauRefreshIndicator extends StatefulWidget {
  const WauRefreshIndicator({
    super.key,
    required this.child,
    required this.onRefresh,
  });

  final Widget child;
  final RefreshCallback onRefresh;

  @override
  State<WauRefreshIndicator> createState() => _WauRefreshIndicatorState();
}

class _WauRefreshIndicatorState extends State<WauRefreshIndicator> {
  RefreshIndicatorStatus? _status;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      RefreshIndicator.noSpinner(
        onRefresh: widget.onRefresh,
        onStatusChange: (status) {
          if (mounted) setState(() => _status = status);
        },
        child: widget.child,
      ),
      if (_status == RefreshIndicatorStatus.drag ||
          _status == RefreshIndicatorStatus.armed ||
          _status == RefreshIndicatorStatus.snap ||
          _status == RefreshIndicatorStatus.refresh)
        const Positioned(
          top: 12,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Center(child: WauLoadingIndicator(size: 32)),
          ),
        ),
    ],
  );
}

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
