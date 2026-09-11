import 'package:flutter/material.dart';
import 'package:flutter_app/shared/widgets/wau_loading_indicator.dart';
import 'package:flutter_app/shared/widgets/ohmy_snack_bar.dart';

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
      backgroundColor: const Color(0xFFF7FAFE),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 26, 24, 25),
              color: const Color(0xFF94B5FA),
              child: Column(
                children: [
                  if (widget.isEditing)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                      ),
                    ),
                  Container(
                    width: 82,
                    height: 82,
                    decoration: const BoxDecoration(
                      color: Color(0xFFD8E5FF),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.auto_awesome,
                      color: Color(0xFF2E61C4),
                      size: 38,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'PERSONALISE YOUR JOURNEY',
                    style: TextStyle(color: Colors.white, fontSize: 11),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'What are you into?',
                    style: TextStyle(color: Colors.white, fontSize: 26),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Pick at least 3 interests',
                          style: TextStyle(
                            color: Color(0xFF17243D),
                            fontSize: 19,
                          ),
                        ),
                      ),
                      Text(
                        '${_selected.length} selected',
                        style: const TextStyle(
                          color: Color(0xFF2E61C4),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'We’ll use these to suggest nearby places, activities and '
                    'trip ideas that feel relevant to you.',
                    style: TextStyle(color: Color(0xFF576B8F), fontSize: 13),
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 10,
                    runSpacing: 12,
                    children: culturalTravelPreferenceOptions
                        .map(_buildInterestChip)
                        .toList(),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F2FF),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Color(0xFF2E61C4),
                          size: 22,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'You can update these anytime in Profile → Edit profile.',
                            style: TextStyle(
                              color: Color(0xFF576B8F),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  ElevatedButton(
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
                  const SizedBox(height: 12),
                  const Text(
                    'Your interests improve recommendations and are not shown publicly.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF576B8F), fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInterestChip(String interest) {
    final selected = _selected.contains(interest);
    return FilterChip(
      label: Text(selected ? '✓  $interest' : interest),
      selected: selected,
      showCheckmark: false,
      selectedColor: const Color(0xFF2E61C4),
      backgroundColor: Colors.white,
      side: BorderSide(
        color: selected ? const Color(0xFF2E61C4) : const Color(0xFFC4D6F5),
      ),
      labelStyle: TextStyle(
        color: selected ? Colors.white : const Color(0xFF17243D),
        fontSize: 13,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onSelected: (_) {
        setState(() {
          selected ? _selected.remove(interest) : _selected.add(interest);
        });
      },
    );
  }
}
