import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:record/record.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image_picker/image_picker.dart';

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'dart:io' show Platform;

import 'services/api_service.dart';
import 'services/voice_text_pipeline.dart';
import 'services/nova_attachment_picker.dart';
import 'services/nova_voice_controller.dart';
import 'services/nova_voice_choice_controller.dart';
import 'services/nova_barge_in_service.dart';
import 'services/nova_invocation_manager.dart';
import 'services/nova_action_bridge.dart';
import 'services/nova_owner_action_dispatcher.dart';
import 'services/nova_conversation_context.dart';
import 'models/nova_attachment.dart';
import 'widgets/chat_bubble.dart';
import 'widgets/nova_orb.dart';
import 'widgets/nova_bottom_assistant.dart';
import 'widgets/custom_app_bar.dart';
import 'widgets/bottom_nav_bar.dart';

void main() {
  runApp(const NovaApp());
}

class NovaApp extends StatelessWidget {
  const NovaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Travel AI Assistant',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(
          0xFFEAF4FE,
        ), // Match prototype background
        textTheme: GoogleFonts.interTextTheme(),
      ),
      home: const ChatScreen(),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, this.showBottomNavigation = true});

  final bool showBottomNavigation;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<Map<String, dynamic>> _messages = [];
  final TextEditingController _textController = TextEditingController();
  final FocusNode _composerFocusNode = FocusNode();
  bool _isRecording = false;
  bool _isSending = false;
  bool _voiceTurnActive = false;
  Map<String, dynamic>? _tripState;
  NovaAttachment? _attachment;

  late final AudioRecorder _audioRecorder;
  late final FlutterTts _flutterTts;
  String? _recordingPath;
  StreamSubscription<Amplitude>? _amplitudeSubscription;
  Timer? _silenceTimer;
  Timer? _maximumRecordingTimer;
  bool _speechDetected = false;
  DateTime? _recordingStartedAt;
  double? _noiseFloorDb;
  bool _isStoppingRecording = false;
  int _voiceGeneration = 0;
  int _requestGeneration = 0;

  @override
  void initState() {
    super.initState();
    _audioRecorder = AudioRecorder();
    _flutterTts = FlutterTts();
    _initTts();
    unawaited(_initializeNova());
    NovaVoiceController.startRequests.addListener(_startRequestedVoiceSession);
  }

  Future<void> _initializeNova() async {
    await NovaInvocationManager.initialize();
    // Starts only once the native Activity declares itself foreground-ready.
    await NovaInvocationManager.startForegroundWakeListener();
  }

  Future<void> _pickPhoto() async {
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (!mounted || image == null) return;
      await _selectAttachment(
        NovaAttachment(
          name: image.name,
          path: image.path,
          type: NovaAttachmentType.image,
          analysisStatus: NovaAttachmentAnalysisStatus.selected,
        ),
      );
    } catch (error) {
      _showAttachmentPickerError(error);
    }
  }

  Future<void> _pickFile() async {
    try {
      final file = await NovaAttachmentPicker.pickDocument();
      if (!mounted || file == null || file.path.isEmpty) return;
      await _selectAttachment(
        NovaAttachment(
          name: file.name,
          path: file.path,
          mimeType: file.mimeType,
          type: NovaAttachmentType.file,
          analysisStatus: NovaAttachmentAnalysisStatus.selected,
        ),
      );
    } catch (error) {
      _showAttachmentPickerError(error);
    }
  }

  void _showAttachmentPickerError(Object error) {
    if (!mounted) return;
    final message = error is PlatformException
        ? (error.message ?? error.code)
        : error.toString();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _replaceAssistantMessage(
    String messageId,
    String text, {
    Map<String, dynamic>? metadata,
  }) {
    final index = _messages.indexWhere((message) => message['id'] == messageId);
    final replacement = <String, dynamic>{
      if (metadata != null) ...metadata,
      'id': messageId,
      'role': 'assistant',
      'text': text,
    };
    if (index == -1) {
      _messages.add(replacement);
    } else {
      _messages[index] = replacement;
    }
  }

  Future<void> _selectAttachment(NovaAttachment attachment) async {
    if (!mounted) return;
    setState(() => _attachment = attachment);
  }

  void _showAttachmentMenu() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_outlined),
              title: const Text('Upload photo'),
              subtitle: const Text('Travel menu, ticket, sign, map, or place'),
              onTap: () {
                Navigator.pop(context);
                unawaited(_pickPhoto());
              },
            ),
            ListTile(
              leading: const Icon(Icons.attach_file_rounded),
              title: const Text('Upload file'),
              subtitle: const Text(
                'Travel-related JPEG, PNG, WebP, TXT, or PDF up to 8 MB',
              ),
              onTap: () {
                Navigator.pop(context);
                unawaited(_pickFile());
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _initTts() async {
    if (!kIsWeb && Platform.isWindows) {
      return; // flutter_tts crashes on Windows with thread error
    }
    try {
      await _flutterTts.setLanguage("en-US");
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);
      await _flutterTts.awaitSpeakCompletion(true);
    } catch (e) {
      debugPrint("TTS Init Error: $e");
    }
  }

  @override
  void dispose() {
    _voiceGeneration++;
    _requestGeneration++;
    _silenceTimer?.cancel();
    _maximumRecordingTimer?.cancel();
    _amplitudeSubscription?.cancel();
    _flutterTts.stop();
    _audioRecorder.dispose();
    _textController.dispose();
    _composerFocusNode.dispose();
    NovaVoiceController.startRequests.removeListener(
      _startRequestedVoiceSession,
    );
    NovaVoiceController.reset();
    super.dispose();
  }

  void _startRequestedVoiceSession() {
    final invocation = NovaVoiceController.takePendingInvocation();
    if (invocation != null) {
      NovaConversationContext.beginSession(
        sessionId: invocation.sessionId,
        source: invocation.source,
      );
    }
    unawaited(_beginVoiceSession(announce: invocation?.announce ?? false));
  }

  Future<void> _beginVoiceSession({bool announce = false}) async {
    // A new invocation is authoritative: a late API/TTS callback from the
    // prior turn must never speak over it.
    _voiceGeneration++;
    _requestGeneration++;
    await _flutterTts.stop();
    if (_isRecording) {
      await _stopRecording(discardRecording: true);
    }
    if (announce) {
      final voiceGeneration = ++_voiceGeneration;
      NovaVoiceController.update(
        phase: NovaVoicePhase.prompting,
        response: NovaVoiceController.wakePrompt,
        amplitude: 0.45,
        clearMessage: true,
      );
      try {
        // awaitSpeakCompletion(true) is configured in _initTts, so normal
        // recording cannot begin until the prompt has completed.
        await _flutterTts.speak(NovaVoiceController.wakePrompt);
      } catch (_) {
        // A failed greeting must not prevent the user from making a request.
      }
      if (!mounted || voiceGeneration != _voiceGeneration) return;
    }
    await _startRecording();
  }

  Future<void> _startRecording() async {
    if (_isRecording || _isStoppingRecording) return;
    try {
      await NovaInvocationManager.stopForegroundWakeListener();
      await _flutterTts.stop();
      if (await _audioRecorder.hasPermission()) {
        final dir = await getTemporaryDirectory();
        _recordingPath = '${dir.path}/recording.m4a';

        await _audioRecorder.start(
          const RecordConfig(
            encoder: AudioEncoder.aacLc,
            sampleRate: 16000,
            numChannels: 1,
            bitRate: 64000,
            autoGain: true,
            echoCancel: true,
            noiseSuppress: true,
          ),
          path: _recordingPath!,
        );
        _speechDetected = false;
        _recordingStartedAt = DateTime.now();
        _noiseFloorDb = null;
        _silenceTimer?.cancel();
        _maximumRecordingTimer?.cancel();
        await _amplitudeSubscription?.cancel();
        _amplitudeSubscription = _audioRecorder
            .onAmplitudeChanged(const Duration(milliseconds: 80))
            .listen((amplitude) {
              if (!_isRecording) return;
              final normalized = ((amplitude.current + 55) / 55).clamp(
                0.0,
                1.0,
              );
              NovaVoiceController.update(amplitude: normalized);
              final recordingAge = DateTime.now().difference(
                _recordingStartedAt ?? DateTime.now(),
              );
              if (!_speechDetected &&
                  recordingAge < const Duration(milliseconds: 400) &&
                  amplitude.current.isFinite) {
                _noiseFloorDb = _noiseFloorDb == null
                    ? amplitude.current
                    : (_noiseFloorDb! * 0.7) + (amplitude.current * 0.3);
              }
              final calibratedFloor = _noiseFloorDb ?? -55.0;
              final speechThreshold = (calibratedFloor + 7).clamp(-58.0, -20.0);
              // Huawei and other Android vendors expose different amplitude
              // scales. Calibrate against the quiet opening of each turn,
              // then finish quickly after the speaker pauses.
              if (amplitude.current > speechThreshold &&
                  recordingAge > const Duration(milliseconds: 220)) {
                _speechDetected = true;
                _silenceTimer?.cancel();
                _silenceTimer = Timer(const Duration(milliseconds: 900), () {
                  if (_isRecording && _speechDetected) {
                    unawaited(_stopRecording());
                  }
                });
              }
            });

        setState(() {
          _isRecording = true;
          _voiceTurnActive = true;
        });
        NovaVoiceController.update(
          phase: NovaVoicePhase.listening,
          message: 'I’m listening. What can I help you with?',
          clearResponse: true,
        );
        // This preserves a hands-free request flow once an approved foreground
        // invocation source starts it, while never recording indefinitely.
        _maximumRecordingTimer = Timer(const Duration(seconds: 10), () {
          if (!_isRecording) return;
          if (_speechDetected) {
            unawaited(_stopRecording());
          } else {
            unawaited(_finishSilentRecording());
          }
        });
      } else {
        NovaVoiceController.update(
          phase: NovaVoicePhase.error,
          message: 'Microphone access is needed to talk to Nova.',
        );
        unawaited(_rearmWakeListenerAfterVoiceFailure(_requestGeneration));
      }
    } catch (e) {
      debugPrint('Failed to start recording: $e');
      NovaVoiceController.update(
        phase: NovaVoicePhase.error,
        message: 'I could not start the microphone. Try again?',
      );
      unawaited(_rearmWakeListenerAfterVoiceFailure(_requestGeneration));
    }
  }

  Future<void> _finishSilentRecording() async {
    await _stopRecording(discardRecording: true);
    if (!mounted) return;
    NovaVoiceController.update(
      phase: NovaVoicePhase.completed,
      message: 'Voice session ended.',
    );
  }

  Future<void> _stopRecording({bool discardRecording = false}) async {
    if (_isStoppingRecording || !_isRecording) return;
    _isStoppingRecording = true;
    final requestGeneration = _requestGeneration;
    try {
      final path = await _audioRecorder.stop();
      await _amplitudeSubscription?.cancel();
      _amplitudeSubscription = null;
      _silenceTimer?.cancel();
      _maximumRecordingTimer?.cancel();
      setState(() {
        _isRecording = false;
      });

      if (discardRecording || requestGeneration != _requestGeneration) {
        if (mounted) setState(() => _voiceTurnActive = false);
        return;
      }
      if (path != null) {
        NovaVoiceController.update(
          phase: NovaVoicePhase.thinking,
          message: 'Thinking…',
        );
        final snapshot = NovaConversationContext.snapshot.value;
        final transcript = await VoiceTextPipeline.processAudio(
          path,
          context:
              [
                    snapshot.currentPage,
                    snapshot.lastUserMessage,
                    snapshot.lastAssistantMessage,
                    snapshot.lastAction?.parameters['destination']?.toString(),
                  ]
                  .whereType<String>()
                  .where((value) => value.trim().isNotEmpty)
                  .join(' | '),
        );
        if (!mounted || requestGeneration != _requestGeneration) return;
        if (await NovaVoiceChoiceController.consume(transcript.correctedText)) {
          if (!mounted || requestGeneration != _requestGeneration) return;
          setState(() => _voiceTurnActive = false);
          NovaVoiceController.update(
            phase: NovaVoicePhase.completed,
            message: 'Voice choice applied.',
          );
          unawaited(_rearmWakeListenerAfterVoiceFailure(requestGeneration));
          return;
        }
        // A speech recognizer cannot promise a perfect written transcript.
        // Keep the canonical transcript private to the Agent instead of
        // displaying an incorrect sentence in the user's blue chat bubble.
        await _sendMessage(
          transcript.correctedText,
          isVoice: true,
          showUserMessage: false,
          inputLanguage: transcript.languageCode,
        );
      } else {
        NovaVoiceController.update(
          phase: NovaVoicePhase.error,
          message: "I didn't catch that. Try again?",
        );
        unawaited(_rearmWakeListenerAfterVoiceFailure(requestGeneration));
      }
    } catch (e) {
      debugPrint('Failed to stop recording: $e');
      final errorMessage = _friendlyNovaError(
        e,
        fallback: "I didn't catch that. Try again?",
      );
      NovaVoiceController.update(
        phase: NovaVoicePhase.error,
        message: errorMessage,
      );
      unawaited(_rearmWakeListenerAfterVoiceFailure(requestGeneration));
    } finally {
      _isStoppingRecording = false;
    }
  }

  Future<void> _sendMessage(
    String textToUse, {
    bool isVoice = false,
    bool showUserMessage = true,
    String? replaceAssistantMessageId,
    String? inputLanguage,
  }) async {
    if (!isVoice && _voiceTurnActive) {
      // A manual answer always takes ownership of the conversation turn.
      // Stop every voice surface before dispatching it so TTS, barge-in ASR,
      // and the dynamic island cannot linger over the new response.
      _voiceGeneration++;
      await NovaBargeInService.stop();
      await _flutterTts.stop();
      if (_isRecording) {
        await _stopRecording(discardRecording: true);
      }
      if (!mounted) return;
      setState(() => _voiceTurnActive = false);
      NovaVoiceController.reset();
    }
    final selectedAttachment = _attachment;
    final requestText = textToUse.trim();
    if (requestText.isEmpty) return;
    final requestGeneration = ++_requestGeneration;
    var attachment = selectedAttachment;
    if (attachment != null &&
        attachment.analysisStatus != NovaAttachmentAnalysisStatus.ready) {
      final attachmentName = attachment.name;
      if (mounted) setState(() => _isSending = true);
      if (isVoice) {
        NovaVoiceController.update(
          phase: NovaVoicePhase.thinking,
          message: 'Checking the attachment…',
        );
      }
      try {
        final analysis = await ApiService.analyzeAttachment(attachment.path);
        if (!mounted || requestGeneration != _requestGeneration) return;
        attachment = attachment.copyWith(
          analysisStatus: NovaAttachmentAnalysisStatus.ready,
          mimeType: analysis['mimeType']?.toString(),
          analysis: analysis,
        );
        setState(() {
          _attachment = attachment;
        });
      } catch (error) {
        if (!mounted || requestGeneration != _requestGeneration) return;
        final message = _friendlyNovaError(error, fallback: attachmentName);
        setState(() {
          _isSending = false;
          _attachment = null;
          _messages.add({
            'id': DateTime.now().millisecondsSinceEpoch.toString(),
            'role': 'assistant',
            'text': message,
          });
        });
        if (isVoice) {
          NovaVoiceController.update(
            phase: NovaVoicePhase.error,
            message: message,
          );
        }
        return;
      }
    }
    // An attachment belongs only to the turn on which it is explicitly sent.
    // Reusing a previous upload here made an ordinary follow-up look like a
    // new image upload and allowed stale visual context to drive app actions.
    NovaConversationContext.recordUserTurn(requestText);

    if (showUserMessage) {
      final newMsg = {
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'role': 'user',
        'text': requestText,
        if (isVoice) 'voiceTranscript': true,
        if (attachment != null)
          'attachment': <String, dynamic>{
            'name': attachment.name,
            'path': attachment.path,
            'type': attachment.type.name,
          },
      };
      setState(() {
        _messages.add(newMsg);
      });
    }
    // Do not overwrite the controller while SwiftKey/Gboard is composing a
    // word. Removing focus first lets Android finish its composing region,
    // then clearing on the next frame avoids InputConnection restarts and
    // zero-length span warnings.
    _composerFocusNode.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _textController.clear();
    });

    try {
      if (!mounted) return;
      setState(() => _isSending = true);
      if (isVoice) {
        NovaVoiceController.update(
          phase: NovaVoicePhase.thinking,
          message: 'Thinking…',
        );
      }
      final data = await ApiService.chat(
        requestText,
        isVoice: isVoice,
        attachment: attachment?.toAgentInput(),
        inputLanguage: inputLanguage,
      );
      if (data['success'] == true &&
          attachment != null &&
          _responseIntent(data) == 'save_travel_item') {
        final toolResult = data['tool_result'];
        final savedItem = toolResult is Map ? toolResult['item'] : null;
        final savedItemId = savedItem is Map
            ? savedItem['id']?.toString()
            : null;
        if (savedItemId?.isNotEmpty == true) {
          try {
            await ApiService.saveTravelItemBinary(
              itemId: savedItemId!,
              attachmentPath: attachment.path,
            );
          } catch (error) {
            debugPrint('Nova saved metadata but binary upload failed: $error');
          }
        }
      }
      if (mounted && attachment != null && identical(attachment, _attachment)) {
        setState(() => _attachment = null);
      }
      if (!mounted || requestGeneration != _requestGeneration) return;

      NovaOwnerActionResult? ownerActionResult;
      NovaAction? publishedAction;
      if (data['success'] == true) {
        NovaVoiceController.update(
          languageCode: data['languageCode']?.toString() ?? 'en',
        );
        final action = NovaActionBridge.publish(data['action']);
        publishedAction = action;
        if (data['action'] != null && action == null) {
          // A malformed server payload is an integration diagnostic, not a
          // traveller-facing chat response. The natural Agent reply remains
          // the authoritative message shown in the conversation.
          debugPrint('Nova ignored an invalid action payload from the server.');
        } else {
          ownerActionResult = await NovaOwnerActionDispatcher.dispatch(action);
        }
        if (!mounted || requestGeneration != _requestGeneration) return;
      }

      setState(() {
        if (data['success'] == true) {
          _tripState = data['trip_state'];
          if (ownerActionResult?.executed == true) {
            NovaConversationContext.recordAction(
              NovaActionBridge.lastAction.value,
            );
          }
          NovaConversationContext.recordAssistantTurn(data['reply'].toString());
          final Map<String, dynamic> responseMessage = {
            'id': (DateTime.now().millisecondsSinceEpoch + 1).toString(),
            'role': 'assistant',
            'text': data['reply'],
            'intent': data['intent'],
            'tool_result': data['tool_result'],
            'language': data['language'],
            'agent_actions': data['agent_actions'],
          };
          if (replaceAssistantMessageId != null) {
            _replaceAssistantMessage(
              replaceAssistantMessageId,
              data['reply'].toString(),
              metadata: responseMessage,
            );
          } else {
            _messages.add(responseMessage);
          }
          if (ownerActionResult != null && !ownerActionResult.executed) {
            debugPrint(
              'Nova owner action was not executed: '
              '${ownerActionResult.errorCode ?? ownerActionResult.status.name}',
            );
          }

          final routePageOwnsVoice =
              ownerActionResult?.executed == true &&
              publishedAction?.type == 'start_journey';
          if (isVoice && routePageOwnsVoice) {
            // The route owner speaks verified alternatives after they load,
            // then opens a fresh hands-free confirmation session. Speaking
            // the chat handoff here would overlap that route narration.
            _voiceTurnActive = false;
          } else if (isVoice && data['reply'] != null) {
            if (!kIsWeb && Platform.isWindows) {
              debugPrint(
                "TTS is disabled on Windows due to platform thread issues.",
              );
              NovaVoiceController.update(
                phase: NovaVoicePhase.completed,
                response: data['reply'].toString(),
              );
              _voiceTurnActive = false;
            } else {
              final hasToolWork =
                  (data['tool_results'] as List?)?.isNotEmpty == true;
              if (hasToolWork) {
                NovaVoiceController.update(
                  phase: NovaVoicePhase.executing,
                  message: 'Getting that ready…',
                );
              }
              final languageCode = data['languageCode']?.toString() ?? 'en';
              final lang = languageCode.toLowerCase().startsWith('ms')
                  ? 'ms-MY'
                  : languageCode.toLowerCase().startsWith('zh')
                  ? 'zh-CN'
                  : 'en-US';
              final voiceGeneration = ++_voiceGeneration;
              NovaVoiceController.update(
                phase: NovaVoicePhase.speaking,
                response: data['reply'].toString(),
                amplitude: 0.45,
              );
              unawaited(
                _speak(data['reply'].toString(), voiceGeneration, lang),
              );
            }
          } else if (isVoice) {
            _voiceTurnActive = false;
            NovaVoiceController.update(
              phase: NovaVoicePhase.error,
              message: data['error']?.toString() ?? '',
            );
            unawaited(_rearmWakeListenerAfterVoiceFailure(requestGeneration));
          }
        } else {
          final errorMessage = _friendlyNovaError(data['error'], fallback: '');
          if (replaceAssistantMessageId != null) {
            _replaceAssistantMessage(replaceAssistantMessageId, errorMessage);
          } else {
            _messages.add({
              'id': DateTime.now().millisecondsSinceEpoch.toString(),
              'role': 'assistant',
              'text': errorMessage,
            });
          }
          if (isVoice) {
            _voiceTurnActive = false;
            NovaVoiceController.update(
              phase: NovaVoicePhase.error,
              message: errorMessage,
            );
            unawaited(_rearmWakeListenerAfterVoiceFailure(requestGeneration));
          }
        }
      });
    } catch (e) {
      final errorMessage = _friendlyNovaError(e, fallback: '');
      setState(() {
        if (replaceAssistantMessageId != null) {
          _replaceAssistantMessage(replaceAssistantMessageId, errorMessage);
        } else {
          _messages.add({
            'id': DateTime.now().millisecondsSinceEpoch.toString(),
            'role': 'assistant',
            'text': errorMessage,
          });
        }
      });
      if (isVoice) {
        if (mounted) setState(() => _voiceTurnActive = false);
        NovaVoiceController.update(
          phase: NovaVoicePhase.error,
          message: errorMessage,
        );
        unawaited(_rearmWakeListenerAfterVoiceFailure(requestGeneration));
      }
    } finally {
      if (mounted && requestGeneration == _requestGeneration) {
        setState(() => _isSending = false);
      }
    }
  }

  Future<void> _openRecommendedPlaceForJourney(
    Map<String, dynamic> recommendation,
    Map<String, dynamic> toolResult,
  ) async {
    final destination = recommendation['name']?.toString().trim() ?? '';
    if (destination.isEmpty) return;
    final preferenceValues = toolResult['applied_preferences'];
    final interests = preferenceValues is List
        ? preferenceValues
              .whereType<String>()
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty)
              .toList()
        : <String>[];
    final action = NovaAction(
      type: 'start_journey',
      target: 'trip',
      parameters: <String, dynamic>{
        'destination': destination,
        'interests': interests,
        'budget': _tripState?['budget']?.toString() ?? '',
        'duration': _tripState?['duration'],
        'trip_mode': 'solo',
      },
      requiresConfirmation: true,
    );
    NovaActionBridge.lastAction.value = action;
    final result = await NovaOwnerActionDispatcher.dispatch(action);
    if (result?.executed == true) {
      NovaConversationContext.recordAction(action);
    } else if (kDebugMode) {
      debugPrint(
        'Nova recommendation handoff was not executed: '
        '${result?.errorCode ?? result?.status.name}',
      );
    }
  }

  String _responseIntent(Map<String, dynamic> data) {
    final value = data['intent'];
    if (value is Map) return value['intent']?.toString() ?? '';
    return value?.toString() ?? '';
  }

  String _friendlyNovaError(Object? error, {required String fallback}) {
    final raw =
        error?.toString().replaceFirst(RegExp(r'^Exception:\s*'), '').trim() ??
        '';
    return raw.isNotEmpty ? raw : fallback;
  }

  Future<void> _speak(String text, int voiceGeneration, String language) async {
    var userStartedSpeaking = false;
    try {
      await NovaBargeInService.start(
        languageCode: language,
        onSpeechStarted: () async {
          if (!mounted || voiceGeneration != _voiceGeneration) return;
          userStartedSpeaking = true;
          NovaVoiceController.update(
            phase: NovaVoicePhase.listening,
            clearResponse: true,
          );
          await _flutterTts.stop();
          await NovaBargeInService.stop();
          if (!mounted || voiceGeneration != _voiceGeneration) return;
          await _startRecording();
        },
        onTranscript: (transcript, isFinal) async {
          if (!mounted || voiceGeneration != _voiceGeneration) return;
          NovaVoiceController.update(message: transcript);
          if (!isFinal) return;
          final spoken = transcript
              .toLowerCase()
              .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
              .trim();
          final response = text
              .toLowerCase()
              .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
              .trim();
          // Ignore a multi-word final result that is clearly the device
          // transcribing Nova's own loudspeaker output.
          if (spoken.split(' ').length >= 4 && response.contains(spoken)) {
            return;
          }
          _voiceGeneration++;
          await NovaBargeInService.stop();
          await _flutterTts.stop();
          if (!mounted) return;
          NovaVoiceController.update(
            phase: NovaVoicePhase.thinking,
            message: transcript,
          );
          await _sendMessage(transcript, isVoice: true, showUserMessage: false);
        },
      );
      await _flutterTts.setLanguage(language);
      await _flutterTts.speak(text);
      if (userStartedSpeaking) return;
      await NovaBargeInService.stop();
      if (!mounted || voiceGeneration != _voiceGeneration) return;
      if (NovaVoiceController.state.value.phase != NovaVoicePhase.speaking) {
        return;
      }
      NovaVoiceController.update(phase: NovaVoicePhase.completed);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (mounted && voiceGeneration == _voiceGeneration) {
        // A voice conversation remains hands-free: after Nova asks or answers,
        // immediately listen for the user's next turn. This does not depend on
        // the optional wake-word model being installed.
        await _startRecording();
      }
    } catch (error) {
      await NovaBargeInService.stop();
      if (mounted && voiceGeneration == _voiceGeneration) {
        setState(() => _voiceTurnActive = false);
        NovaVoiceController.update(
          phase: NovaVoicePhase.error,
          message: 'I could not play that response.',
        );
        await NovaInvocationManager.startForegroundWakeListener();
      }
    }
  }

  /// Recording has already stopped at every call site. Re-arm the local wake
  /// provider after a failed voice turn, but never let a stale turn restart it
  /// over a newer recorder session.
  Future<void> _rearmWakeListenerAfterVoiceFailure(
    int requestGeneration,
  ) async {
    if (!mounted ||
        requestGeneration != _requestGeneration ||
        _isRecording ||
        _isStoppingRecording) {
      return;
    }
    setState(() => _voiceTurnActive = false);
    await NovaInvocationManager.startForegroundWakeListener();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(),
      extendBody: widget.showBottomNavigation,
      bottomNavigationBar: widget.showBottomNavigation
          ? const BottomNavBar()
          : null,
      body: SafeArea(
        bottom: false, // Custom bottom nav handles bottom inset
        child: Column(
          children: [
            Expanded(
              child: _messages.isEmpty
                  ? LayoutBuilder(
                      builder: (context, constraints) => SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight > 32
                                ? constraints.maxHeight - 32
                                : 0,
                          ),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                GestureDetector(
                                  onTap: _isSending
                                      ? null
                                      : () =>
                                            NovaVoiceController.requestVoiceSession(
                                              source: NovaInvocationSource
                                                  .chatbotMicrophone,
                                            ),
                                  child: NovaOrb(
                                    isListening: _isRecording,
                                    size: 80,
                                  ),
                                ),
                                const SizedBox(height: 40),
                                Text(
                                  'Your travel agent, ready.',
                                  style: GoogleFonts.inter(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF1E3A8A),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 40,
                                  ),
                                  child: Text(
                                    'Tap Nova to talk. I can plan, update preferences, find community tips, check weather, routes, and itineraries.',
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
                                  'Voice or text • English • Bahasa Malaysia • 中文 • Rojak/Manglish',
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    color: Colors.blueGrey.shade400,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        return ChatBubble(
                          message: _messages[index],
                          tripState: _tripState,
                          onRecommendationSelected:
                              _openRecommendedPlaceForJourney,
                        );
                      },
                    ),
            ),
            if (_attachment != null)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF1FF),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFC8D8F7)),
                ),
                child: Row(
                  children: [
                    Icon(
                      _attachment!.type == NovaAttachmentType.image
                          ? Icons.image_outlined
                          : Icons.description_outlined,
                      color: const Color(0xFF315EA8),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _attachment!.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const Text(
                            'Add a message or use voice, then send',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Describe by voice',
                      onPressed: _isSending
                          ? null
                          : () => NovaVoiceController.requestVoiceSession(
                              source: NovaInvocationSource.chatbotMicrophone,
                            ),
                      icon: const Icon(Icons.mic_none),
                    ),
                    IconButton(
                      tooltip: 'Remove attachment',
                      onPressed: _isSending
                          ? null
                          : () => setState(() => _attachment = null),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),

            if (_voiceTurnActive)
              _LiveVoicePanel(
                onClose: () {
                  unawaited(_flutterTts.stop());
                  if (_isRecording) {
                    unawaited(_stopRecording(discardRecording: true));
                  }
                  setState(() => _voiceTurnActive = false);
                  NovaVoiceController.reset();
                },
              )
            else
              // Input Area
              Container(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                color: Colors.transparent,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        offset: const Offset(0, 4),
                        blurRadius: 15,
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: _showAttachmentMenu,
                        icon: const Icon(Icons.add_circle_outline_rounded),
                        color: const Color(0xFF273D7C),
                        tooltip: 'Add photo or file',
                      ),
                      const Padding(
                        padding: EdgeInsets.only(left: 8.0, right: 12.0),
                        child: NovaOrb(isListening: false, size: 24),
                      ),
                      Expanded(
                        child: ValueListenableBuilder<NovaVoiceState>(
                          valueListenable: NovaVoiceController.state,
                          builder: (_, voiceState, _) => TextField(
                            controller: _textController,
                            focusNode: _composerFocusNode,
                            style: GoogleFonts.inter(fontSize: 14),
                            decoration: InputDecoration(
                              hintText: _isRecording
                                  ? "Listening..."
                                  : _isSending
                                  ? "Nova is thinking..."
                                  : voiceState.phase ==
                                            NovaVoicePhase.speaking ||
                                        voiceState.phase ==
                                            NovaVoicePhase.prompting
                                  ? "Nova is speaking..."
                                  : "Message Nova...",
                              hintStyle: GoogleFonts.inter(
                                color: _isRecording
                                    ? Colors.red.shade400
                                    : Colors.grey.shade500,
                                fontSize: 14,
                              ),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                            onSubmitted: (value) {
                              _composerFocusNode.unfocus();
                              unawaited(_sendMessage(value));
                            },
                          ),
                        ),
                      ),
                      AnimatedBuilder(
                        animation: _textController,
                        builder: (context, _) {
                          final hasText = _textController.text
                              .trim()
                              .isNotEmpty;
                          // Selecting a file is context, not an instruction.
                          // Nova waits for the user's typed or spoken request
                          // so an upload is never implicitly explained, saved,
                          // or opened on the map.
                          final canSend = hasText;
                          return GestureDetector(
                            onTap: _isSending
                                ? null
                                : () {
                                    if (canSend) {
                                      _composerFocusNode.unfocus();
                                      unawaited(
                                        _sendMessage(_textController.text),
                                      );
                                    } else if (_isRecording) {
                                      unawaited(_stopRecording());
                                    } else {
                                      NovaVoiceController.requestVoiceSession(
                                        source: NovaInvocationSource
                                            .chatbotMicrophone,
                                      );
                                    }
                                  },
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: canSend
                                    ? Colors.blueAccent
                                    : (_isRecording
                                          ? Colors.redAccent
                                          : Colors.blue.shade100),
                              ),
                              child: Icon(
                                _isSending
                                    ? Icons.hourglass_top_rounded
                                    : canSend
                                    ? Icons.arrow_upward
                                    : Icons.mic_none,
                                color: _isSending || canSend || _isRecording
                                    ? Colors.white
                                    : Colors.blueAccent,
                                size: 20,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LiveVoicePanel extends StatelessWidget {
  const _LiveVoicePanel({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<NovaVoiceState>(
    valueListenable: NovaVoiceController.state,
    builder: (_, state, _) => NovaBottomAssistant(
      state: state,
      onDismiss: onClose,
      showResponse: true,
    ),
  );
}
