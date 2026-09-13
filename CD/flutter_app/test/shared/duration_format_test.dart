import 'package:flutter_app/shared/utils/duration_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps durations below one hour in minutes', () {
    expect(formatTravelDuration(35), '35 min');
  });

  test('formats hours with optional remaining minutes', () {
    expect(formatTravelDuration(65), '1 hr 5 min');
    expect(formatTravelDuration(120), '2 hr');
    expect(formatTravelDuration(300), '5 hr');
    expect(formatTravelDuration(315), '5 hr 15 min');
  });
}
