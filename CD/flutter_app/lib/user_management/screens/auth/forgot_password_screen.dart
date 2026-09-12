import 'package:flutter/material.dart';
import 'package:flutter_app/shared/widgets/wau_loading_indicator.dart';
import 'package:flutter_app/shared/widgets/ohmy_snack_bar.dart';

import '../../services/auth_service.dart';
import '../../utils/auth_validators.dart';
import '../../widgets/auth_page_layout.dart';
import 'recovery_otp_screen.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _authService = AuthService();
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (_isLoading) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final email = _emailController.text.trim();
      await _authService.sendPasswordRecoveryOtp(email);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => RecoveryOtpScreen(email: email),
        ),
      );
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
      title: 'Forgot password?',
      subtitle:
          'Enter the email linked to your account.\nWe’ll send you a one-time verification code.',
      showBackButton: true,
      illustrationAsset: 'assets/images/auth/email_recovery.svg',
      glowAsset: 'assets/images/auth/recovery_glow.svg',
      glowOnRight: true,
      topSpacing: 52,
      titleSpacing: 32,
      formSpacing: 44,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              enabled: !_isLoading,
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              inputFormatters: AuthValidators.emailInputFormatters,
              textInputAction: TextInputAction.done,
              textCapitalization: TextCapitalization.none,
              autocorrect: false,
              autofillHints: const [AutofillHints.email],
              validator: AuthValidators.email,
              decoration: const InputDecoration(
                labelText: 'EMAIL',
                hintText: 'name@example.com',
                floatingLabelBehavior: FloatingLabelBehavior.always,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isLoading ? null : _sendCode,
              child: _isLoading
                  ? const SizedBox.square(
                      dimension: 22,
                      child: WauLoadingIndicator(size: 22),
                    )
                  : const Text('Send OTP'),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Remembered your password?',
                  style: TextStyle(color: Color(0xFF62708A), fontSize: 13),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.only(left: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Sign in'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
