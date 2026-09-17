import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_app/user_management/services/verification_service.dart';

void main() {
  group('VerificationService.parseResponse', () {
    test('reports a plain-text server error as service unavailable', () {
      expect(
        () => VerificationService.parseResponse(
          http.Response('Internal Server Error', 500),
        ),
        throwsA(
          isA<VerificationFailure>().having(
            (error) => error.message,
            'message',
            contains('unavailable'),
          ),
        ),
      );
    });

    test('uses a JSON API error detail when one is supplied', () {
      expect(
        () => VerificationService.parseResponse(
          http.Response(
            '{"detail":"Tesseract OCR is not installed on the laptop."}',
            503,
          ),
        ),
        throwsA(
          isA<VerificationFailure>().having(
            (error) => error.message,
            'message',
            'Tesseract OCR is not installed on the laptop.',
          ),
        ),
      );
    });

    test('parses a successful verification result', () {
      final result = VerificationService.parseResponse(
        http.Response(
          '{"verified":true,"message":"Verification successful.",'
          '"face_match_score":0.91}',
          200,
        ),
      );

      expect(result.verified, isTrue);
      expect(result.message, 'Verification successful.');
      expect(result.faceMatchScore, 0.91);
    });

    test('preserves a failure code and provides targeted retry guidance', () {
      final result = VerificationService.parseResponse(
        http.Response(
          '{"verified":false,"code":"selfie_face_not_found",'
          '"message":"No clear face was found in your selfie."}',
          200,
        ),
      );

      expect(result.code, 'selfie_face_not_found');
      expect(result.failureTitle, 'Selfie face not detected');
      expect(result.retryGuidance, contains('selfie'));
      expect(result.retryGuidance, contains('one face'));
    });

    test('explains when MyKad text recognition failed', () {
      final result = VerificationService.parseResponse(
        http.Response(
          '{"verified":false,"code":"invalid_mykad",'
          '"message":"This does not look like a Malaysian MyKad."}',
          200,
        ),
      );

      expect(result.failureTitle, 'MyKad details not recognised');
      expect(result.retryGuidance, contains('MALAYSIA'));
      expect(result.retryGuidance, contains('12-digit'));
    });
  });
}
