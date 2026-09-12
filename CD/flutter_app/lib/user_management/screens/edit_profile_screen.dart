import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app/shared/widgets/wau_loading_indicator.dart';
import 'package:flutter_app/shared/widgets/ohmy_snack_bar.dart';
import 'package:image_picker/image_picker.dart';

import '../config/travel_preference_options.dart';
import '../models/app_user_profile.dart';
import '../services/auth_service.dart';
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
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();
  final _imagePicker = ImagePicker();
  late final TextEditingController _nameController;
  late final TextEditingController _bioController;
  late List<String> _preferences;
  bool _isSaving = false;
  bool _isUploadingPhoto = false;
  bool _preferencesChanged = false;
  bool _hasSavedChanges = false;
  String? _avatarUrl;
  String? _localAvatarPath;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.profile.fullName);
    _bioController = TextEditingController(text: widget.profile.bio);
    _preferences = widget.initialPreferences
        .where(culturalTravelPreferenceOptions.contains)
        .toList();
    _avatarUrl = widget.profile.avatarUrl;
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

  Future<void> _pickProfilePhoto() async {
    if (_isUploadingPhoto) return;
    final image = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
      requestFullMetadata: false,
    );
    if (image == null || !mounted) return;

    setState(() {
      _isUploadingPhoto = true;
      _localAvatarPath = image.path;
    });
    try {
      final extension = _extensionOf(image.path);
      final profile = await _authService.uploadProfilePhoto(
        bytes: await image.readAsBytes(),
        extension: extension,
        contentType: _contentTypeFor(extension),
      );
      if (!mounted) return;
      setState(() {
        _avatarUrl = profile.avatarUrl;
        _hasSavedChanges = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const OhMySnackBar(content: Text('Profile photo updated successfully')),
      );
    } on AuthFailure catch (error) {
      if (!mounted) return;
      setState(() => _localAvatarPath = null);
      ScaffoldMessenger.of(context).showSnackBar(
        OhMySnackBar(content: Text(error.message), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isUploadingPhoto = false);
    }
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
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      await _authService.updateProfile(
        fullName: _nameController.text,
        bio: _bioController.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const OhMySnackBar(content: Text('Profile updated successfully')),
      );
      setState(() => _hasSavedChanges = true);
    } on AuthFailure catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        OhMySnackBar(content: Text(error.message), backgroundColor: Colors.red),
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
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).pop(_hasSavedChanges),
          icon: const Icon(Icons.arrow_back),
        ),
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
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    _EditableAvatar(
                      localPath: _localAvatarPath,
                      networkUrl: _avatarUrl,
                      initial: _initial,
                    ),
                    Positioned(
                      right: -5,
                      bottom: -5,
                      child: IconButton.filled(
                        tooltip: 'Upload profile photo',
                        onPressed: _isUploadingPhoto ? null : _pickProfilePhoto,
                        icon: _isUploadingPhoto
                            ? const SizedBox.square(
                                dimension: 18,
                                child: WauLoadingIndicator(size: 18),
                              )
                            : const Icon(Icons.photo_camera_outlined, size: 20),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: _isUploadingPhoto ? null : _pickProfilePhoto,
                icon: const Icon(Icons.upload_outlined, size: 18),
                label: const Text('Upload profile photo'),
              ),
              const Text(
                'JPG, PNG or WebP • Maximum 5 MB',
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
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: _openChangePassword,
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: const Color(0xFFC5D6F5)),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.lock_outline, color: Color(0xFF2E60C4)),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'CHANGE PASSWORD',
                              style: TextStyle(
                                color: Color(0xFF2E61C4),
                                fontSize: 10,
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
                      Icon(Icons.chevron_right, color: Color(0xFF536681)),
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
                        child: WauLoadingIndicator(size: 22),
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

  String _extensionOf(String path) {
    final extension = path.split('.').last.toLowerCase();
    return extension == 'jpeg' ? 'jpg' : extension;
  }

  String _contentTypeFor(String extension) => switch (extension) {
    'png' => 'image/png',
    'webp' => 'image/webp',
    _ => 'image/jpeg',
  };
}

class _EditableAvatar extends StatelessWidget {
  const _EditableAvatar({
    required this.localPath,
    required this.networkUrl,
    required this.initial,
  });

  final String? localPath;
  final String? networkUrl;
  final String initial;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      color: const Color(0xFFD9E8FF),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          color: Color(0xFF2E60C4),
          fontSize: 28,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    Widget image = fallback;
    if (localPath != null) {
      image = Image.file(
        File(localPath!),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      );
    } else if (networkUrl != null && networkUrl!.isNotEmpty) {
      image = Image.network(
        networkUrl!,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      );
    }
    return ClipOval(child: SizedBox.square(dimension: 88, child: image));
  }
}
