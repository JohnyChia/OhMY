import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../utils/auth_validators.dart';
import '../widgets/password_field.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  final _authService = AuthService();
  bool _isSaving = false;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      await _authService.changePassword(
        currentPassword: _currentController.text,
        newPassword: _newController.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
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
      appBar: AppBar(title: const Text('Change password'), centerTitle: true),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
            children: [
              const Icon(
                Icons.lock_reset_outlined,
                size: 64,
                color: Color(0xFF2E60C4),
              ),
              const SizedBox(height: 18),
              const Text(
                'Protect your account',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 24, color: Color(0xFF17243D)),
              ),
              const SizedBox(height: 8),
              const Text(
                'Use 8–16 letters and numbers. The new password must include both and cannot match the old password, even with different letter casing.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF62708A), fontSize: 12),
              ),
              const SizedBox(height: 28),
              PasswordField(
                controller: _currentController,
                label: 'Current password',
                validator: (value) => AuthValidators.requiredField(
                  value,
                  'your current password',
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 14),
              PasswordField(
                controller: _newController,
                label: 'New password',
                validator: (value) => AuthValidators.newPassword(
                  value,
                  oldPassword: _currentController.text,
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 14),
              PasswordField(
                controller: _confirmController,
                label: 'Confirm new password',
                validator: (value) {
                  final error = AuthValidators.password(value);
                  if (error != null) return error;
                  if (value != _newController.text) {
                    return 'Both new password fields must match.';
                  }
                  return null;
                },
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _isSaving ? null : _changePassword(),
              ),
              const SizedBox(height: 22),
              ElevatedButton(
                onPressed: _isSaving ? null : _changePassword,
                child: _isSaving
                    ? const SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Change password'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
