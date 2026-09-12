import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_app/shared/widgets/ohmy_snack_bar.dart';
import 'package:flutter_app/shared/widgets/wau_loading_indicator.dart';

import '../config/travel_preference_options.dart';
import '../services/traveler_profile_service.dart';

class TravelPreferencesScreen extends StatefulWidget {
  const TravelPreferencesScreen({
    super.key,
    required this.onSaved,
    this.initialSelections = const [],
    this.isEditing = false,
  });

  final ValueChanged<List<String>> onSaved;
  final List<String> initialSelections;
  final bool isEditing;

  @override
  State<TravelPreferencesScreen> createState() =>
      _TravelPreferencesScreenState();
}

class _TravelPreferencesScreenState extends State<TravelPreferencesScreen> {
  static const _blue = Color(0xFF2865C7);
  static const _ink = Color(0xFF17345F);

  final _service = TravelerProfileService();
  late final Set<String> _selected;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialSelections
        .where(culturalTravelPreferenceOptions.contains)
        .toSet();
  }

  Future<void> _save() async {
    if (_selected.length < 3) {
      _showMessage('Please select at least 3 interests.', isError: true);
      return;
    }

    setState(() => _isSaving = true);
    try {
      final saved = await _service.saveFavoriteCategories(_selected.toList());
      if (!mounted) return;
      widget.onSaved(saved.favoriteCategories);
    } on TravelerProfileFailure catch (error) {
      _showMessage(error.message, isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      OhMySnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFBF3),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 64,
        leadingWidth: 68,
        leading: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Material(
            color: const Color(0xF7FFFFFF),
            elevation: 3,
            shadowColor: const Color(0x33000000),
            shape: const CircleBorder(
              side: BorderSide(color: Color(0xFFD4E0F5)),
            ),
            child: IconButton(
              tooltip: 'Back',
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back, color: _blue),
            ),
          ),
        ),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          ClipRect(
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 2, sigmaY: 2),
              child: Transform.scale(
                scale: 1.02,
                child: Image.asset(
                  'assets/images/user_management/preference_bg.png',
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
          const ColoredBox(color: Color(0x18FFFFFF)),
          const Positioned(
            top: 54,
            left: -24,
            right: -24,
            height: 290,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    radius: 0.78,
                    colors: [
                      Color(0xF2FFFCF5),
                      Color(0xCFFFFFFA),
                      Color(0x00FFFFFF),
                    ],
                    stops: [0, 0.58, 1],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: ListView(
              primary: false,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(18, 24, 18, 30),
              children: [
                Center(
                  child: Container(
                    width: 78,
                    height: 78,
                    decoration: const BoxDecoration(
                      color: Color(0xFFDCE8FF),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.auto_awesome,
                      color: _blue,
                      size: 38,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'PERSONALISE YOUR JOURNEY',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _blue,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                    shadows: [
                      Shadow(color: Colors.white, blurRadius: 8),
                      Shadow(color: Colors.white, blurRadius: 8),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'What are you into?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _ink,
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'serif',
                    shadows: [
                      Shadow(color: Colors.white, blurRadius: 10),
                      Shadow(color: Colors.white, blurRadius: 10),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
                  decoration: BoxDecoration(
                    color: const Color(0xF8FFFCF7),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: const Color(0x55D5B98A)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x18000000),
                        blurRadius: 14,
                        offset: Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Pick at least 3 interests',
                              style: TextStyle(
                                color: _ink,
                                fontSize: 19,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Text(
                            '${_selected.length} selected',
                            style: const TextStyle(
                              color: _blue,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      const Text(
                        'We’ll use these to suggest nearby places, activities and trip ideas that feel relevant to you.',
                        style: TextStyle(
                          color: Color(0xFF60708D),
                          fontSize: 12,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 16),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final width = (constraints.maxWidth - 10) / 2;
                          return Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: culturalTravelPreferenceOptions
                                .map(
                                  (interest) =>
                                      _buildInterestChoice(interest, width),
                                )
                                .toList(),
                          );
                        },
                      ),
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 11,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F2FF),
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.info_outline, color: _blue, size: 20),
                            SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                'You can update these anytime in Profile → Edit profile.',
                                style: TextStyle(
                                  color: Color(0xFF576B8F),
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 50,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _blue,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(25),
                      ),
                    ),
                    onPressed: _isSaving ? null : _save,
                    child: _isSaving
                        ? const SizedBox.square(
                            dimension: 22,
                            child: WauLoadingIndicator(size: 22),
                          )
                        : Text(
                            widget.isEditing ? 'Save preferences' : 'Continue',
                          ),
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xEFFFFFFF),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Text(
                    'Your interests improve recommendations and are not shown publicly.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _ink,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInterestChoice(String interest, double width) {
    final selected = _selected.contains(interest);
    return SizedBox(
      width: width,
      height: 48,
      child: Material(
        color: selected ? _blue : const Color(0xF8FFFFFF),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
          side: BorderSide(color: selected ? _blue : const Color(0xFFBFD2F2)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => setState(() {
            selected ? _selected.remove(interest) : _selected.add(interest);
          }),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (selected) ...[
                  const Icon(Icons.check, color: Colors.white, size: 16),
                  const SizedBox(width: 5),
                ],
                Flexible(
                  child: Text(
                    interest,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? Colors.white : _ink,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
