// Registration screen — new user sign up with email/password

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/aura_theme.dart';
import 'verify_email_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _nameController = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _register() async {
    if (_passwordController.text != _confirmPasswordController.text) {
      setState(() => _error = 'Passwords do not match');
      return;
    }
    if (_passwordController.text.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await Supabase.instance.client.auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
        data: {'full_name': _nameController.text.trim()},
      );

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) =>
                VerifyEmailScreen(email: _emailController.text.trim()),
          ),
        );
      }
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kVoid,
      appBar: AppBar(
        backgroundColor: kVoid,
        foregroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: kBgGradient),
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(26, 8, 26, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Create account',
                    style: kScreenTitle(),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Join Aura Studio',
                    style: kCaption(),
                  ),
                  const SizedBox(height: 36),
                  _buildField(_nameController, 'Full name', false),
                  const SizedBox(height: 14),
                  _buildField(
                    _emailController,
                    'Email address',
                    false,
                    type: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 14),
                  _buildField(_passwordController, 'Password', true),
                  const SizedBox(height: 14),
                  _buildField(_confirmPasswordController, 'Confirm password', true),
                  const SizedBox(height: 28),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: kCaption(kErrorText),
                      ),
                    ),
                  GestureDetector(
                    onTap: _loading ? null : _register,
                    child: Container(
                      height: 55,
                      decoration: BoxDecoration(
                        gradient: _loading
                            ? null
                            : kPrimaryGradient,
                        color: _loading ? const Color(0x33FFFFFF) : null,
                        borderRadius: BorderRadius.circular(15),
                        boxShadow: _loading
                            ? null
                            : const [
                                BoxShadow(
                                  color: Color(0x8C6366E8),
                                  blurRadius: 22,
                                  offset: Offset(0, 8),
                                  spreadRadius: -12,
                                ),
                              ],
                      ),
                      alignment: Alignment.center,
                      child: _loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              'Create account',
                              style: GoogleFonts.manrope(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField(
    TextEditingController controller,
    String label,
    bool obscure, {
    TextInputType type = TextInputType.text,
  }) {
    return Container(
      height: 54,
      decoration: BoxDecoration(
        color: const Color(0x0EFFFFFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x1FFFFFFF)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Center(
        child: TextField(
          controller: controller,
          obscureText: obscure,
          keyboardType: type,
          style: GoogleFonts.manrope(color: Colors.white, fontSize: 15),
          decoration: InputDecoration(
            hintText: label,
            hintStyle: GoogleFonts.manrope(
              color: const Color(0x66FFFFFF),
              fontSize: 15,
            ),
            border: InputBorder.none,
            isDense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ),
    );
  }
}
