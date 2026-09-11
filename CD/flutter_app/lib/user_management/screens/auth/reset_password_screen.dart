import 'package:flutter/material.dart';
import 'package:flutter_app/shared/widgets/wau_loading_indicator.dart';
import 'package:flutter_app/shared/widgets/ohmy_snack_bar.dart';

import '../../services/auth_service.dart';
import '../../utils/auth_validators.dart';
import '../../widgets/auth_page_layout.dart';
import '../../widgets/password_field.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _authService = AuthService();
  bool _isLoading = false;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _resetPassword() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      await _authService.updatePassword(_passwordController.text);
      await _authService.logout();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const OhMySnackBar(
          content: Text('Password reset successfully. Please sign in.'),
        ),
      );
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on AuthFailure catch (error) {
      _showMessage(error.message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      OhMySnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuthPageLayout(
      title: 'Create new password',
      subtitle:
          'Use 8–16 letters and numbers. Your new password cannot be the same as your previous password.',
      glowAsset: 'assets/images/auth/register_glow.svg',
      topSpacing: 170,
      formSpacing: 46,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PasswordField(
              controller: _passwordController,
              label: 'New password',
              validator: AuthValidators.password,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 11),
            PasswordField(
              controller: _confirmPasswordController,
              label: 'Confirm new password',
              validator: (value) {
                final passwordError = AuthValidators.password(value);
                if (passwordError != null) return passwordError;
                if (value != _passwordController.text) {
                  return 'Both password fields must match.';
                }
                return null;
              },
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: _isLoading ? null : _resetPassword,
              child: _isLoading
                  ? const SizedBox.square(
                      dimension: 22,
                      child: WauLoadingIndicator(size: 22),
                    )
                  : const Text('Reset password'),
            ),
          ],
        ),
      ),
    );
  }
}
