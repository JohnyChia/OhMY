import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class AuthPageLayout extends StatelessWidget {
  const AuthPageLayout({
    required this.title,
    required this.subtitle,
    required this.child,
    this.showBackButton = false,
    this.backLabel = 'Back',
    this.illustrationAsset,
    this.glowAsset,
    this.glowOnRight = false,
    this.topSpacing = 56,
    this.titleSpacing = 34,
    this.formSpacing = 34,
    this.footerNote,
    super.key,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final bool showBackButton;
  final String backLabel;
  final String? illustrationAsset;
  final String? glowAsset;
  final bool glowOnRight;
  final double topSpacing;
  final double titleSpacing;
  final double formSpacing;
  final String? footerNote;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          if (glowAsset != null)
            Positioned(
              top: 22,
              left: glowOnRight ? null : -92,
              right: glowOnRight ? -86 : null,
              child: IgnorePointer(
                child: SvgPicture.asset(glowAsset!, width: 270, height: 270),
              ),
            ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Center(
                    child: SizedBox(
                      width: 330,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (showBackButton)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: () =>
                                    Navigator.of(context).maybePop(),
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  foregroundColor: const Color(0xFF2E60C4),
                                ),
                                icon: const Icon(Icons.chevron_left, size: 18),
                                label: Text(backLabel),
                              ),
                            ),
                          SizedBox(height: topSpacing),
                          if (illustrationAsset != null) ...[
                            Center(
                              child: SvgPicture.asset(
                                illustrationAsset!,
                                width: 78,
                                height: 78,
                              ),
                            ),
                            SizedBox(height: titleSpacing),
                          ],
                          Text(
                            title,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Color(0xFF17243D),
                              fontSize: 30,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            subtitle,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Color(0xFF62708A),
                              fontSize: 13,
                              height: 1.5,
                            ),
                          ),
                          SizedBox(height: formSpacing),
                          child,
                          if (footerNote != null) ...[
                            const SizedBox(height: 130),
                            Text(
                              footerNote!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFF7A879B),
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
