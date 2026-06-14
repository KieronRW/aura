// Settings screen — account, locations, automations, app, support

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../providers/auth_provider.dart';
import '../auth/login_screen.dart';
import '../automations/automations_screen.dart';
import 'account_details_screen.dart';
import 'diagnostics_screen.dart';
import 'locations_screen.dart';
import 'about_screen.dart';
import 'app_preferences_screen.dart';
import 'manage_auras_screen.dart';
import 'support_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(authProvider);
    final user = userAsync.value;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'SETTINGS',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 4,
              color: Colors.white38,
            ),
          ),
          const SizedBox(height: 32),

          // ── ACCOUNT ────────────────────────────────────────────────────────
          const _SectionHeader(title: 'ACCOUNT'),
          _SettingsRow(
            icon: Icons.person_outline,
            title: 'Account Details',
            subtitle: user?.email ?? '',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AccountDetailsScreen()),
            ),
          ),
          _SettingsRow(
            icon: Icons.credit_card_outlined,
            title: 'Plan & Usage',
            subtitle: 'Free plan',
            onTap: () {},
          ),

          const SizedBox(height: 32),

          // ── LOCATIONS & AURAS ──────────────────────────────────────────────
          const _SectionHeader(title: 'LOCATIONS & AURAS'),
          _SettingsRow(
            icon: Icons.location_on_outlined,
            title: 'Manage Locations',
            subtitle: 'Properties and addresses',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LocationsScreen()),
            ),
          ),
          _SettingsRow(
            icon: Icons.sensors,
            title: 'Manage Auras',
            subtitle: 'View and configure your Auras',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ManageAurasScreen()),
            ),
          ),

          const SizedBox(height: 32),

          // ── AUTOMATIONS ────────────────────────────────────────────────────
          const _SectionHeader(title: 'AUTOMATIONS'),
          _SettingsRow(
            icon: Icons.bolt_outlined,
            title: 'Automation Rules',
            subtitle: 'Event-driven rules',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => Scaffold(
                  backgroundColor: Colors.black,
                  appBar: AppBar(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    title: const Text(
                      'AUTOMATIONS',
                      style: TextStyle(
                        fontSize: 13,
                        letterSpacing: 4,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                  ),
                  body: const AutomationsScreen(),
                ),
              ),
            ),
          ),
          _SettingsRow(
            icon: Icons.link_outlined,
            title: 'Integrations',
            subtitle: 'Integrations coming soon',
            onTap: () {},
          ),

          const SizedBox(height: 32),

          // ── APP ────────────────────────────────────────────────────────────
          const _SectionHeader(title: 'APP'),
          _SettingsRow(
            icon: Icons.notifications_outlined,
            title: 'Notifications',
            onTap: () {},
          ),
          _SettingsRow(
            icon: Icons.palette_outlined,
            title: 'Theme',
            subtitle: 'Dark',
            onTap: () {},
          ),
          _SettingsRow(
            icon: Icons.tune_outlined,
            title: 'App Preferences',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const AppPreferencesScreen()),
            ),
          ),

          const SizedBox(height: 32),

          // ── SUPPORT ────────────────────────────────────────────────────────
          const _SectionHeader(title: 'SUPPORT'),
          _SettingsRow(
            icon: Icons.monitor_heart_outlined,
            title: 'Diagnostics',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DiagnosticsScreen()),
            ),
          ),
          _SettingsRow(
            icon: Icons.help_outline,
            title: 'Support',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SupportScreen()),
            ),
          ),
          _SettingsRow(
            icon: Icons.info_outline,
            title: 'About Aura',
            subtitle: 'Version 1.0.0',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AboutScreen()),
            ),
          ),

          const SizedBox(height: 32),

          // ── SIGN OUT ───────────────────────────────────────────────────────
          _SettingsRow(
            icon: Icons.logout,
            title: 'Sign Out',
            destructive: true,
            onTap: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  backgroundColor: const Color(0xFF111111),
                  title: const Text('SIGN OUT', style: TextStyle(color: Colors.white, fontSize: 14, letterSpacing: 3, fontWeight: FontWeight.w300)),
                  content: const Text('Are you sure you want to sign out?', style: TextStyle(color: Colors.white38, fontSize: 13, height: 1.6)),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCEL', style: TextStyle(color: Colors.white38, letterSpacing: 2))),
                    TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('SIGN OUT', style: TextStyle(color: Colors.redAccent, letterSpacing: 2))),
                  ],
                ),
              );
              if (confirmed == true) {
                await Supabase.instance.client.auth.signOut();
                if (context.mounted) {
                  Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
                }
              }
            },
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 10,
          letterSpacing: 3,
          color: Colors.white24,
        ),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool destructive;
  final VoidCallback onTap;

  const _SettingsRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.destructive = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = destructive ? Colors.redAccent : Colors.white;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.white12)),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: destructive ? Colors.redAccent : Colors.white38,
              size: 20,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: color,
                      fontSize: 14,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
            if (!destructive)
              const Icon(Icons.chevron_right, color: Colors.white24, size: 18),
          ],
        ),
      ),
    );
  }
}
