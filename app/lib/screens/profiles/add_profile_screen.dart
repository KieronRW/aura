// Add Profile screen — create a new profile with first/last name and optional avatar

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../providers/profile_provider.dart';

class AddProfileScreen extends ConsumerStatefulWidget {
  final String installationId;

  const AddProfileScreen({super.key, required this.installationId});

  @override
  ConsumerState<AddProfileScreen> createState() => _AddProfileScreenState();
}

class _AddProfileScreenState extends ConsumerState<AddProfileScreen> {
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  File? _avatarFile;
  bool _loading = false;
  String? _error;
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _firstNameController.addListener(() => setState(() {}));
    _lastNameController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  bool get _canSave =>
      _firstNameController.text.trim().isNotEmpty &&
      _lastNameController.text.trim().isNotEmpty;

  Future<void> _pickAvatar(ImageSource source) async {
    try {
      final file = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 512,
      );
      if (file != null && mounted) {
        setState(() => _avatarFile = File(file.path));
      }
    } catch (e) {
      debugPrint('Avatar pick error: $e');
    }
  }

  void _showAvatarSourceDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111111),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(
                Icons.camera_alt_outlined,
                color: Colors.white38,
              ),
              title: const Text(
                'Take photo',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                _pickAvatar(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.photo_library_outlined,
                color: Colors.white38,
              ),
              title: const Text(
                'Choose from library',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                _pickAvatar(ImageSource.gallery);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_canSave) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final client = Supabase.instance.client;
      final firstName = _firstNameController.text.trim();
      final lastName = _lastNameController.text.trim();
      final displayName = '$firstName $lastName';

      final response = await client
          .from('profiles')
          .insert({
            'installation_id': widget.installationId,
            'first_name': firstName,
            'last_name': lastName,
            'display_name': displayName,
            'greeting': 'Welcome, $firstName',
            'is_active': true,
          })
          .select('id')
          .single();

      final profileId = response['id'] as String;

      if (_avatarFile != null) {
        final bytes = await _avatarFile!.readAsBytes();
        final storagePath = 'profiles/$profileId/avatar.jpg';
        await client.storage.from('avatars').uploadBinary(
          storagePath,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: true,
          ),
        );
        await client.from('profiles').update({
          'avatar_path': storagePath,
          'avatar_updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', profileId);
      }

      if (mounted) {
        ref.read(profilesProvider.notifier).refresh();
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint('Add profile error: $e');
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
            onPressed: (_loading || !_canSave) ? null : _save,
            child: Text(
              'SAVE',
              style: TextStyle(
                color: _canSave ? Colors.white : Colors.white24,
                letterSpacing: 2,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
          child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            // Avatar picker
            Center(
              child: GestureDetector(
                onTap: _showAvatarSourceDialog,
                child: Stack(
                  children: [
                    Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white24),
                        color: const Color(0xFF111111),
                      ),
                      child: ClipOval(
                        child: _avatarFile != null
                            ? Image.file(_avatarFile!, fit: BoxFit.cover)
                            : const Center(
                                child: Icon(
                                  Icons.person_outline,
                                  color: Colors.white38,
                                  size: 36,
                                ),
                              ),
                      ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.black, width: 2),
                        ),
                        child: const Icon(
                          Icons.camera_alt,
                          color: Colors.black,
                          size: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),
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
              controller: _firstNameController,
              style: const TextStyle(color: Colors.white),
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'First Name *',
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
            const SizedBox(height: 16),
            TextField(
              controller: _lastNameController,
              style: const TextStyle(color: Colors.white),
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Last Name *',
                labelStyle: TextStyle(color: Colors.white38),
                hintText: 'e.g. Smith',
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
      ),
    );
  }
}
