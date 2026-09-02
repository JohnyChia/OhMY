import 'dart:ui';

class NavigationSnapshot {
  const NavigationSnapshot({
    required this.position,
    required this.etaMinutes,
    required this.distanceKm,
    required this.instruction,
  });

  final Offset position;
  final int etaMinutes;
  final double distanceKm;
  final String instruction;
}

abstract interface class TravelMapService {
  NavigationSnapshot snapshot(double progress);
}

class MockTravelMapService implements TravelMapService {
  static const _route = [
    Offset(78, 520),
    Offset(150, 470),
    Offset(218, 408),
    Offset(245, 277),
    Offset(294, 200),
    Offset(311, 92),
  ];

  @override
  NavigationSnapshot snapshot(double progress) {
    final safeProgress = progress.clamp(0.0, 0.98).toDouble();
    final scaled = safeProgress * (_route.length - 1);
    final segment = scaled.floor().clamp(0, _route.length - 2).toInt();
    final localProgress = scaled - segment;
    final position =
        Offset.lerp(_route[segment], _route[segment + 1], localProgress)!;
    final remaining = 1 - safeProgress;
    var instruction = 'Continue on the highlighted route';
    if (safeProgress > .72) {
      instruction = 'Turn right in 80 m';
    } else if (safeProgress > .36) {
      instruction = 'Keep left at the next junction';
    }
    return NavigationSnapshot(
      position: position,
      etaMinutes: (6 * remaining).ceil().clamp(1, 6).toInt(),
      distanceKm:
          double.parse((.8 * remaining).clamp(.05, .8).toStringAsFixed(2)),
      instruction: instruction,
    );
  }
}
