import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../utils/auth_validators.dart';
import '../../widgets/auth_page_layout.dart';
import '../../widgets/password_field.dart';
import 'community_guidelines_screen.dart';
import 'email_verification_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _authService = AuthService();
  bool _acceptedGuidelines = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_acceptedGuidelines) {
      _showMessage('Please accept the Community Safety Guidelines.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final response = await _authService.register(
        fullName: _fullNameController.text,
        email: _emailController.text,
        password: _passwordController.text,
      );

      if (!mounted) return;
      if (response.session == null) {
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) =>
                EmailVerificationScreen(email: _emailController.text.trim()),
          ),
        );
      } else {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } on AuthFailure catch (error) {
      _showMessage(error.message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuthPageLayout(
      title: 'Create account',
      subtitle: 'Create your profile and start exploring',
      glowAsset: 'assets/images/auth/register_glow.svg',
      topSpacing: 78,
      formSpacing: 32,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _fullNameController,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.name],
              validator: AuthValidators.fullName,
              decoration: const InputDecoration(
                labelText: 'FULL NAME',
                hintText: 'Your full name',
                floatingLabelBehavior: FloatingLabelBehavior.always,
              ),
            ),
            const SizedBox(height: 11),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              validator: AuthValidators.email,
              decoration: const InputDecoration(
                labelText: 'EMAIL',
                hintText: 'name@example.com',
                floatingLabelBehavior: FloatingLabelBehavior.always,
              ),
            ),
            const SizedBox(height: 11),
            PasswordField(
              controller: _passwordController,
              label: 'Password',
              validator: AuthValidators.password,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 11),
            PasswordField(
              controller: _confirmPasswordController,
              label: 'Confirm password',
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
            const SizedBox(height: 8),
            const Text(
              'Use 8–16 letters or numbers • Passwords must match',
              style: TextStyle(color: Color(0xFF52668C), fontSize: 10),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: Checkbox(
                    value: _acceptedGuidelines,
                    activeColor: const Color(0xFF2E60C4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(5),
                    ),
                    side: const BorderSide(color: Color(0xFF2E60C4)),
                    onChanged: _isLoading
                        ? null
                        : (value) => setState(
                            () => _acceptedGuidelines = value ?? false,
                          ),
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'I accept the ',
                  style: TextStyle(color: Color(0xFF53627B), fontSize: 11),
                ),
                Flexible(
                  child: InkWell(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const CommunityGuidelinesScreen(),
                      ),
                    ),
                    child: const Text(
                      'Community Guidelines',
                      style: TextStyle(
                        color: Color(0xFF2E60C4),
                        fontSize: 11,
                        decoration: TextDecoration.underline,
                        decorationColor: Color(0xFF2E60C4),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _isLoading ? null : _register,
              child: _isLoading
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Create account'),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                const Text(
                  'Already have an account?',
                  style: TextStyle(color: Color(0xFF62708A), fontSize: 13),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.only(left: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: _isLoading
                      ? null
                      : () => Navigator.of(context).pop(),
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
