class VerificationResult {
  const VerificationResult({
    required this.verified,
    required this.message,
    this.faceMatchScore,
    this.code,
    this.retryable = true,
  });

  final bool verified;
  final String message;
  final double? faceMatchScore;
  final String? code;
  final bool retryable;

  String get failureTitle => switch (code) {
    'invalid_image' => 'Photo could not be read',
    'low_resolution' => 'ID photo resolution is too low',
    'blurred_document' => 'ID photo is too blurry',
    'missing_back' => 'MyKad back photo is missing',
    'invalid_mykad' => 'MyKad details not recognised',
    'invalid_passport' => 'Passport details not recognised',
    'expired_passport' => 'Passport has expired',
    'document_face_not_found' => 'ID portrait not detected',
    'selfie_face_not_found' => 'Selfie face not detected',
    'face_mismatch' => 'Selfie does not match the ID',
    'identity_linked' => 'Identity already linked',
    'authentication' => 'Sign-in session expired',
    _ => 'Verification could not be completed',
  };

  String get retryGuidance => switch (code) {
    'invalid_image' =>
      'Retake the photo or upload a standard JPEG or PNG image.',
    'low_resolution' =>
      'Move closer while keeping every edge of the ID visible, then retake it.',
    'blurred_document' =>
      'Hold the camera steady, use brighter light and avoid glare before retaking it.',
    'missing_back' => 'Capture the back of the same MyKad before continuing.',
    'invalid_mykad' =>
      'Retake the MyKad front clearly so “MALAYSIA” and the complete 12-digit IC number can be read.',
    'invalid_passport' =>
      'Open the passport biodata page fully and make the two machine-readable lines sharp and visible.',
    'expired_passport' => 'Use a passport that has not expired.',
    'document_face_not_found' =>
      'Retake the ID front with one unobstructed portrait visible and no other faces in frame.',
    'selfie_face_not_found' =>
      'Retake the selfie with exactly one face centred, well lit and unobstructed.',
    'face_mismatch' =>
      'Use the document owner’s face, remove masks or sunglasses and face the camera directly.',
    'identity_linked' =>
      'Sign in to the account already verified with this identity, or contact support.',
    'authentication' => 'Sign in again, then restart identity verification.',
    _ => 'Review the reason above and retake the affected photo.',
  };

  factory VerificationResult.fromJson(Map<String, dynamic> json) {
    return VerificationResult(
      verified: json['verified'] == true,
      message:
          json['message'] as String? ??
          'Verification could not be completed. Please try again.',
      faceMatchScore: (json['face_match_score'] as num?)?.toDouble(),
      code: json['code'] as String?,
      retryable: json['retryable'] != false,
    );
  }
}
