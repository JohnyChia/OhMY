import 'dart:async';

typedef NovaVoiceChoiceHandler = FutureOr<bool> Function(String transcript);

class NovaVoiceChoiceRegistration {
  NovaVoiceChoiceRegistration._(this._handler);

  final NovaVoiceChoiceHandler _handler;
  bool _disposed = false;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    NovaVoiceChoiceController._unregister(_handler);
  }
}

/// Lets the visible owner page consume a spoken answer before Nova treats it
/// as a new chat request. Only one foreground choice owner is active at once.
class NovaVoiceChoiceController {
  NovaVoiceChoiceController._();

  static final List<NovaVoiceChoiceHandler> _handlers = [];

  static NovaVoiceChoiceRegistration register(NovaVoiceChoiceHandler handler) {
    _handlers.add(handler);
    return NovaVoiceChoiceRegistration._(handler);
  }

  static void _unregister(NovaVoiceChoiceHandler handler) {
    _handlers.removeWhere((candidate) => identical(candidate, handler));
  }

  static Future<bool> consume(String transcript) async {
    if (_handlers.isEmpty) return false;
    return await _handlers.last(transcript);
  }
}
