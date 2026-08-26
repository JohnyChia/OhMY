import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'rich_cards.dart';

class ChatBubble extends StatelessWidget {
  final Map<String, dynamic> message;
  final Map<String, dynamic>? tripState;

  const ChatBubble({
    Key? key,
    required this.message,
    this.tripState,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    bool isUser = message['role'] == 'user';
    
    // Attempt to parse tool_result if it exists (for rich cards)
    Widget? richCard;
    if (message['tool_result'] != null && !isUser) {
      if (message['intent']?['name'] == 'create_itinerary' || message['intent']?['name'] == 'modify_trip') {
        richCard = RichCards.buildItineraryCard(message['tool_result'], tripState);
      } else if (message['intent']?['name'] == 'recommendation') {
        richCard = RichCards.buildRecommendationCard(message['tool_result']);
      }
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12.0),
      child: Column(
        crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
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
                bottomLeft: isUser ? const Radius.circular(16) : const Radius.circular(4),
                bottomRight: isUser ? const Radius.circular(4) : const Radius.circular(16),
              ),
              boxShadow: isUser
                  ? []
                  : [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      )
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
                
                // Rich Card parsing (if any)
                if (richCard != null) ...[
                  const SizedBox(height: 16),
                  richCard,
                ],
              ],
            ),
          ),
          
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
          ]
        ],
      ),
    );
  }
}
