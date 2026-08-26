import 'package:flutter/material.dart';

class NovaOrb extends StatefulWidget {
  final bool isListening;
  final double size;

  const NovaOrb({Key? key, required this.isListening, this.size = 32.0}) : super(key: key);

  @override
  _NovaOrbState createState() => _NovaOrbState();
}

class _NovaOrbState extends State<NovaOrb> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    if (widget.isListening) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(NovaOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isListening != oldWidget.isListening) {
      if (widget.isListening) {
        _controller.repeat(reverse: true);
      } else {
        _controller.stop();
        _controller.animateTo(0.0, duration: const Duration(milliseconds: 300));
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: widget.isListening ? _scaleAnimation.value : 1.0,
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Colors.white,
                    Colors.cyanAccent.shade100,
                    Colors.purple.shade300,
                  ],
                  stops: const [0.1, 0.4, 1.0],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.purple.withOpacity(0.3),
                    blurRadius: 20 * _scaleAnimation.value,
                    spreadRadius: 10 * _scaleAnimation.value,
                  ),
                  BoxShadow(
                    color: Colors.blueAccent.withOpacity(0.3),
                    blurRadius: 30 * _scaleAnimation.value,
                    spreadRadius: 5 * _scaleAnimation.value,
                  )
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
