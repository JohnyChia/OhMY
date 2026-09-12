import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';

class VoiceTranscript {
  const VoiceTranscript({
    required this.rawText,
    required this.correctedText,
    this.languageCode,
  });

  final String rawText;
  final String correctedText;
  final String? languageCode;
}

class ApiService {
  static const _configuredApiUrl = String.fromEnvironment('AI_CHATBOT_URL');
  static const _requestTimeout = Duration(seconds: 30);

  static String get apiUrl {
    if (_configuredApiUrl.isNotEmpty) {
      return _configuredApiUrl;
    }
    if (kIsWeb) {
      return 'http://localhost:3001';
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      // The local run workflow exposes the backend with `adb reverse`. Using
      // loopback works for both a USB-connected phone and an emulator, while
      // 10.0.2.2 is an emulator-only host alias and fails every request on a
      // physical Android device.
      return 'http://127.0.0.1:3001';
    }
    return 'http://127.0.0.1:3001';
  }

  // Use the signed-in user so agent updates share the same profile and
  // recommendations as User Management. Anonymous development still works.
  static final String _anonymousUserId =
      'mobile_usr_${Random().nextInt(10000000)}';

  static String get userId {
    try {
      return Supabase.instance.client.auth.currentUser?.id ?? _anonymousUserId;
    } catch (_) {
      // The standalone chatbot preview does not initialise Supabase.
      return _anonymousUserId;
    }
  }

  static Future<Map<String, String>> _authorizationHeaders({
    bool json = false,
  }) async {
    String? accessToken;
    try {
      // Do not refresh a session inside every chat turn: certain Android auth
      // providers can keep that refresh pending and prevent /api/chat from
      // ever being sent. The backend rejects expired tokens explicitly.
      accessToken = Supabase.instance.client.auth.currentSession?.accessToken;
    } catch (_) {
      // The caller receives a clear sign-in message when Supabase is not
      // initialised or the session has expired.
    }
    return <String, String>{
      if (json) 'Content-Type': 'application/json',
      if (accessToken?.isNotEmpty == true)
        'Authorization': 'Bearer $accessToken',
    };
  }

