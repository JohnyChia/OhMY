import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:record/record.dart';

/// Requests only the runtime permissions Nova actually uses. Android's system
/// remains authoritative when a traveller denies or permanently blocks one.
class NovaInitialPermissionService {
  NovaInitialPermissionService._();

  static bool _requested = false;

  static Future<void> requestForFirstUse() async {
    if (_requested) return;
    _requested = true;

    final recorder = AudioRecorder();
    try {
      await recorder.hasPermission();
    } catch (_) {
      // The voice UI will retain its contextual permission error.
    } finally {
      await recorder.dispose();
    }

    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }
    } catch (_) {
      // Maps can still open without the current-location layer.
    }
  }
}

class NovaPermissionBootstrap extends StatefulWidget {
  const NovaPermissionBootstrap({super.key, required this.child});

  final Widget child;

  @override
  State<NovaPermissionBootstrap> createState() =>
      _NovaPermissionBootstrapState();
}

class _NovaPermissionBootstrapState extends State<NovaPermissionBootstrap> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(NovaInitialPermissionService.requestForFirstUse());
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
