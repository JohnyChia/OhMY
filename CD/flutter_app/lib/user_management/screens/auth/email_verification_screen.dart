import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../utils/auth_validators.dart';
import '../../widgets/auth_page_layout.dart';
import '../../widgets/otp_code_field.dart';

class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({required this.email, super.key});

  final String email;

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  final _otpController = TextEditingController();
  final _authService = AuthService();
  bool _isLoading = false;
  Timer? _resendTimer;
  int _resendSeconds = 60;

  @override
  void initState() {
    super.initState();
    _startResendCooldown();
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _otpController.dispose();
    super.dispose();
  }

  void _startResendCooldown() {
    _resendTimer?.cancel();
    setState(() => _resendSeconds = 60);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_resendSeconds <= 1) {
        timer.cancel();
        setState(() => _resendSeconds = 0);
      } else {
        setState(() => _resendSeconds--);
      }
    });
  }

  Future<void> _verify() async {
    final validationError = AuthValidators.otp(_otpController.text);
    if (validationError != null) {
      _showMessage(validationError, isError: true);
      return;
    }
    setState(() => _isLoading = true);
    try {
      await _authService.verifyRegistrationOtp(
        email: widget.email,
        otp: _otpController.text,
      );
      // Verifying an email creates a Supabase session. This project requires
      // the traveller to sign in with their new credentials after registration.
      await _authService.logout();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Account created. Please log in to continue.'),
        ),
      );
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on AuthFailure catch (error) {
      _showMessage(error.message, isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resend() async {
    setState(() => _isLoading = true);
    try {
      await _authService.resendRegistrationOtp(widget.email);
      _startResendCooldown();
      _showMessage('A new verification code has been sent.');
    } on AuthFailure catch (error) {
      _showMessage(error.message, isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuthPageLayout(
      title: 'Enter verification code',
      subtitle: 'We sent a verification code to\n${widget.email}',
      showBackButton: true,
      illustrationAsset: 'assets/images/auth/otp_lock.svg',
      glowAsset: 'assets/images/auth/otp_glow.svg',
      topSpacing: 22,
      titleSpacing: 32,
      formSpacing: 44,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OtpCodeField(
            controller: _otpController,
            onSubmitted: _isLoading ? null : _verify,
          ),
          const SizedBox(height: 18),
          const Text(
            'Enter the 6-digit code from your email',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF62708A), fontSize: 12),
          ),
          const SizedBox(height: 18),
          ElevatedButton(
            onPressed: _isLoading ? null : _verify,
            child: _isLoading
                ? const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Verify code'),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Didn’t receive the code?',
                style: TextStyle(color: Color(0xFF62708A), fontSize: 13),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.only(left: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: _isLoading || _resendSeconds > 0 ? null : _resend,
                child: Text(
                  _resendSeconds > 0
                      ? 'Resend in ${_resendSeconds}s'
                      : 'Resend OTP',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
