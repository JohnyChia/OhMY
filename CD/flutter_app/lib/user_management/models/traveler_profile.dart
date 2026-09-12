class TravelerProfile {
  const TravelerProfile({
    required this.userId,
    required this.favoriteCategories,
    this.preferredLanguage,
    this.travelStyle,
    this.budgetPreference,
  });

  final String userId;
  final List<String> favoriteCategories;
  final String? preferredLanguage;
  final String? travelStyle;
  final String? budgetPreference;

  bool get hasCompletedOnboarding =>
      favoriteCategories
          .map((category) => category.trim())
          .where((category) => category.isNotEmpty)
          .toSet()
          .length >=
      3;

  bool get requiresFirstTimeOnboarding => !hasCompletedOnboarding;

  factory TravelerProfile.fromJson(Map<String, dynamic> json) {
    final categories = json['favorite_categories'];
    return TravelerProfile(
      userId: json['user_id'] as String? ?? '',
      favoriteCategories: categories is List
          ? categories.map((item) => item.toString()).toList()
          : const [],
      preferredLanguage: json['preferred_language'] as String?,
      travelStyle: json['travel_style'] as String?,
      budgetPreference: json['budget_preference'] as String?,
    );
  }
}
