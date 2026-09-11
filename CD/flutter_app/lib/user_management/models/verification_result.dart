class VerificationResult {
  const VerificationResult({
    required this.verified,
    required this.message,
    this.faceMatchScore,
  });

  final bool verified;
  final String message;
  final double? faceMatchScore;

  factory VerificationResult.fromJson(Map<String, dynamic> json) {
    return VerificationResult(
      verified: json['verified'] == true,
      message:
          json['message'] as String? ??
          'Verification could not be completed. Please try again.',
      faceMatchScore: (json['face_match_score'] as num?)?.toDouble(),
    );
  }
}
