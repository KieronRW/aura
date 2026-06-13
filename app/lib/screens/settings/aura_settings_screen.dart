// Aura Settings screen — display, camera, network, recognition settings for one Aura

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../providers/installation_provider.dart';
import '../../providers/property_provider.dart';
import '../aura/camera_settings_screen.dart';
import '../aura/display_settings_screen.dart';
import '../aura/network_settings_screen.dart';
import '../onboarding/discover_mirror_screen.dart';

class AuraSettingsScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> installation;
  final String propertyId;

  const AuraSettingsScreen({
    super.key,
    required this.installation,
    required this.propertyId,
  });

  @override
  ConsumerState<AuraSettingsScreen> createState() => _AuraSettingsScreenState();
}

class _AuraSettingsScreenState extends ConsumerState<AuraSettingsScreen> {
  late Map<String, dynamic> _installation;

  @override
  void initState() {
    super.initState();
    _installation = Map<String, dynamic>.from(widget.installation);
  }

  Future<void> _addAura() async {
    final installationsAsync = ref.read(
      installationsProvider(widget.propertyId),
    );
    final installations = installationsAsync.valueOrNull ?? [];
    final ownedKeys = installations
        .map((i) => i.toMap()['installation_key'] as String? ?? '')
        .where((k) => k.isNotEmpty)
        .toSet();

    final added = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => DiscoverMirrorScreen(
          propertyId: widget.propertyId,
          ownedKeys: ownedKeys,
        ),
      ),
    );
    if (added == true && mounted) {
      ref.invalidate(installationsProvider(widget.propertyId));
      ref.invalidate(propertiesProvider);
    }
  }

  void _showRemoveDialog() {
    final nav = Navigator.of(context);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF111111),
        title: const Text(
          'REMOVE AURA',
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            letterSpacing: 3,
            fontWeight: FontWeight.w300,
          ),
        ),
        content: Text(
          'Remove "${_installation['name'] ?? 'this Aura'}" from your account? It can be reclaimed later.',
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 13,
            height: 1.6,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => nav.pop(),
            child: const Text(
              'CANCEL',
              style: TextStyle(color: Colors.white38, letterSpacing: 2),
            ),
          ),
          TextButton(
            onPressed: () async {
              try {
                await Supabase.instance.client
                    .from('installations')
                    .update({
                      'status': 'unclaimed',
                      'claimed_by': null,
                      'property_id': null,
                      'claimed_at': null,
                    })
                    .eq('id', _installation['id']);
                nav.pop();
                if (mounted) {
                  ref.invalidate(installationsProvider(widget.propertyId));
                  ref.invalidate(propertiesProvider);
                  Navigator.of(context).pop();
                }
              } catch (e) {
                debugPrint('Remove aura error: $e');
                nav.pop();
              }
            },
            child: const Text(
              'REMOVE',
              style: TextStyle(color: Colors.redAccent, letterSpacing: 2),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auraName = _installation['name'] as String? ?? 'Aura';
    final localIp = _installation['local_ip'] as String? ?? '';

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          auraName.toUpperCase(),
          style: const TextStyle(
            fontSize: 13,
            letterSpacing: 4,
            fontWeight: FontWeight.w300,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'AURA SETTINGS',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 3,
                color: Colors.white24,
              ),
            ),
            const SizedBox(height: 12),
            _SettingsRow(
              icon: Icons.brightness_6_outlined,
              title: 'Display',
              subtitle: 'Brightness, orientation',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DisplaySettingsScreen(
                    installation: _installation,
                    localIp: localIp,
                  ),
                ),
              ),
            ),
            _SettingsRow(
              icon: Icons.camera_outlined,
              title: 'Camera',
              subtitle: 'Sensitivity, quality',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CameraSettingsScreen(
                    installation: _installation,
                    localIp: localIp,
                  ),
                ),
              ),
            ),
            _SettingsRow(
              icon: Icons.wifi_outlined,
              title: 'Network',
              subtitle: localIp.isNotEmpty ? localIp : 'DHCP',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => NetworkSettingsScreen(
                    installation: _installation,
                    localIp: localIp,
                  ),
                ),
              ),
            ),
            _SettingsRow(
              icon: Icons.tune_outlined,
              title: 'Recognition',
              subtitle: 'Confidence thresholds',
              onTap: () {},
            ),
            const SizedBox(height: 32),
            const Text(
              'MANAGE',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 3,
                color: Colors.white24,
              ),
            ),
            const SizedBox(height: 12),
            _SettingsRow(
              icon: Icons.add_circle_outline,
              title: 'Add New Aura',
              subtitle: 'Discover and add another Aura',
              onTap: _addAura,
            ),
            const SizedBox(height: 24),
            _SettingsRow(
              icon: Icons.link_off,
              title: 'Remove Aura',
              subtitle: 'Unlink this Aura from your account',
              destructive: true,
              onTap: _showRemoveDialog,
            ),
          ],
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
                      color: destructive ? Colors.redAccent : Colors.white,
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
