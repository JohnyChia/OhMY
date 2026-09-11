import 'package:flutter/material.dart';

/// A consistently short application message that never lingers over content.
class OhMySnackBar extends SnackBar {
  const OhMySnackBar({
    super.key,
    required super.content,
    super.backgroundColor,
    super.behavior,
    super.action,
    super.showCloseIcon,
    super.closeIconColor,
    super.shape,
    super.margin,
    super.padding,
    super.width,
    super.elevation,
    super.dismissDirection,
    super.clipBehavior,
    super.hitTestBehavior,
    super.actionOverflowThreshold,
    super.duration = const Duration(seconds: 3),
  });
}
