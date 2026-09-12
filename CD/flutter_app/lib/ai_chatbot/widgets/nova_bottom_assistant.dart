import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/nova_voice_controller.dart';
import 'nova_waveform.dart';

class NovaBottomAssistant extends StatefulWidget {
  const NovaBottomAssistant({
    super.key,
    required this.state,
    this.onDismiss,
    this.showResponse = true,
    this.showIdleTrigger = false,
    this.compact = false,
  });

  final NovaVoiceState state;
  final VoidCallback? onDismiss;
  final bool showResponse;
  final bool showIdleTrigger;
  final bool compact;

  @override
  State<NovaBottomAssistant> createState() => _NovaBottomAssistantState();
}

class _NovaBottomAssistantState extends State<NovaBottomAssistant>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // Create the ticker while the element is active. A lazy field initializer
    // can otherwise first run from dispose when a transient voice overlay is
    // inserted and removed in the same frame.
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
  }

  NovaVoiceState get state => widget.state;

  String get _label => switch (state.phase) {
    NovaVoicePhase.listening => 'Listening…',
    NovaVoicePhase.invocationDetected => 'Nova is ready…',
    NovaVoicePhase.prompting => 'Nova is ready to help…',
    NovaVoicePhase.processing => 'Processing your voice…',
    NovaVoicePhase.thinking => 'Thinking…',
    NovaVoicePhase.executing => 'Working on it…',
    NovaVoicePhase.awaitingConfirmation => 'Waiting for your confirmation…',
    NovaVoicePhase.speaking => 'Nova is speaking…',
    NovaVoicePhase.completed => 'Done',
    NovaVoicePhase.interrupted => 'Interrupted',
    NovaVoicePhase.error => 'Nova needs a moment',
    NovaVoicePhase.idle => 'Nova',
  };

  @override
  Widget build(BuildContext context) {
    if (state.phase == NovaVoicePhase.idle) {
      if (!widget.showIdleTrigger) return const SizedBox.shrink();
      return const SizedBox.shrink();
    }
    final response = state.response ?? state.message;
    final hasResponse =
        widget.showResponse && response != null && response.isNotEmpty;
    if (widget.compact) {
      return FadeTransition(
        opacity: Tween<double>(begin: .9, end: 1).animate(_controller),
        child: Material(
          color: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 260),
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(
                colors: [Color(0xF2163158), Color(0xF1443175)],
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x2609132A),
                  blurRadius: 12,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 62,
                  height: 28,
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: SizedBox(
                      width: 128,
                      height: 28,
                      child: NovaWaveform(
                        phase: state.phase.name,
                        amplitude: state.amplitude,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    state.message?.isNotEmpty == true ? state.message! : _label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 12),
                  ),
                ),
                if (widget.onDismiss != null)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: widget.onDismiss,
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 19,
                      color: Colors.white70,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }
    return AnimatedSize(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      child: FadeTransition(
        opacity: Tween<double>(begin: .88, end: 1).animate(_controller),
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              colors: [Color(0xF2163158), Color(0xF1443175)],
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x2609132A),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    NovaWaveform(
                      phase: state.phase.name,
                      amplitude: state.amplitude,
                    ),
                    const SizedBox(height: 3),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, .2),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      child: Text(
                        _label,
                        key: ValueKey(state.phase),
                        style: GoogleFonts.inter(
                          color: const Color(0xFFBDEAFF),
                          fontSize: 11,
                        ),
                      ),
                    ),
                    if (hasResponse) ...[
                      const SizedBox(height: 2),
                      Text(
                        response,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 13,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (widget.onDismiss != null)
                IconButton(
                  onPressed: widget.onDismiss,
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  tooltip: 'Dismiss Nova',
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
