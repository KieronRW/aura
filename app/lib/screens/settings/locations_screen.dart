// Locations screen — manage properties and their Auras

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../providers/property_provider.dart';

class LocationsScreen extends ConsumerStatefulWidget {
  const LocationsScreen({super.key});

  @override
  ConsumerState<LocationsScreen> createState() => _LocationsScreenState();
}

class _LocationsScreenState extends ConsumerState<LocationsScreen> {
  void _showAddLocationDialog() {
    final nameController = TextEditingController();
    final addressController = TextEditingController();
    final nav = Navigator.of(context);

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF111111),
        title: const Text(
          'ADD LOCATION',
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            letterSpacing: 3,
            fontWeight: FontWeight.w300,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              maxLength: 20,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Name',
                labelStyle: TextStyle(color: Colors.white38),
                hintText: 'e.g. Summer Ridge, Office',
                hintStyle: TextStyle(color: Colors.white24),
                counterStyle: TextStyle(color: Colors.white24),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: addressController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Address (optional)',
                labelStyle: TextStyle(color: Colors.white38),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white),
                ),
              ),
            ),
          ],
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
              final name = nameController.text.trim();
              if (name.isEmpty) return;
              await _addProperty(
                name: name,
                address: addressController.text.trim(),
              );
              nav.pop();
            },
            child: const Text(
              'ADD',
              style: TextStyle(color: Colors.white, letterSpacing: 2),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addProperty({required String name, String? address}) async {
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser!.id;
      await client.from('properties').insert({
        'user_id': userId,
        'name': name,
        'address': address?.isNotEmpty == true ? address : null,
        'timezone': 'UTC',
      });
      await ref.read(propertiesProvider.notifier).refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to add location'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _showEditDialog(Map<String, dynamic> property) {
    final nameController = TextEditingController(text: property['name']);
    final addressController = TextEditingController(
      text: property['address'] ?? '',
    );
    final nav = Navigator.of(context);

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF111111),
        title: const Text(
          'EDIT LOCATION',
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            letterSpacing: 3,
            fontWeight: FontWeight.w300,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              maxLength: 20,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Name',
                labelStyle: TextStyle(color: Colors.white38),
                counterStyle: TextStyle(color: Colors.white24),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: addressController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Address (optional)',
                labelStyle: TextStyle(color: Colors.white38),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white),
                ),
              ),
            ),
          ],
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
              final name = nameController.text.trim();
              if (name.isNotEmpty) {
                final address = addressController.text.trim();
                await Supabase.instance.client
                    .from('properties')
                    .update({
                      'name': name,
                      'address': address.isNotEmpty ? address : null,
                    })
                    .eq('id', property['id']);
                await ref.read(propertiesProvider.notifier).refresh();
              }
              nav.pop();
            },
            child: const Text(
              'SAVE',
              style: TextStyle(color: Colors.white, letterSpacing: 2),
            ),
          ),
        ],
      ),
    );
  }

  void _showRenameDialog(Map<String, dynamic> property) {
    final controller = TextEditingController(text: property['name']);
    final nav = Navigator.of(context);

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF111111),
        title: const Text(
          'RENAME LOCATION',
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            letterSpacing: 3,
            fontWeight: FontWeight.w300,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 20,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            counterStyle: TextStyle(color: Colors.white24),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white24),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white),
            ),
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
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                await Supabase.instance.client
                    .from('properties')
                    .update({'name': name})
                    .eq('id', property['id']);
                await ref.read(propertiesProvider.notifier).refresh();
              }
              nav.pop();
            },
            child: const Text(
              'SAVE',
              style: TextStyle(color: Colors.white, letterSpacing: 2),
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(Map<String, dynamic> property) {
    final nav = Navigator.of(context);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF111111),
        title: const Text(
          'DELETE LOCATION',
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            letterSpacing: 3,
            fontWeight: FontWeight.w300,
          ),
        ),
        content: Text(
          'Delete "${property['name']}"? All Auras at this location will be released.',
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
              await Supabase.instance.client
                  .from('properties')
                  .update({'is_active': false})
                  .eq('id', property['id']);
              await ref.read(propertiesProvider.notifier).refresh();
              nav.pop();
            },
            child: const Text(
              'DELETE',
              style: TextStyle(color: Colors.redAccent, letterSpacing: 2),
            ),
          ),
        ],
      ),
    );
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
            onPressed: _showAddLocationDialog,
            icon: const Icon(Icons.add, color: Colors.white),
          ),
        ],
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
          child: loading
            ? const Center(
                child: CircularProgressIndicator(
                  color: Colors.white24,
                  strokeWidth: 1,
                ),
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
                  return Container(
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
                                property['name'],
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w300,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (property['address'] != null)
                                Text(
                                  property['address'],
                                  style: const TextStyle(
                                    color: Colors.white38,
                                    fontSize: 12,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                        PopupMenuButton<String>(
                          color: const Color(0xFF222222),
                          icon: const Icon(
                            Icons.more_vert,
                            color: Colors.white38,
                            size: 20,
                          ),
                          onSelected: (value) {
                            if (value == 'edit') {
                              _showEditDialog(property);
                            } else if (value == 'rename') {
                              _showRenameDialog(property);
                            } else if (value == 'delete') {
                              _showDeleteDialog(property);
                            }
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              value: 'edit',
                              child: Text(
                                'Edit',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'rename',
                              child: Text(
                                'Rename',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Text(
                                'Delete',
                                style: TextStyle(color: Colors.redAccent),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
        ),
      ),
    );
  }
}
