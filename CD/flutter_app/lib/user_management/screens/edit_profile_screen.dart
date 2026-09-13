import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_app/shared/widgets/wau_loading_indicator.dart';
import 'package:flutter_app/shared/widgets/ohmy_snack_bar.dart';

import '../config/travel_preference_options.dart';
import '../models/app_user_profile.dart';
import '../services/auth_service.dart';
import '../services/traveler_profile_service.dart';
import '../utils/auth_validators.dart';
import 'change_password_screen.dart';
import 'travel_preferences_screen.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({
    super.key,
    required this.profile,
    required this.initialPreferences,
  });

  final AppUserProfile profile;
  final List<String> initialPreferences;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  static const _blue = Color(0xFF28599F);
  static const _ink = Color(0xFF17345F);

  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();
  final _travelerProfileService = TravelerProfileService();
  late final TextEditingController _nameController;
  late List<String> _preferences;
  bool _isSaving = false;
  bool _preferencesChanged = false;
  bool _hasSavedChanges = false;
  bool _allowPop = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.profile.fullName);
    _preferences = widget.initialPreferences
        .where(culturalTravelPreferenceOptions.contains)
        .toList();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _editPreferences() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => TravelPreferencesScreen(
          initialSelections: _preferences,
          isEditing: true,
          onSaved: (savedPreferences) {
            if (!mounted) return;
            setState(() {
              _preferences = List.of(savedPreferences);
              _preferencesChanged = true;
            });
          },
        ),
      ),
    );
  }

  Future<void> _openChangePassword() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const ChangePasswordScreen()),
    );
    if (changed == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const OhMySnackBar(content: Text('Password changed successfully')),
      );
    }
  }

  Future<void> _save() async {
    if (_isSaving) return;
    if (!_formKey.currentState!.validate()) return;
    if (_preferences.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const OhMySnackBar(
          content: Text('Please select at least 3 interests.'),
        ),
      );
      return;
    }
    setState(() => _isSaving = true);
    try {
      await _authService.updateProfile(
        fullName: _nameController.text,
        bio: widget.profile.bio,
      );
      if (_preferencesChanged) {
        await _travelerProfileService.saveFavoriteCategories(_preferences);
        _preferencesChanged = false;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const OhMySnackBar(content: Text('Profile updated successfully')),
      );
      setState(() => _hasSavedChanges = true);
    } on TravelerProfileFailure catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        OhMySnackBar(content: Text(error.message), backgroundColor: Colors.red),
      );
    } on AuthFailure catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        OhMySnackBar(content: Text(error.message), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _closeScreen() {
    if (_allowPop) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(_hasSavedChanges);
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<bool>(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _allowPop) return;
        _closeScreen();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFFFFBF5),
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            tooltip: 'Back',
            onPressed: _closeScreen,
            icon: const Icon(Icons.arrow_back),
          ),
          title: const Text(
            'Edit profile',
            style: TextStyle(
              color: Color(0xFF123A78),
              fontWeight: FontWeight.w700,
            ),
          ),
          centerTitle: false,
        ),
        body: Stack(
          fit: StackFit.expand,
          children: [
            ClipRect(
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 3.5, sigmaY: 3.5),
                child: Transform.scale(
                  scale: 1.02,
                  child: Image.asset(
                    'assets/images/user_management/profile_bg.png',
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
            const ColoredBox(color: Color(0x12FFFDF8)),
            SafeArea(
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
                  children: [
                    Center(child: _EditableAvatar(initial: _initial)),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _nameController,
                      onChanged: (_) => setState(() {}),
                      inputFormatters: AuthValidators.usernameInputFormatters,
                      validator: AuthValidators.username,
                      textCapitalization: TextCapitalization.none,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'USERNAME',
                        labelStyle: TextStyle(
                          color: _blue,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                        floatingLabelBehavior: FloatingLabelBehavior.always,
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: _blue),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: _blue, width: 2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: _editPreferences,
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xEFFFFFFF),
                          border: Border.all(color: const Color(0xFFBFD3F2)),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const _EditProfileIcon(Icons.explore_outlined),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          'TRAVEL PREFERENCES',
                                          style: TextStyle(
                                            color: _blue,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: .7,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        'Change',
                                        style: TextStyle(
                                          color: _blue,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      Icon(
                                        Icons.chevron_right,
                                        color: _blue,
                                        size: 19,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 5),
                                  const Text(
                                    'Used to personalise nearby places and trip ideas',
                                    style: TextStyle(
                                      color: Color(0xFF617496),
                                      fontSize: 11,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEAF2FF),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      _preferences.isEmpty
                                          ? 'No interests selected'
                                          : '${_preferences.take(3).join(' • ')}${_preferences.length > 3 ? '  +${_preferences.length - 3} more' : ''}',
                                      style: const TextStyle(
                                        color: _ink,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: _openChangePassword,
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xEFFFFFFF),
                          border: Border.all(color: const Color(0xFFBFD3F2)),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const Row(
                          children: [
                            _EditProfileIcon(Icons.lock_outline),
                            SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'CHANGE PASSWORD',
                                    style: TextStyle(
                                      color: _blue,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: .7,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'Confirm your old password and choose a new one',
                                    style: TextStyle(
                                      color: Color(0xFF576B8F),
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right, color: _blue),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xEFFFFFFF),
                        border: Border.all(color: const Color(0xFFBFD3F2)),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const _EditProfileIcon(Icons.verified_user_outlined),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'IDENTITY STATUS — READ ONLY',
                                  style: TextStyle(
                                    color: _blue,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: .5,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  widget.profile.isVerified
                                      ? 'Verified Traveller'
                                      : 'Unverified Traveller',
                                  style: const TextStyle(
                                    color: _ink,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'This can only change after the future identity verification flow.',
                                  style: TextStyle(
                                    color: Color(0xFF7A879B),
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _blue,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: const Color(0xFF9AAAC4),
                        minimumSize: const Size.fromHeight(52),
                        elevation: 3,
                        shape: const StadiumBorder(),
                        textStyle: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'sans-serif',
                        ),
                      ),
                      onPressed: _isSaving ? null : _save,
                      child: _isSaving
                          ? const SizedBox.square(
                              dimension: 22,
                              child: WauLoadingIndicator(size: 22),
                            )
                          : const Text('Save Changes'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _initial {
    final name = _nameController.text.trim();
    if (name.isNotEmpty) return name[0].toUpperCase();
    return widget.profile.email.isNotEmpty
        ? widget.profile.email[0].toUpperCase()
        : '?';
  }
}

class _EditProfileIcon extends StatelessWidget {
  const _EditProfileIcon(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: const BoxDecoration(
        color: Color(0xFFE8F1FF),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: Color(0xFF28599F), size: 24),
    );
  }
}

class _EditableAvatar extends StatelessWidget {
  const _EditableAvatar({required this.initial});

  final String initial;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 54,
      backgroundColor: const Color(0xFFD9E8FF),
      child: Text(
        initial,
        style: const TextStyle(
          color: Color(0xFF2E60C4),
          fontSize: 28,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
