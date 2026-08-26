import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:record/record.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;

import 'services/api_service.dart';
import 'widgets/chat_bubble.dart';
import 'widgets/nova_orb.dart';
import 'widgets/custom_app_bar.dart';
import 'widgets/bottom_nav_bar.dart';

void main() {
  runApp(const WanderVoiceApp());
}

class WanderVoiceApp extends StatelessWidget {
  const WanderVoiceApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Travel AI Assistant',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFFEAF4FE), // Match prototype background
        textTheme: GoogleFonts.interTextTheme(),
      ),
      home: const ChatScreen(),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({Key? key}) : super(key: key);

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<Map<String, dynamic>> _messages = [];
  final TextEditingController _textController = TextEditingController();
  bool _isTyping = false;
  bool _isRecording = false;
  Map<String, dynamic>? _tripState;

  late final AudioRecorder _audioRecorder;
  late final FlutterTts _flutterTts;
  String? _recordingPath;

  @override
  void initState() {
    super.initState();
    _audioRecorder = AudioRecorder();
    _flutterTts = FlutterTts();
    _initTts();
  }

  Future<void> _initTts() async {
    if (!kIsWeb && Platform.isWindows) return; // flutter_tts crashes on Windows with thread error
    try {
      await _flutterTts.setLanguage("en-US");
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);
    } catch (e) {
      print("TTS Init Error: $e");
    }
  }

  @override
  void dispose() {
    _audioRecorder.dispose();
    _textController.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final dir = await getTemporaryDirectory();
        _recordingPath = '${dir.path}/recording.m4a';
        
        await _audioRecorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc), 
          path: _recordingPath!,
        );
        
        setState(() {
          _isRecording = true;
        });
      }
    } catch (e) {
      print('Failed to start recording: $e');
    }
  }

  Future<void> _stopRecording() async {
    try {
      final path = await _audioRecorder.stop();
      setState(() {
        _isRecording = false;
        _isTyping = true;
      });

      if (path != null) {
        final text = await ApiService.transcribeAudio(path);
        _sendMessage(text, isVoice: true);
      }
    } catch (e) {
      print('Failed to stop recording: $e');
      setState(() {
        _isTyping = false;
      });
    }
  }

  Future<void> _sendMessage(String textToUse, {bool isVoice = false}) async {
    if (textToUse.trim().isEmpty) return;

    final newMsg = {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'role': 'user',
      'text': textToUse,
    };

    setState(() {
      _messages.add(newMsg);
      _textController.clear();
      _isTyping = true;
    });

    try {
      final data = await ApiService.chat(textToUse);
      
      setState(() {
        _isTyping = false;
        if (data['success'] == true) {
          _tripState = data['trip_state'];
          _messages.add({
            'id': (DateTime.now().millisecondsSinceEpoch + 1).toString(),
            'role': 'assistant',
            'text': data['reply'],
            'intent': data['intent'],
            'tool_result': data['tool_result'],
            'language': data['language'],
          });
          
          if (isVoice && data['reply'] != null) {
            if (!kIsWeb && Platform.isWindows) {
              print("TTS is disabled on Windows due to platform thread issues.");
            } else {
              String lang = data['intent']?['parameters']?['language'] == 'chinese' ? 'zh-CN' : 'en-US';
              _flutterTts.setLanguage(lang);
              _flutterTts.speak(data['reply']);
            }
          }
        } else {
          _messages.add({
            'id': DateTime.now().millisecondsSinceEpoch.toString(),
            'role': 'assistant',
            'text': "Error: ${data['error']}",
          });
        }
      });
    } catch (e) {
      setState(() {
        _isTyping = false;
        _messages.add({
          'id': DateTime.now().millisecondsSinceEpoch.toString(),
          'role': 'assistant',
          'text': "Network error connecting to the Travel AI.",
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(),
      extendBody: true, // For bottom nav bar overlap
      bottomNavigationBar: const BottomNavBar(),
      body: SafeArea(
        bottom: false, // Custom bottom nav handles bottom inset
        child: Column(
          children: [
            Expanded(
              child: _messages.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const NovaOrb(isListening: true, size: 80),
                          const SizedBox(height: 40),
                          Text(
                            'Where to next?',
                            style: GoogleFonts.inter(
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF1E3A8A),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 40),
                            child: Text(
                              'Ask me to plan a trip, build an itinerary, check live weather, discover hidden gems, reroute around traffic, or adapt to your travel style.',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: Colors.blueGrey.shade600,
                                height: 1.5,
                              ),
                            ),
                          ),
                          const SizedBox(height: 30),
                          Text(
                            'Voice or text • English • Bahasa Malaysia • 中文 • தமிழ்',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              color: Colors.blueGrey.shade400,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        return ChatBubble(
                          message: _messages[index],
                          tripState: _tripState,
                        );
                      },
                    ),
            ),
            
            // Input Area
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), // Extra bottom padding for floating feel
              color: Colors.transparent,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      offset: const Offset(0, 4),
                      blurRadius: 15,
                    ),
                  ],
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(left: 8.0, right: 12.0),
                      child: NovaOrb(isListening: false, size: 24),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _textController,
                        style: GoogleFonts.inter(fontSize: 14),
                        decoration: InputDecoration(
                          hintText: _isRecording ? "Listening..." : "Ask anything about your trip...",
                          hintStyle: GoogleFonts.inter(
                            color: _isRecording ? Colors.red.shade400 : Colors.grey.shade500,
                            fontSize: 14,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        onSubmitted: _sendMessage,
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        if (_textController.text.trim().isNotEmpty) {
                          _sendMessage(_textController.text);
                        } else {
                          if (_isRecording) {
                            _stopRecording();
                          } else {
                            _startRecording();
                          }
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _textController.text.trim().isNotEmpty
                              ? Colors.blueAccent
                              : (_isRecording ? Colors.redAccent : Colors.blue.shade100),
                        ),
                        child: Icon(
                          _textController.text.trim().isNotEmpty ? Icons.arrow_upward : Icons.mic_none,
                          color: _textController.text.trim().isNotEmpty || _isRecording ? Colors.white : Colors.blueAccent,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Extra spacing for bottom nav bar overlap
            const SizedBox(height: 70), 
          ],
        ),
      ),
    );
  }
}
