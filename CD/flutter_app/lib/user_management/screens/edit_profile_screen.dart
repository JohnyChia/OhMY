import 'package:flutter/material.dart';

import '../models/app_user_profile.dart';
import '../services/auth_service.dart';
import '../utils/auth_validators.dart';
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
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();
  late final TextEditingController _nameController;
  late final TextEditingController _bioController;
  late List<String> _preferences;
  bool _isSaving = false;
  bool _preferencesChanged = false;
  bool _hasSavedChanges = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.profile.fullName);
    _bioController = TextEditingController(text: widget.profile.bio);
    _preferences = List.of(widget.initialPreferences);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _editPreferences() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => TravelPreferencesScreen(
          initialSelections: _preferences,
          isEditing: true,
          onSaved: (savedPreferences) {
            setState(() {
              _preferences = List.of(savedPreferences);
              _preferencesChanged = true;
            });
            Navigator.of(context).pop();
          },
        ),
      ),
    );
    if (!_preferencesChanged) return;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      await _authService.updateProfile(
        fullName: _nameController.text,
        bio: _bioController.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully')),
      );
      setState(() => _hasSavedChanges = true);
    } on AuthFailure catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: TextButton(
          onPressed: () => Navigator.of(context).pop(_hasSavedChanges),
          child: const Text('‹ Back'),
        ),
        leadingWidth: 82,
        title: const Text('Edit profile'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: [
              Center(
                child: CircleAvatar(
                  radius: 40,
                  backgroundColor: const Color(0xFFD9E8FF),
                  child: Text(
                    _initial,
                    style: const TextStyle(
                      color: Color(0xFF2E60C4),
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Profile photo upload will be connected with private storage later.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF71809A), fontSize: 11),
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _nameController,
                inputFormatters: AuthValidators.usernameInputFormatters,
                validator: AuthValidators.username,
                textCapitalization: TextCapitalization.none,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'USERNAME',
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _bioController,
                maxLength: 160,
                minLines: 2,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'BIO',
                  hintText: 'Tell other travellers a little about yourself',
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                ),
              ),
              const SizedBox(height: 12),
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: _editPreferences,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F7FE),
                    border: Border.all(color: const Color(0xFFC5D6F5)),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Expanded(
                            child: Text(
                              'TRAVEL PREFERENCES',
                              style: TextStyle(
                                color: Color(0xFF2E61C4),
                                fontSize: 10,
                              ),
                            ),
                          ),
                          Text(
                            'Change',
                            style: TextStyle(
                              color: Color(0xFF2E61C4),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      const Text(
                        'Used to personalise nearby places and trip ideas',
                        style: TextStyle(
                          color: Color(0xFF576B8F),
                          fontSize: 10,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _preferences.isEmpty
                            ? 'No interests selected'
                            : '${_preferences.take(3).join(' • ')}${_preferences.length > 3 ? '  +${_preferences.length - 3} more' : ''}',
                        style: const TextStyle(
                          color: Color(0xFF17243D),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F7FC),
                  border: Border.all(color: const Color(0xFFD3DCEA)),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '🔒  IDENTITY STATUS — READ ONLY',
                      style: TextStyle(color: Color(0xFF536681), fontSize: 10),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      widget.profile.isVerified
                          ? 'Verified Traveller'
                          : 'Unverified Traveller',
                      style: const TextStyle(
                        color: Color(0xFF17243D),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'This can only change after the future identity verification flow.',
                      style: TextStyle(color: Color(0xFF7A879B), fontSize: 10),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              ElevatedButton(
                onPressed: _isSaving ? null : _save,
                child: _isSaving
                    ? const SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save Changes'),
              ),
            ],
          ),
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
