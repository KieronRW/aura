// Admin screen — diagnostics, settings, software updates

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/login_screen.dart';

class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  Future<void> _signOut(BuildContext context) async {
    await Supabase.instance.client.auth.signOut();
    if (context.mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ADMIN',
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 4,
                color: Colors.white38,
              ),
            ),
            const SizedBox(height: 32),
            // Diagnostics section
            const Text(
              'DIAGNOSTICS',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 3,
                color: Colors.white24,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF111111),
                border: Border.all(color: Colors.white12),
              ),
              child: const Column(
                children: [
                  _DiagnosticRow(label: 'Camera', value: 'Online'),
                  _DiagnosticRow(label: 'Display', value: '1 client'),
                  _DiagnosticRow(label: 'Supabase', value: 'Connected'),
                  _DiagnosticRow(label: 'Software', value: 'v1.0.1'),
                ],
              ),
            ),
            const Spacer(),
            // Sign out
            GestureDetector(
              onTap: () => _signOut(context),
              child: const Text(
                'SIGN OUT',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 4,
                  color: Colors.white38,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiagnosticRow extends StatelessWidget {
  final String label;
  final String value;

  const _DiagnosticRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white38, fontSize: 13),
          ),
          Text(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
