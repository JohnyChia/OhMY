import 'dart:io';
import 'dart:ui' as ui;

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
  static const _blue = Color(0xFF28599F);
  static const _ink = Color(0xFF17345F);

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
  bool _allowPop = false;
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
          toolbarHeight: 68,
          leadingWidth: 68,
          leading: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            child: Material(
              color: const Color(0xF7FFFFFF),
              elevation: 3,
              shadowColor: const Color(0x33000000),
              shape: const CircleBorder(
                side: BorderSide(color: Color(0xFFBFD3F2)),
              ),
              child: IconButton(
                tooltip: 'Back',
                onPressed: _closeScreen,
                icon: const Icon(Icons.arrow_back, color: _blue, size: 25),
              ),
            ),
          ),
          title: const Text(
            'Edit profile',
            style: TextStyle(
              color: _ink,
              fontSize: 28,
              fontWeight: FontWeight.w800,
              fontFamily: 'serif',
            ),
          ),
          centerTitle: true,
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
                  padding: const EdgeInsets.fromLTRB(18, 68, 18, 32),
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
                            right: -7,
                            bottom: -4,
                            child: IconButton.filled(
                              style: IconButton.styleFrom(
                                backgroundColor: _blue,
                                foregroundColor: Colors.white,
                                disabledBackgroundColor: const Color(
                                  0xFF9AAAC4,
                                ),
                              ),
                              tooltip: 'Upload profile photo',
                              onPressed: _isUploadingPhoto
                                  ? null
                                  : _pickProfilePhoto,
                              icon: _isUploadingPhoto
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: WauLoadingIndicator(size: 18),
                                    )
                                  : const Icon(
                                      Icons.photo_camera_outlined,
                                      size: 20,
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: _blue,
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'serif',
                        ),
                      ),
                      onPressed: _isUploadingPhoto ? null : _pickProfilePhoto,
                      icon: const Icon(Icons.upload_outlined, size: 18),
                      label: const Text('Upload profile photo'),
                    ),
                    const Text(
                      'JPG, PNG or WebP • Maximum 5 MB',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF71809A), fontSize: 11),
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _nameController,
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
                    TextFormField(
                      controller: _bioController,
                      maxLength: 160,
                      minLines: 2,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'BIO',
                        labelStyle: TextStyle(
                          color: _blue,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                        hintText:
                            'Tell other travellers a little about yourself',
                        hintStyle: TextStyle(color: Color(0xFF64789A)),
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
                          fontFamily: 'serif',
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
    return Container(
      width: 108,
      height: 108,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: const Color(0xEFFFFFFF),
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFC9DBF6), width: 2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: ClipOval(child: image),
    );
  }
}
