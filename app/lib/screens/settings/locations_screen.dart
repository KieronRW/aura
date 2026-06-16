// Locations screen — manage properties and their Auras

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../providers/property_provider.dart';
import 'location_detail_screen.dart';
import '../../widgets/skeleton.dart';

class LocationsScreen extends ConsumerStatefulWidget {
  const LocationsScreen({super.key});

  @override
  ConsumerState<LocationsScreen> createState() => _LocationsScreenState();
}

class _LocationsScreenState extends ConsumerState<LocationsScreen> {
  Future<void> _createAndOpenLocation() async {
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser!.id;
      final result = await client
          .from('properties')
          .insert({
            'user_id': userId,
            'name': 'New Location',
            'timezone': 'UTC',
            'is_active': true,
          })
          .select()
          .single();

      if (!mounted) return;
      await _openDetail(Map<String, dynamic>.from(result));
    } catch (e) {
      debugPrint('Create location error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to create location'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _openDetail(Map<String, dynamic> property) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => LocationDetailScreen(property: property),
      ),
    );
    if (result == true && mounted) {
      ref.invalidate(propertiesProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final propertiesAsync = ref.watch(propertiesProvider);
    final properties = propertiesAsync.valueOrNull
            ?.map((p) => p.toMap())
            .toList() ??
        [];
    final loading = propertiesAsync.isLoading && properties.isEmpty;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'LOCATIONS',
          style: TextStyle(
            fontSize: 13,
            letterSpacing: 4,
            fontWeight: FontWeight.w300,
          ),
        ),
        actions: [
          IconButton(
            onPressed: _createAndOpenLocation,
            icon: const Icon(Icons.add, color: Colors.white),
          ),
        ],
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
          child: loading
            ? ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  SkeletonList(
                    itemCount: 2,
                    itemBuilder: (ctx, i) => Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF111111),
                        border: Border.all(color: const Color(0xFF222222)),
                      ),
                      child: Row(
                        children: const [
                          SkeletonBox(width: 20, height: 20, borderRadius: 10),
                          SizedBox(width: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SkeletonBox(width: 140, height: 14, borderRadius: 4),
                              SizedBox(height: 6),
                              SkeletonBox(width: 100, height: 12, borderRadius: 4),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              )
            : properties.isEmpty
            ? const Center(
                child: Text(
                  'No locations yet',
                  style: TextStyle(color: Colors.white24, fontSize: 13),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(24),
                itemCount: properties.length,
                itemBuilder: (context, index) {
                  final property = properties[index];
                  return GestureDetector(
                    onTap: () => _openDetail(property),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF111111),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.location_on_outlined,
                            color: Colors.white38,
                            size: 20,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  property['name'] as String? ?? '',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w300,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (property['address'] != null)
                                  Text(
                                    property['address'] as String,
                                    style: const TextStyle(
                                      color: Colors.white38,
                                      fontSize: 12,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
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
                },
              ),
        ),
      ),
    );
  }
}
