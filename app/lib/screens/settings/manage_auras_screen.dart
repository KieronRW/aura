// Manage Auras screen — properties with their installations, add/configure auras

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/property_provider.dart';
import '../../providers/installation_provider.dart';
import '../../theme/aura_theme.dart';
import '../onboarding/discover_mirror_screen.dart';
import 'aura_settings_screen.dart';

bool _isActuallyOnline(Map<String, dynamic>? status) {
  if (status == null) return false;
  if (status['is_online'] != true) return false;
  final lastSeen = status['last_seen_at'];
  if (lastSeen == null) return false;
  return DateTime.now().toUtc()
      .difference(DateTime.parse(lastSeen.toString()))
      .inSeconds < 45;
}

class ManageAurasScreen extends ConsumerStatefulWidget {
  const ManageAurasScreen({super.key});

  @override
  ConsumerState<ManageAurasScreen> createState() => _ManageAurasScreenState();
}

class _ManageAurasScreenState extends ConsumerState<ManageAurasScreen> {
  Future<void> _addAura(String? propertyId, Set<String> ownedKeys) async {
    final added = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => DiscoverMirrorScreen(
          propertyId: propertyId,
          ownedKeys: ownedKeys,
        ),
      ),
    );
    if (added == true && mounted) {
      ref.invalidate(propertiesProvider);
      if (propertyId != null) {
        ref.invalidate(installationsProvider(propertyId));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final propertiesAsync = ref.watch(propertiesProvider);

    return Scaffold(
      backgroundColor: kVoid,
      appBar: AppBar(
        backgroundColor: kVoid,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'MANAGE AURAS',
          style: kHeading(),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: kBgGradient),
        child: SafeArea(
          child: propertiesAsync.when(
            loading: () => Center(
              child: CircularProgressIndicator(
                color: kViolet,
                strokeWidth: 1.5,
              ),
            ),
            error: (_, _) => Center(
              child: Text(
                'Failed to load properties',
                style: kCaption(),
              ),
            ),
            data: (propertyModels) {
              if (propertyModels.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: GestureDetector(
                    onTap: () => _addAura(null, {}),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        border: Border.all(color: kCardBorder),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.add, color: Color(0x66FFFFFF), size: 16),
                          const SizedBox(width: 8),
                          Text(
                            'ADD AURA',
                            style: kLabel(),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.all(24),
                itemCount: propertyModels.length,
                itemBuilder: (context, index) {
                  final property = propertyModels[index].toMap();
                  return _PropertySection(
                    property: property,
                    onAddAura: (ownedKeys) => _addAura(property['id'] as String, ownedKeys),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PropertySection extends ConsumerWidget {
  final Map<String, dynamic> property;
  final void Function(Set<String> ownedKeys) onAddAura;

  const _PropertySection({
    required this.property,
    required this.onAddAura,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final installationsAsync = ref.watch(
      installationsProvider(property['id'] as String),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              (property['name'] as String).toUpperCase(),
              style: kLabel(),
            ),
            GestureDetector(
              onTap: () {
                final installations = installationsAsync.valueOrNull ?? [];
                final ownedKeys = installations
                    .map((i) => i.toMap()['installation_key'] as String? ?? '')
                    .where((k) => k.isNotEmpty)
                    .toSet();
                onAddAura(ownedKeys);
              },
              child: Row(
                children: [
                  const Icon(Icons.add, color: Color(0x66FFFFFF), size: 16),
                  const SizedBox(width: 4),
                  Text(
                    'ADD',
                    style: kLabel(),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        installationsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: Center(
              child: CircularProgressIndicator(
                color: kViolet,
                strokeWidth: 1.5,
              ),
            ),
          ),
          error: (_, _) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              'Failed to load',
              style: kCaption(),
            ),
          ),
          data: (installationModels) {
            if (installationModels.isEmpty) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Text(
                  'No Auras at this location',
                  style: kCaption(),
                ),
              );
            }
            return Column(
              children: [
                ...installationModels.map((model) => _AuraRow(
                  installation: model.toMap(),
                  propertyId: property['id'] as String,
                )),
                const SizedBox(height: 16),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _AuraRow extends ConsumerWidget {
  final Map<String, dynamic> installation;
  final String propertyId;

  const _AuraRow({required this.installation, required this.propertyId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = installation['id'] as String;
    final statusAsync = ref.watch(deviceStatusProvider(id));
    final isOnline = _isActuallyOnline(statusAsync.valueOrNull);

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AuraSettingsScreen(
            installation: installation,
            propertyId: propertyId,
          ),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: kCard,
          border: Border.all(color: kCardBorder),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            const Icon(Icons.sensors, color: Color(0x66FFFFFF), size: 20),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                installation['name'] as String? ?? 'Aura',
                style: kBody(),
              ),
            ),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: isOnline ? kOnline : kError,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              isOnline ? 'Online' : 'Offline',
              style: kCaption(isOnline ? kOnlineText : kErrorText),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: Color(0x40FFFFFF), size: 18),
          ],
        ),
      ),
    );
  }
}
