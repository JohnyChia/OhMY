import 'dart:async';

/// Ends a recording after one second without a speech event.
class NovaSilenceCutoff {
  NovaSilenceCutoff(this.onSilence);

  final void Function() onSilence;
  Timer? _timer;

  void arm() {
    cancel();
    _timer = Timer(const Duration(seconds: 1), onSilence);
  }

  void cancel() => _timer?.cancel();
}
