import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../providers/auth_provider.dart';
import '../auth/login_screen.dart';

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
          content: Text(error, style: const TextStyle(color: Colors.white)),
          backgroundColor: Colors.redAccent,
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
          const SnackBar(
            content: Text(
              'Password updated',
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: Color(0xFF222222),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to update password: $e',
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.redAccent,
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
        backgroundColor: const Color(0xFF111111),
        title: const Text(
          'SIGN OUT',
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            letterSpacing: 3,
            fontWeight: FontWeight.w300,
          ),
        ),
        content: const Text(
          'Are you sure you want to sign out?',
          style: TextStyle(color: Colors.white38, fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'CANCEL',
              style: TextStyle(color: Colors.white38, letterSpacing: 2),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'SIGN OUT',
              style: TextStyle(color: Colors.redAccent, letterSpacing: 2),
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
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = ref.watch(authProvider).value?.email ?? '';

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'ACCOUNT DETAILS',
          style: TextStyle(
            fontSize: 13,
            letterSpacing: 4,
            fontWeight: FontWeight.w300,
          ),
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
                    color: Colors.white38,
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
                    border: Border(bottom: BorderSide(color: Colors.white12)),
                  ),
                  child: Text(
                    email.isNotEmpty ? email : '—',
                    style: const TextStyle(color: Colors.white, fontSize: 13),
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
                          Border(bottom: BorderSide(color: Colors.white12)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.logout, color: Colors.redAccent, size: 20),
                        SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            'Sign Out',
                            style: TextStyle(
                              color: Colors.redAccent,
                              fontSize: 14,
                              fontWeight: FontWeight.w300,
                            ),
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
                  color: Colors.black,
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                  child: GestureDetector(
                    onTap: _saving ? null : _onSave,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      color: _saving ? Colors.white24 : Colors.white,
                      child: const Text(
                        'SAVE',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 11,
                          letterSpacing: 4,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 10,
          letterSpacing: 3,
          color: Colors.white24,
        ),
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
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 10,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: obscure,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: '••••••••',
            hintStyle: const TextStyle(color: Colors.white12),
            enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white24),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white),
            ),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            suffixIcon: GestureDetector(
              onTap: onToggle,
              child: Icon(
                obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                color: Colors.white24,
                size: 18,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
