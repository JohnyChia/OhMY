import 'package:flutter_app/user_management/models/traveler_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('onboarding is required when saved preferences are empty', () {
    const profile = TravelerProfile(userId: 'user-1', favoriteCategories: []);

    expect(profile.hasCompletedOnboarding, isFalse);
  });

  test('one saved preference is enough to skip first-time onboarding', () {
    const profile = TravelerProfile(
      userId: 'user-1',
      favoriteCategories: ['Cultural Experience'],
    );

    expect(profile.hasCompletedOnboarding, isTrue);
  });

  test('blank preference values do not count as completed onboarding', () {
    const profile = TravelerProfile(
      userId: 'user-1',
      favoriteCategories: ['  '],
    );

    expect(profile.hasCompletedOnboarding, isFalse);
  });
}
