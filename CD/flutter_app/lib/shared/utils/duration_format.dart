String formatTravelDuration(int minutes) {
  final safeMinutes = minutes < 0 ? 0 : minutes;
  if (safeMinutes < 60) return '$safeMinutes min';

  final hours = safeMinutes ~/ 60;
  final remainingMinutes = safeMinutes.remainder(60);
  if (remainingMinutes == 0) return '$hours hr';
  return '$hours hr $remainingMinutes min';
}
