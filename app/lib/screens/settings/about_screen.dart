import 'package:flutter/material.dart';
import '../../theme/aura_theme.dart';
import '../auth/terms_content.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kVoid,
      appBar: AppBar(
        backgroundColor: kVoid,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'About',
          style: kHeading(),
        ),
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Container(
          decoration: const BoxDecoration(gradient: kBgGradient),
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                // ── ABOUT ─────────────────────────────────────────────────────
                const SizedBox(height: 40),
                Center(
                  child: Text(
                    'AURA',
                    style: kTitle(),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    'Aura Studio',
                    style: kBody(),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    'Version 1.0.0',
                    style: kCaption(),
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    'A product of VIVO Automation',
                    style: kCaption(),
                  ),
                ),

                const SizedBox(height: 56),

                // ── LEGAL ─────────────────────────────────────────────────────
                Text(
                  'LEGAL',
                  style: kLabel(),
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
          border: Border(bottom: BorderSide(color: kRowDivider)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: kBody(kVioletText),
              ),
            ),
            const Icon(Icons.chevron_right, color: Color(0x40FFFFFF), size: 18),
          ],
        ),
      ),
    );
  }
}
