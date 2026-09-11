import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'dart:math';

class ApiService {
  static const _configuredApiUrl = String.fromEnvironment('AI_CHATBOT_URL');

  static String get apiUrl {
    if (_configuredApiUrl.isNotEmpty) {
      return _configuredApiUrl;
    }
    if (kIsWeb) {
      return 'http://localhost:3001';
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:3001';
    }
    return 'http://127.0.0.1:3001';
  }

  static String userId = 'mobile_usr_${Random().nextInt(10000000)}';

  static Future<Map<String, dynamic>> chat(String message) async {
    try {
      final response = await http.post(
        Uri.parse('$apiUrl/api/chat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': userId, 'message': message}),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        return {
          'success': false,
          'error': 'Server error: ${response.statusCode}',
        };
      }
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

  static Future<String> transcribeAudio(String audioPath) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$apiUrl/api/transcribe'),
      );
      request.files.add(await http.MultipartFile.fromPath('audio', audioPath));

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      final data = jsonDecode(response.body);
      if (data['success'] != true) {
        throw Exception(data['error'] ?? 'Unknown error');
      }
      return data['text'];
    } catch (e) {
      debugPrint('Error transcribing audio: $e');
      rethrow;
    }
  }
}
