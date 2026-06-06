// Add Profile screen — create a new profile with name and greeting

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AddProfileScreen extends StatefulWidget {
  final String installationId;

  const AddProfileScreen({super.key, required this.installationId});

  @override
  State<AddProfileScreen> createState() => _AddProfileScreenState();
}

class _AddProfileScreenState extends State<AddProfileScreen> {
  final _nameController = TextEditingController();
  final _greetingController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _greetingController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Please enter a name');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await Supabase.instance.client.from('profiles').insert({
        'installation_id': widget.installationId,
        'display_name': name,
        'owner_greeting': _greetingController.text.trim().isNotEmpty
            ? _greetingController.text.trim()
            : 'Welcome, $name',
        'is_active': true,
      });

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _error = 'Failed to save profile. Please try again.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'ADD PROFILE',
          style: TextStyle(
            fontSize: 13,
            letterSpacing: 4,
            fontWeight: FontWeight.w300,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _loading ? null : _save,
            child: const Text(
              'SAVE',
              style: TextStyle(
                color: Colors.white,
                letterSpacing: 2,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'PROFILE DETAILS',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 3,
                color: Colors.white24,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              style: const TextStyle(color: Colors.white),
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Name',
                labelStyle: TextStyle(color: Colors.white38),
                hintText: 'e.g. Kieron',
                hintStyle: TextStyle(color: Colors.white24),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _greetingController,
              style: const TextStyle(color: Colors.white),
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Custom greeting (optional)',
                labelStyle: TextStyle(color: Colors.white38),
                hintText: 'e.g. Welcome home, Kieron!',
                hintStyle: TextStyle(color: Colors.white24),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 13),
              ),
            ],
            if (_loading) ...[
              const SizedBox(height: 24),
              const Center(
                child: CircularProgressIndicator(
                  color: Colors.white24,
                  strokeWidth: 1,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
