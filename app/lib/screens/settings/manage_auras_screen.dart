// Manage Auras screen — properties with their installations, add/configure auras

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/property_provider.dart';
import '../../providers/installation_provider.dart';
import '../onboarding/discover_mirror_screen.dart';
import 'aura_settings_screen.dart';

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
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'MANAGE AURAS',
          style: TextStyle(
            fontSize: 13,
            letterSpacing: 4,
            fontWeight: FontWeight.w300,
          ),
        ),
      ),
      body: SafeArea(
        child: propertiesAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(
              color: Colors.white24,
              strokeWidth: 1,
            ),
          ),
          error: (_, _) => const Center(
            child: Text(
              'Failed to load properties',
              style: TextStyle(color: Colors.white38),
            ),
          ),
          data: (propertyModels) {
            if (propertyModels.isEmpty) {
              return const Center(
                child: Text(
                  'No locations found.\nAdd a location first in Manage Locations.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white38, fontSize: 13, height: 1.6),
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
              style: const TextStyle(
                fontSize: 11,
                letterSpacing: 3,
                color: Colors.white38,
              ),
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
              child: const Row(
                children: [
                  Icon(Icons.add, color: Colors.white54, size: 16),
                  SizedBox(width: 4),
                  Text(
                    'ADD',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 10,
                      letterSpacing: 2,
                    ),
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
                color: Colors.white24,
                strokeWidth: 1,
              ),
            ),
          ),
          error: (_, _) => const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: Text(
              'Failed to load',
              style: TextStyle(color: Colors.white24, fontSize: 13),
            ),
          ),
          data: (installationModels) {
            if (installationModels.isEmpty) {
              return const Padding(
                padding: EdgeInsets.only(bottom: 24),
                child: Text(
                  'No Auras at this location',
                  style: TextStyle(color: Colors.white24, fontSize: 13),
                ),
              );
            }
            return Column(
              children: [
                ...installationModels.map((model) {
                  final installation = model.toMap();
                  return GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AuraSettingsScreen(
                          installation: installation,
                          propertyId: property['id'] as String,
                        ),
                      ),
                    ),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF111111),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.sensors,
                            color: Colors.white38,
                            size: 20,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              installation['name'] as String? ?? 'Aura',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w300,
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right,
                            color: Colors.white24,
                            size: 18,
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 16),
              ],
            );
          },
        ),
      ],
    );
  }
}
