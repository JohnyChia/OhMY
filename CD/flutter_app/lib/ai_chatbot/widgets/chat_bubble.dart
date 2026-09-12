import 'dart:io' show File;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'rich_cards.dart';

class ChatBubble extends StatelessWidget {
  final Map<String, dynamic> message;
  final Map<String, dynamic>? tripState;
  final void Function(
    Map<String, dynamic> recommendation,
    Map<String, dynamic> toolResult,
  )?
  onRecommendationSelected;

  const ChatBubble({
    super.key,
    required this.message,
    this.tripState,
    this.onRecommendationSelected,
  });

  @override
  Widget build(BuildContext context) {
    bool isUser = message['role'] == 'user';
    final attachment = message['attachment'];
    final attachmentPath = attachment is Map
        ? attachment['path']?.toString()
        : null;
    final attachmentName = attachment is Map
        ? attachment['name']?.toString()
        : null;
    final isImageAttachment =
        attachment is Map && attachment['type'] == 'image';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12.0),
      child: Column(
        crossAxisAlignment: isUser
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          // Name Label
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
            child: Text(
              isUser ? 'You' : 'Nova',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: Colors.grey.shade500,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),

          // Bubble
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isUser ? const Color(0xFF4285F4) : Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: isUser
                    ? const Radius.circular(16)
                    : const Radius.circular(4),
                bottomRight: isUser
                    ? const Radius.circular(4)
                    : const Radius.circular(16),
              ),
              boxShadow: isUser
                  ? []
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message['text'] ?? '',
                  style: GoogleFonts.inter(
                    color: isUser ? Colors.white : const Color(0xFF1F2937),
                    fontSize: 15,
                    height: 1.5,
                  ),
                ),
                if (message['voiceTranscript'] == true) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Voice transcript',
                    style: GoogleFonts.inter(
                      color: Colors.white.withValues(alpha: 0.78),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if (attachmentName != null) ...[
                  const SizedBox(height: 10),
                  if (isImageAttachment && !kIsWeb && attachmentPath != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(
                        File(attachmentPath),
                        height: 180,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            _attachmentLabel(attachmentName),
                      ),
                    )
                  else
                    _attachmentLabel(attachmentName),
                ],
              ],
            ),
          ),

          if (!isUser &&
              message['tool_result'] is Map &&
              (message['tool_result']['recommendations'] as List?)
                      ?.isNotEmpty ==
                  true) ...[
            const SizedBox(height: 10),
            RichCards.buildRecommendationCard(
              message['tool_result'],
              onSelected: onRecommendationSelected == null
                  ? null
                  : (recommendation) => onRecommendationSelected!(
                      recommendation,
                      Map<String, dynamic>.from(message['tool_result'] as Map),
                    ),
            ),
          ],

          // Detected Language Tag
          if (!isUser && message['language'] != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'DETECTED ${message['language'].toString().toUpperCase()}',
                  style: GoogleFonts.inter(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade500,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _attachmentLabel(String name) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.attach_file_rounded, size: 16),
        const SizedBox(width: 6),
        Flexible(child: Text(name, overflow: TextOverflow.ellipsis)),
      ],
    ),
  );
}
