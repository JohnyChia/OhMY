import 'package:flutter/material.dart';

class CommunityGuidelinesScreen extends StatelessWidget {
  const CommunityGuidelinesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: const Text('Guidelines & Terms'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          children: const [
            Text(
              'ohMY Travel Community Guidelines',
              style: TextStyle(
                color: Color(0xFF17243D),
                fontSize: 26,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'These guidelines and terms help keep travel discussions safe, useful and respectful.',
              style: TextStyle(color: Color(0xFF62708A), height: 1.5),
            ),
            SizedBox(height: 24),
            _GuidelineSection(
              title: '1. Be respectful',
              body:
                  'Do not post harassment, hate speech, threats, bullying or discriminatory content. Respect other travellers and local communities.',
            ),
            _GuidelineSection(
              title: '2. Share responsible travel information',
              body:
                  'Post information you believe is accurate. Do not encourage dangerous, illegal or harmful activities. Weather, traffic and route information can change, so check official advice before travelling.',
            ),
            _GuidelineSection(
              title: '3. Protect privacy',
              body:
                  'Do not publish passwords, identity-document details, private addresses, phone numbers or another person’s personal information without permission.',
            ),
            _GuidelineSection(
              title: '4. No scams or harmful content',
              body:
                  'Do not post scams, spam, malware, impersonation, misleading promotions or content that violates applicable laws.',
            ),
            _GuidelineSection(
              title: '5. Your account and content',
              body:
                  'You are responsible for keeping your account secure and for content posted through it. Only upload content you have permission to share.',
            ),
            _GuidelineSection(
              title: '6. Moderation',
              body:
                  'Content that breaks these rules may be restricted or removed. Repeated or serious violations may result in account restrictions.',
            ),
            Divider(height: 40),
            Text(
              'Terms and Conditions',
              style: TextStyle(
                color: Color(0xFF17243D),
                fontSize: 22,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 12),
            _GuidelineSection(
              title: 'Using the application',
              body:
                  'By creating an account, you agree to use ohMY Travel lawfully and follow these Community Guidelines. The application provides travel-planning information and does not guarantee that weather, traffic, route or community information is complete or current.',
            ),
            _GuidelineSection(
              title: 'Service changes',
              body:
                  'Features may be updated, interrupted or changed while the project is being developed. Important changes to these terms should be communicated before they take effect.',
            ),
            _GuidelineSection(
              title: 'Acceptance',
              body:
                  'Selecting the acceptance checkbox during registration confirms that you have read and agree to these Community Guidelines and Terms and Conditions.',
            ),
          ],
        ),
      ),
    );
  }
}

class _GuidelineSection extends StatelessWidget {
  const _GuidelineSection({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF17243D),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: const TextStyle(
              color: Color(0xFF53627B),
              fontSize: 14,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}
