import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../providers/auth_provider.dart';
import '../../theme/aura_theme.dart';
import '../auth/splash_screen.dart';

class AccountDetailsScreen extends ConsumerStatefulWidget {
  const AccountDetailsScreen({super.key});

  @override
  ConsumerState<AccountDetailsScreen> createState() =>
      _AccountDetailsScreenState();
}

class _AccountDetailsScreenState extends ConsumerState<AccountDetailsScreen> {
  final _newPasswordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  bool _saving = false;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _newPasswordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  String? _validate() {
    final pw = _newPasswordCtrl.text;
    final confirm = _confirmPasswordCtrl.text;
    if (pw.isEmpty) return 'Enter a new password';
    if (pw.length < 6) return 'Password must be at least 6 characters';
    if (pw != confirm) return 'Passwords do not match';
    return null;
  }

  Future<void> _onSave() async {
    final error = _validate();
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error, style: kBody()),
          backgroundColor: kError,
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: _newPasswordCtrl.text),
      );
      if (mounted) {
        _newPasswordCtrl.clear();
        _confirmPasswordCtrl.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Password updated',
              style: kBody(),
            ),
            backgroundColor: kOnline,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to update password: $e',
              style: kBody(),
            ),
            backgroundColor: kError,
          ),
        );
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: kCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: kCardBorder),
        ),
        title: Text(
          'Sign Out',
          style: kHeading(),
        ),
        content: Text(
          'Are you sure you want to sign out?',
          style: kCaption(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: kBody(),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Sign Out',
              style: kBody(kErrorText),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await Supabase.instance.client.auth.signOut();
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const SplashScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = ref.watch(authProvider).value?.email ?? '';

    return Scaffold(
      backgroundColor: kVoid,
      appBar: AppBar(
        backgroundColor: kVoid,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'Account Details',
          style: kHeading(),
        ),
        actions: [
          AnimatedOpacity(
            opacity: _saving ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    color: kViolet,
                    strokeWidth: 1.5,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Container(
          decoration: const BoxDecoration(gradient: kBgGradient),
          child: Stack(
            children: [
              ListView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 100),
                children: [
                  // ── EMAIL ──────────────────────────────────────────────────
                  _sectionLabel('EMAIL'),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: kRowDivider)),
                    ),
                    child: Text(
                      email.isNotEmpty ? email : '—',
                      style: kBody(),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // ── CHANGE PASSWORD ────────────────────────────────────────
                  _sectionLabel('CHANGE PASSWORD'),
                  const SizedBox(height: 16),
                  _PasswordField(
                    label: 'NEW PASSWORD',
                    controller: _newPasswordCtrl,
                    obscure: _obscureNew,
                    onToggle: () => setState(() => _obscureNew = !_obscureNew),
                  ),
                  const SizedBox(height: 20),
                  _PasswordField(
                    label: 'CONFIRM PASSWORD',
                    controller: _confirmPasswordCtrl,
                    obscure: _obscureConfirm,
                    onToggle: () =>
                        setState(() => _obscureConfirm = !_obscureConfirm),
                  ),

                  const SizedBox(height: 32),

                  // ── SIGN OUT ───────────────────────────────────────────────
                  _sectionLabel('ACCOUNT'),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: _signOut,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: const BoxDecoration(
                        border:
                            Border(bottom: BorderSide(color: kRowDivider)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.logout, color: kErrorText, size: 20),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              'Sign Out',
                              style: kBody(kErrorText),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              // ── SAVE button ────────────────────────────────────────────────
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  child: Container(
                    color: kVoid,
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                    child: GestureDetector(
                      onTap: _saving ? null : _onSave,
                      child: Container(
                        height: 55,
                        decoration: BoxDecoration(
                          gradient: _saving ? null : kPrimaryGradient,
                          color: _saving ? const Color(0x1FFFFFFF) : null,
                          borderRadius: BorderRadius.circular(15),
                          boxShadow: _saving
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
                        child: Text(
                          'Save',
                          style: kBody(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
        text,
        style: kLabel(),
      );
}

class _PasswordField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool obscure;
  final VoidCallback onToggle;

  const _PasswordField({
    required this.label,
    required this.controller,
    required this.obscure,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: kLabel(),
        ),
        const SizedBox(height: 8),
        Container(
          height: 54,
          decoration: BoxDecoration(
            color: const Color(0x0EFFFFFF),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kInputBorder),
          ),
          child: Row(
            children: [
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  controller: controller,
                  obscureText: obscure,
                  style: kBody(),
                  decoration: InputDecoration(
                    hintText: '••••••••',
                    hintStyle: kBody(const Color(0x66FFFFFF)),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              GestureDetector(
                onTap: onToggle,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Icon(
                    obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                    color: const Color(0x66FFFFFF),
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
