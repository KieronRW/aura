import 'package:flutter/material.dart';
import '../auth/terms_content.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'ABOUT',
          style: TextStyle(
            fontSize: 13,
            letterSpacing: 4,
            fontWeight: FontWeight.w300,
          ),
        ),
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              // ── ABOUT ─────────────────────────────────────────────────────
              const SizedBox(height: 40),
              const Center(
                child: Text(
                  'AURA',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 48,
                    letterSpacing: 8,
                    fontWeight: FontWeight.w200,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Center(
                child: Text(
                  'Aura Studio',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 14,
                    fontWeight: FontWeight.w300,
                    letterSpacing: 1,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Center(
                child: Text(
                  'Version 1.0.0',
                  style: TextStyle(
                    color: Colors.white24,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Center(
                child: Text(
                  'A product of VIVO Automation',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 12,
                  ),
                ),
              ),

              const SizedBox(height: 56),

              // ── LEGAL ─────────────────────────────────────────────────────
              const Text(
                'LEGAL',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 3,
                  color: Colors.white24,
                ),
              ),
              const SizedBox(height: 12),
              _LegalRow(
                title: 'Terms of Service',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const TermsViewScreen(title: 'TERMS OF SERVICE'),
                  ),
                ),
              ),
              _LegalRow(
                title: 'Privacy Policy',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const TermsViewScreen(title: 'PRIVACY POLICY'),
                  ),
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _LegalRow extends StatelessWidget {
  final String title;
  final VoidCallback onTap;

  const _LegalRow({required this.title, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.white12)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w300,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white24, size: 18),
          ],
        ),
      ),
    );
  }
}