  static Future<Map<String, dynamic>> chat(
    String message, {
    bool isVoice = false,
    Map<String, dynamic>? attachment,
    String? inputLanguage,
  }) async {
    try {
      http.Response? response;
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          response = await http
              .post(
                Uri.parse('$apiUrl/api/chat'),
                headers: await _authorizationHeaders(json: true),
                body: jsonEncode({
                  'user_id': userId,
                  'message': message,
                  'isVoice': isVoice,
                  'interaction_mode': isVoice ? 'driving_voice' : 'chat_text',
                  'attachment': ?attachment,
                  if (inputLanguage?.isNotEmpty == true)
                    'input_language': inputLanguage,
                }),
              )
              .timeout(_requestTimeout);
          break;
        } on http.ClientException {
          if (attempt == 1) rethrow;
          // Node may still be completing startup immediately after adb reverse
          // is configured. Retry this transport-only failure once; do not
          // retry a completed HTTP request or duplicate an Agent action.
          await Future<void>.delayed(const Duration(milliseconds: 750));
        }
      }
      if (response == null) {
        return {
          'success': false,
          'error': 'Nova connection was not established.',
        };
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        return {
          'success': false,
          'error': 'Nova returned an invalid response.',
        };
      }
      final data = Map<String, dynamic>.from(decoded);
      if (kDebugMode) {
        debugPrint(
          'Nova chat HTTP ${response.statusCode}; '
          'success=${data['success'] == true}; '
          'error=${data['error'] ?? ''}',
        );
      }
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return data;
      }
      return {
        'success': false,
        'error':
            data['error']?.toString() ?? 'Server error: ${response.statusCode}',
      };
    } catch (e) {
      debugPrint("API Chat Error: $e");
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> clearSession() async {
    try {
      final response = await http.delete(
        Uri.parse('$apiUrl/api/chat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': userId}),
      );
      return jsonDecode(response.body);
    } catch (e) {
      debugPrint('Error clearing session: $e');
      rethrow;
    }
  }

  static Future<VoiceTranscript> transcribeAudio(
    String audioPath, {
    String? context,
  }) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$apiUrl/api/transcribe'),
      );
      request.headers.addAll(await _authorizationHeaders());
      request.fields['user_id'] = userId;
      if (context?.trim().isNotEmpty == true) {
        request.fields['context'] = context!.trim();
      }
      request.files.add(await http.MultipartFile.fromPath('audio', audioPath));

      var streamedResponse = await request.send().timeout(_requestTimeout);
      var response = await http.Response.fromStream(
        streamedResponse,
      ).timeout(_requestTimeout);

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw Exception(
          'Nova transcription service returned an invalid response.',
        );
      }
      final data = Map<String, dynamic>.from(decoded);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          data['error'] ?? 'Nova could not transcribe that audio.',
        );
      }
      if (data['success'] != true) {
        throw Exception(data['error'] ?? 'Unknown error');
      }
      final correctedText = (data['correctedText'] ?? data['text'] ?? '')
          .toString()
          .trim();
      final rawText = (data['rawText'] ?? correctedText).toString().trim();
      if (correctedText.isEmpty) {
        throw Exception('Speech transcription was empty');
      }
      final languageCode = data['languageCode']?.toString().trim();
      return VoiceTranscript(
        rawText: rawText,
        correctedText: correctedText,
        languageCode: languageCode?.isNotEmpty == true ? languageCode : null,
      );
    } catch (e) {
      debugPrint('Error transcribing audio: $e');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> resolveVoiceChoice({
    required String transcript,
    required String mode,
    required List<Map<String, dynamic>> choices,
    int? selectedIndex,
  }) async {
    final response = await http
        .post(
          Uri.parse('$apiUrl/api/voice-choice'),
          headers: await _authorizationHeaders(json: true),
          body: jsonEncode({
            'user_id': userId,
            'transcript': transcript,
            'mode': mode,
            'choices': choices,
            'selectedIndex': ?selectedIndex,
          }),
        )
        .timeout(const Duration(seconds: 8));
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const FormatException('Voice choice response was not an object.');
    }
    final data = Map<String, dynamic>.from(decoded);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(data['error'] ?? 'Voice choice could not be resolved.');
    }
    return data;
  }

  static Future<Map<String, dynamic>> analyzeAttachment(
    String attachmentPath,
  ) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$apiUrl/api/analyze-attachment'),
    );
    request.headers.addAll(await _authorizationHeaders());
    request.fields['user_id'] = userId;
    request.files.add(
      await http.MultipartFile.fromPath('attachment', attachmentPath),
    );
    final streamed = await request.send().timeout(_requestTimeout);
    final response = await http.Response.fromStream(
      streamed,
    ).timeout(_requestTimeout);
    Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw const FormatException('Response was not an object.');
      }
      data = Map<String, dynamic>.from(decoded);
    } on FormatException {
      throw Exception(
        'Nova could not reach the attachment service. Check that the Nova backend is running at the configured URL.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        data['error'] ?? 'Nova could not analyse this attachment.',
      );
    }
    if (data['success'] != true) {
      throw Exception(data['error'] ?? 'Attachment analysis failed.');
    }
    return Map<String, dynamic>.from(data['analysis'] as Map);
  }

  static Future<void> saveTravelItemBinary({
    required String itemId,
    required String attachmentPath,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$apiUrl/api/save-travel-item-binary'),
    );
    request.headers.addAll(await _authorizationHeaders());
    request.fields['user_id'] = userId;
    request.fields['item_id'] = itemId;
    request.files.add(
      await http.MultipartFile.fromPath('attachment', attachmentPath),
    );
    final streamed = await request.send().timeout(_requestTimeout);
    final response = await http.Response.fromStream(
      streamed,
    ).timeout(_requestTimeout);
    final decoded = jsonDecode(response.body);
    final data = decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : const <String, dynamic>{};
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        data['success'] != true) {
      throw Exception(data['error'] ?? 'The original file could not be saved.');
    }
  }
}
