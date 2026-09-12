import 'package:flutter/material.dart';

class CommunityStatusCard extends StatelessWidget {
  const CommunityStatusCard({
    super.key,
    required this.title,
    required this.message,
    this.details = const <String>[],
    this.isError = true,
  });

  final String title;
  final String message;
  final List<String> details;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final background = isError
        ? colors.errorContainer
        : colors.surfaceContainerHighest;
    final foreground = isError
        ? colors.onErrorContainer
        : colors.onSurfaceVariant;

    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isError
                ? colors.error.withValues(alpha: 0.35)
                : colors.outlineVariant,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isError ? Icons.cancel_rounded : Icons.cloud_off_outlined,
              color: foreground,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(message, style: TextStyle(color: foreground)),
                  for (final detail in details) ...[
                    const SizedBox(height: 4),
                    Text(detail, style: TextStyle(color: foreground)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
