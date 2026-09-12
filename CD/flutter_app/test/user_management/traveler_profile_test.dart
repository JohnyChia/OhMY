import 'package:flutter_app/user_management/models/traveler_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'onboarding is required for a newly registered user without preferences',
    () {
      const profile = TravelerProfile(userId: 'user-1', favoriteCategories: []);

      expect(profile.requiresFirstTimeOnboarding, isTrue);
    },
  );

  test(
    'an existing account cannot enter the app without saved preferences',
    () {
      const profile = TravelerProfile(userId: 'user-1', favoriteCategories: []);

      expect(profile.requiresFirstTimeOnboarding, isTrue);
    },
  );

  test('fewer than three saved preferences do not complete onboarding', () {
    const profile = TravelerProfile(
      userId: 'user-1',
      favoriteCategories: ['Cultural Experience'],
    );

    expect(profile.requiresFirstTimeOnboarding, isTrue);
  });

  test(
    'three saved preferences survive login without repeating onboarding',
    () {
      const profile = TravelerProfile(
        userId: 'user-1',
        favoriteCategories: [
          'Cultural Experience',
          'Cultural Festival',
          'Heritage',
        ],
      );

      expect(profile.requiresFirstTimeOnboarding, isFalse);
    },
  );

  test('blank preference values do not count as completed onboarding', () {
    const profile = TravelerProfile(
      userId: 'user-1',
      favoriteCategories: ['  '],
    );

    expect(profile.hasCompletedOnboarding, isFalse);
  });
}
