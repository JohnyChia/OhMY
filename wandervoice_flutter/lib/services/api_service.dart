import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'dart:math';

class ApiService {
  // Use 10.0.2.2 for Android emulator to access host localhost.
  // Use localhost for Web/iOS emulator.
  static String get apiUrl {
    if (kIsWeb) {
      return 'http://localhost:3000';
    }
    // Check if android or ios could be added here, but for simplicity assuming 127.0.0.1 or 10.0.2.2
    // You might want to use your actual local IP (e.g. 192.168.1.x) to test on a physical device
    return 'http://127.0.0.1:3000'; 
  }

  static String userId = 'mobile_usr_${Random().nextInt(10000000)}';

  static Future<Map<String, dynamic>> chat(String message) async {
    try {
      final response = await http.post(
        Uri.parse('$apiUrl/api/chat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': userId,
          'message': message,
        }),
      );
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        return {'success': false, 'error': 'Server error: ${response.statusCode}'};
      }
    } catch (e) {
      print("API Chat Error: $e");
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
      print('Error clearing session: $e');
      rethrow;
    }
  }

  static Future<String> transcribeAudio(String audioPath) async {
    try {
      var request = http.MultipartRequest('POST', Uri.parse('$apiUrl/api/transcribe'));
      request.files.add(await http.MultipartFile.fromPath(
        'audio', 
        audioPath,
      ));
      
      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);
      
      final data = jsonDecode(response.body);
      if (data['success'] != true) {
        throw Exception(data['error'] ?? 'Unknown error');
      }
      return data['text'];
    } catch (e) {
      print('Error transcribing audio: $e');
      rethrow;
    }
  }
}
