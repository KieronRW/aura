import 'package:flutter/material.dart';

import '../../theme/aura_theme.dart';

// Reusable scrollable T&Cs body — no scroll wrapper, embed inside your own
// ScrollView. Used by both TermsScreen (gate) and TermsViewScreen (read-only).
class TermsContent extends StatelessWidget {
  const TermsContent({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          color: const Color(0xFF1A1400),
          child: const Text(
            '⚠ PLACEHOLDER — These terms are not legally binding and will be '
            'replaced with finalised legal text before public launch.',
            style: TextStyle(color: Colors.amber, fontSize: 12, height: 1.5),
          ),
        ),
        const SizedBox(height: 28),
        const _Section(
          number: '1.',
          title: 'Acceptance of Terms',
          body:
              'By accessing or using the Aura application you agree to be bound '
              'by these Terms and Conditions. If you do not agree to these terms '
              'you may not use the service. Your continued use of the service '
              'constitutes acceptance of any updated terms.',
        ),
        const _Section(
          number: '2.',
          title: 'Use of Service',
          body:
              'Aura is provided for lawful vehicle recognition and property '
              'access management purposes only. You are responsible for ensuring '
              'that your use of the service complies with all applicable local '
              'laws and regulations. Unauthorised use of the service, including '
              'attempts to circumvent security measures, is strictly prohibited.',
        ),
        const _Section(
          number: '3.',
          title: 'Privacy',
          body:
              'We collect and process personal data including vehicle images, '
              'recognition events, and account information to provide and improve '
              'the Aura service. Data is stored securely and is not sold to third '
              'parties. Please refer to our Privacy Policy for full details on '
              'how your data is handled.',
        ),
        const _Section(
          number: '4.',
          title: 'Limitation of Liability',
          body:
              'Aura and its developers are not liable for any damages arising '
              'from the use or inability to use the service, including but not '
              'limited to missed recognition events, system downtime, or data '
              'loss. The service is provided "as is" without warranties of any '
              'kind, express or implied.',
        ),
        const _Section(
          number: '5.',
          title: 'Changes to Terms',
          body:
              'We reserve the right to modify these Terms and Conditions at any '
              'time. Users will be notified of material changes and may be '
              'required to re-accept updated terms before continuing to use the '
              'service. Continued use after notification constitutes acceptance '
              'of the revised terms.',
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  final String number;
  final String title;
  final String body;

  const _Section({
    required this.number,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                number,
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 12,
                  fontWeight: FontWeight.w300,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w300,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            body,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              height: 1.7,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Read-only viewer — used from About Aura screen
// ---------------------------------------------------------------------------

class TermsViewScreen extends StatelessWidget {
  final String title;

  const TermsViewScreen({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kVoid,
      appBar: AppBar(
        backgroundColor: kVoid,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            letterSpacing: 4,
            fontWeight: FontWeight.w300,
          ),
        ),
      ),
      body: const SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(24),
          child: TermsContent(),
        ),
      ),
    );
  }
}
