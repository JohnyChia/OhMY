import 'dart:async';

import 'package:flutter/material.dart';

import '../services/nova_action_bridge.dart';

/// Keeps the traveller on the current page until an explicit choice and a
/// confirmation. The owner module is only opened after final confirmation.
class NovaJourneyConfirmationCard extends StatefulWidget {
  const NovaJourneyConfirmationCard({
    super.key,
    required this.action,
    required this.onConfirm,
    required this.onCancel,
    this.timeout = const Duration(seconds: 20),
  });

  final NovaAction action;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final Duration timeout;

  @override
  State<NovaJourneyConfirmationCard> createState() =>
      _NovaJourneyConfirmationCardState();
}

class _NovaJourneyConfirmationCardState
    extends State<NovaJourneyConfirmationCard>
    with SingleTickerProviderStateMixin {
  late int _secondsLeft;
  late final AnimationController _countdown;
  Timer? _timer;
  String? _tripMode;

  bool get _isReroute => widget.action.type == 'show_place_results';
  bool get _isAwaitingTripMode => !_isReroute && _tripMode == null;

  @override
  void initState() {
    super.initState();
    _secondsLeft = widget.timeout.inSeconds;
    _countdown = AnimationController(vsync: this, duration: widget.timeout);
    final requestedMode = widget.action.parameters['trip_mode'];
    if (requestedMode == 'solo' || requestedMode == 'group') {
      _tripMode = requestedMode;
    }
    if (_isReroute || _tripMode != null) _beginCountdown();
  }

  void _beginCountdown() {
    if (_timer != null) return;
    _countdown.forward(from: 0);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_secondsLeft <= 1) {
        _timer?.cancel();
        widget.onCancel();
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  void _selectTripMode(String mode) {
    setState(() => _tripMode = mode);
    _beginCountdown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _countdown.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final parameters = widget.action.parameters;
    final destination =
        parameters['destination']?.toString() ?? 'your destination';
    final interests =
        (parameters['interests'] as List?)
            ?.map((item) => item.toString())
            .where((item) => item.isNotEmpty)
            .join(' · ') ??
        '';
    final duration = parameters['duration'];
    final budget = parameters['budget']?.toString() ?? '';
    final detail = [
      if (duration is num) '${duration.toInt()} day${duration == 1 ? '' : 's'}',
      if (budget.isNotEmpty) budget,
      if (interests.isNotEmpty) interests,
    ].join('  •  ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
      child: AnimatedBuilder(
        animation: _countdown,
        builder: (context, child) => CustomPaint(
          foregroundPainter: _JourneyCountdownBorder(_countdown.value),
          child: child,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF173B7A), Color(0xFF5D3E9A)],
              ),
            ),
            child: _isAwaitingTripMode
                ? _TripModeStep(
                    onSolo: () => _selectTripMode('solo'),
                    onGroup: () => _selectTripMode('group'),
                    onCancel: widget.onCancel,
                  )
                : _ConfirmationStep(
                    destination: destination,
                    detail: detail,
                    isReroute: _isReroute,
                    tripMode: _tripMode,
                    secondsLeft: _secondsLeft,
                    onConfirm: widget.onConfirm,
                    onCancel: widget.onCancel,
                  ),
          ),
        ),
      ),
    );
  }
}

class _TripModeStep extends StatelessWidget {
  const _TripModeStep({
    required this.onSolo,
    required this.onGroup,
    required this.onCancel,
  });

  final VoidCallback onSolo;
  final VoidCallback onGroup;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Row(
        children: [
          Icon(Icons.people_alt_outlined, color: Colors.white),
          SizedBox(width: 8),
          Text(
            'Who is travelling?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ],
      ),
      const SizedBox(height: 10),
      const Text(
        'Choose a trip type first. Nova will then show the journey confirmation.',
        style: TextStyle(color: Colors.white70, fontSize: 12),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: onSolo,
              icon: const Icon(Icons.person_outline),
              label: const Text('Solo trip'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton.icon(
              onPressed: onGroup,
              icon: const Icon(Icons.groups_outlined),
              label: const Text('Group trip'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      TextButton(
        onPressed: onCancel,
        style: TextButton.styleFrom(foregroundColor: Colors.white70),
        child: const Text('Cancel'),
      ),
    ],
  );
}

class _ConfirmationStep extends StatelessWidget {
  const _ConfirmationStep({
    required this.destination,
    required this.detail,
    required this.isReroute,
    required this.tripMode,
    required this.secondsLeft,
    required this.onConfirm,
    required this.onCancel,
  });

  final String destination;
  final String detail;
  final bool isReroute;
  final String? tripMode;
  final int secondsLeft;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          const Icon(Icons.navigation_rounded, color: Colors.white),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isReroute ? 'Reroute proposal ready' : 'Journey ready',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text('$secondsLeft s', style: const TextStyle(color: Colors.white70)),
        ],
      ),
      const SizedBox(height: 10),
      Text(
        destination,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      if (tripMode != null) ...[
        const SizedBox(height: 4),
        Text(
          '${tripMode == 'solo' ? 'Solo' : 'Group'} trip',
          style: const TextStyle(color: Colors.white70),
        ),
      ],
      if (detail.isNotEmpty) ...[
        const SizedBox(height: 5),
        Text(detail, style: const TextStyle(color: Colors.white70)),
      ],
      const SizedBox(height: 14),
      Text(
        isReroute
            ? 'Say “show alternatives” or confirm below. The existing recommendation map will provide verified choices.'
            : 'Say “start journey” or confirm below. It will stay on this page if you cancel or time out.',
        style: const TextStyle(color: Colors.white70, fontSize: 12),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: onCancel,
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
              child: const Text('Cancel'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              onPressed: onConfirm,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF244786),
              ),
              child: Text(isReroute ? 'Show alternatives' : 'Start journey'),
            ),
          ),
        ],
      ),
    ],
  );
}

/// The timer is painted directly on the gradient card edge. It begins at the
/// upper-right, traces right/bottom/left, and expires at the top-middle.
class _JourneyCountdownBorder extends CustomPainter {
  const _JourneyCountdownBorder(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    const inset = 1.5;
    const radius = 16.0;
    final rect = Rect.fromLTWH(
      inset,
      inset,
      size.width - inset * 2,
      size.height - inset * 2,
    );
    final path = Path()
      ..moveTo(rect.right - radius, rect.top)
      ..lineTo(rect.right, rect.top + radius)
      ..lineTo(rect.right, rect.bottom - radius)
      ..quadraticBezierTo(
        rect.right,
        rect.bottom,
        rect.right - radius,
        rect.bottom,
      )
      ..lineTo(rect.left + radius, rect.bottom)
      ..quadraticBezierTo(
        rect.left,
        rect.bottom,
        rect.left,
        rect.bottom - radius,
      )
      ..lineTo(rect.left, rect.top + radius)
      ..quadraticBezierTo(rect.left, rect.top, rect.left + radius, rect.top)
      ..lineTo(rect.center.dx, rect.top);
    final metric = path.computeMetrics().first;
    canvas.drawPath(
      metric.extractPath(
        0,
        metric.length * progress.clamp(0.0, 1.0).toDouble(),
      ),
      Paint()
        ..color = const Color(0xFF8BE7FF)
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _JourneyCountdownBorder oldDelegate) =>
      oldDelegate.progress != progress;
}
