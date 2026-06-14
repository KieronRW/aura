// Profiles screen — manage people and their vehicles

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../widgets/profile_avatar.dart';
import '../../providers/profile_provider.dart';
import '../../services/supabase_service.dart';
import 'add_profile_screen.dart';
import 'greetings_screen.dart';
import 'recognition_history_screen.dart';
import 'vehicle_detail_screen.dart';

class ProfilesScreen extends ConsumerStatefulWidget {
  const ProfilesScreen({super.key});

  @override
  ConsumerState<ProfilesScreen> createState() => _ProfilesScreenState();
}

class _ProfilesScreenState extends ConsumerState<ProfilesScreen> {
  Future<void> _addProfile() async {
    final installation = await SupabaseService.getInstallation();
    if (installation == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No Aura found. Please add an Aura first.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    if (!mounted) return;
    final added = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddProfileScreen(installationId: installation['id']),
      ),
    );
    if (added == true && mounted) {
      ref.read(profilesProvider.notifier).refresh();
    }
  }

  void _showProfileDetail(Map<String, dynamic> profile) async {
    final deleted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => _ProfileDetailScreen(profile: profile)),
    );
    if (deleted == true && mounted) {
      ref.read(profilesProvider.notifier).refresh();
    }
  }

  String _profileDisplayName(Map<String, dynamic> profile) {
    final first = profile['first_name'] as String?;
    final last = profile['last_name'] as String?;
    if (first != null && last != null) return '$first $last';
    if (first != null) return first;
    return profile['display_name'] as String? ?? 'Unknown';
  }

  @override
  Widget build(BuildContext context) {
    final profilesAsync = ref.watch(profilesProvider);
    final profiles = profilesAsync.valueOrNull?.map((p) => p.toMap()).toList();
    final loading = profilesAsync.isLoading && profiles == null;

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () => ref.read(profilesProvider.notifier).refresh(),
        color: Colors.white,
        backgroundColor: const Color(0xFF111111),
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(24),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'PROFILES',
                        style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 4,
                          color: Colors.white38,
                        ),
                      ),
                      IconButton(
                        onPressed: _addProfile,
                        icon: const Icon(Icons.add, color: Colors.white),
                        tooltip: 'Add profile',
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (loading)
                    const Center(
                      child: CircularProgressIndicator(
                        color: Colors.white24,
                        strokeWidth: 1,
                      ),
                    )
                  else if (profiles == null || profiles.isEmpty)
                    const Center(
                      child: Text(
                        'No profiles yet',
                        style: TextStyle(color: Colors.white24, fontSize: 13),
                      ),
                    )
                  else
                    ...profiles.map(
                      (profile) => _ProfileCard(
                        profile: profile,
                        displayName: _profileDisplayName(profile),
                        onTap: () => _showProfileDetail(profile),
                      ),
                    ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Profile card
// ─────────────────────────────────────────────────────────────────────────────

class _ProfileCard extends StatelessWidget {
  final Map<String, dynamic> profile;
  final String displayName;
  final VoidCallback onTap;

  const _ProfileCard({
    required this.profile,
    required this.displayName,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final profileId = profile['id'] as String;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF111111),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            ProfileAvatar(
              avatarPath: profile['avatar_path'] as String?,
              avatarUpdatedAt: profile['avatar_updated_at']?.toString(),
              displayName: displayName,
              size: 44,
              fontSize: 18,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w300,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  FutureBuilder<List>(
                    future: Supabase.instance.client
                        .from('vehicles')
                        .select('id')
                        .eq('profile_id', profileId)
                        .eq('is_active', true),
                    builder: (context, snapshot) {
                      final count = snapshot.data?.length ?? 0;
                      final label = !snapshot.hasData
                          ? ''
                          : count == 0
                          ? 'No vehicles'
                          : '$count vehicle${count == 1 ? '' : 's'}';
                      return Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 12,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white24, size: 20),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Profile detail — 4-tab screen
// ─────────────────────────────────────────────────────────────────────────────

class _ProfileDetailScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> profile;

  const _ProfileDetailScreen({required this.profile});

  @override
  ConsumerState<_ProfileDetailScreen> createState() =>
      _ProfileDetailScreenState();
}

class _ProfileDetailScreenState extends ConsumerState<_ProfileDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late List<dynamic> _vehicles;
  bool _deleting = false;

  String get _displayName {
    final first = widget.profile['first_name'] as String?;
    final last = widget.profile['last_name'] as String?;
    if (first != null && last != null) return '$first $last';
    if (first != null) return first;
    return widget.profile['display_name'] as String? ?? 'Profile';
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _vehicles = List.from(widget.profile['vehicles'] as List? ?? []);
    _reloadVehicles();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _deleteProfile() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF111111),
        title: const Text(
          'Delete Profile',
          style: TextStyle(color: Colors.white, fontSize: 15, letterSpacing: 1),
        ),
        content: const Text(
          'This will permanently delete this profile, all its vehicles, and all reference images. This cannot be undone.',
          style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'CANCEL',
              style: TextStyle(color: Colors.white70, letterSpacing: 1),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'DELETE',
              style: TextStyle(color: Colors.redAccent, letterSpacing: 1),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    setState(() => _deleting = true);

    try {
      final client = Supabase.instance.client;
      final profileId = widget.profile['id'] as String;

      final vehiclesResp = await client
          .from('vehicles')
          .select('id')
          .eq('profile_id', profileId);
      final vehicleIds = (vehiclesResp as List)
          .map((v) => v['id'] as String)
          .toList();

      if (vehicleIds.isNotEmpty) {
        final imagesResp = await client
            .from('vehicle_reference_images')
            .select('storage_path')
            .inFilter('vehicle_id', vehicleIds);
        final paths = (imagesResp as List)
            .map((img) => img['storage_path'] as String)
            .toList();

        if (paths.isNotEmpty) {
          await client.storage.from('reference-images').remove(paths);
        }

        await client
            .from('vehicle_reference_images')
            .delete()
            .inFilter('vehicle_id', vehicleIds);

        await client.from('vehicles').delete().eq('profile_id', profileId);
      }

      final avatarPath = widget.profile['avatar_path'] as String?;
      if (avatarPath != null) {
        try {
          await client.storage.from('avatars').remove([avatarPath]);
        } catch (_) {}
      }

      await client.from('profiles').delete().eq('id', profileId);

      if (mounted) {
        ref.read(profilesProvider.notifier).refresh();
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint('Delete profile error: $e');
      if (mounted) {
        setState(() => _deleting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to delete profile. Please try again.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _reloadVehicles() async {
    final profiles = await SupabaseService.getProfiles();
    final updated = profiles.firstWhere(
      (p) => p['id'] == widget.profile['id'],
      orElse: () => widget.profile,
    );
    if (mounted) {
      setState(() {
        _vehicles = List.from(updated['vehicles'] as List? ?? []);
      });
    }
    ref.read(profilesProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          _displayName.toUpperCase(),
          style: const TextStyle(
            fontSize: 13,
            letterSpacing: 4,
            fontWeight: FontWeight.w300,
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _deleting
                ? const Center(
                    child: CircularProgressIndicator(
                      color: Colors.white24,
                      strokeWidth: 1,
                    ),
                  )
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _VehiclesTab(
                        profile: widget.profile,
                        displayName: _displayName,
                        vehicles: _vehicles,
                        onReload: _reloadVehicles,
                        onDeleteProfile: _deleteProfile,
                      ),
                      GreetingsScreen(profile: widget.profile),
                      const _AutomationRulesTab(),
                      RecognitionHistoryScreen(profile: widget.profile),
                    ],
                  ),
          ),
          Container(
            decoration: const BoxDecoration(
              color: Color(0xFF111111),
              border: Border(top: BorderSide(color: Colors.white12)),
            ),
            child: SafeArea(
              top: false,
              child: TabBar(
                controller: _tabController,
                indicatorColor: Colors.white,
                indicatorWeight: 1,
                indicatorSize: TabBarIndicatorSize.label,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white38,
                labelStyle: const TextStyle(fontSize: 10, letterSpacing: 2),
                unselectedLabelStyle: const TextStyle(
                  fontSize: 10,
                  letterSpacing: 2,
                ),
                tabs: const [
                  Tab(text: 'VEHICLES'),
                  Tab(text: 'GREETINGS'),
                  Tab(text: 'RULES'),
                  Tab(text: 'HISTORY'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Vehicles tab
// ─────────────────────────────────────────────────────────────────────────────

class _VehiclesTab extends ConsumerStatefulWidget {
  final Map<String, dynamic> profile;
  final String displayName;
  final List<dynamic> vehicles;
  final VoidCallback onReload;
  final VoidCallback onDeleteProfile;

  const _VehiclesTab({
    required this.profile,
    required this.displayName,
    required this.vehicles,
    required this.onReload,
    required this.onDeleteProfile,
  });

  @override
  ConsumerState<_VehiclesTab> createState() => _VehiclesTabState();
}

class _VehiclesTabState extends ConsumerState<_VehiclesTab> {
  bool _uploadingAvatar = false;
  late Map<String, dynamic> _localProfile;
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _localProfile = Map<String, dynamic>.from(widget.profile);
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
                _pickAndUploadAvatar(ImageSource.camera);
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
                _pickAndUploadAvatar(ImageSource.gallery);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndUploadAvatar(ImageSource source) async {
    try {
      final file = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 512,
      );
      if (file == null || !mounted) return;

      setState(() => _uploadingAvatar = true);

      final client = Supabase.instance.client;
      final profileId = _localProfile['id'] as String;
      final storagePath = 'profiles/$profileId/avatar.jpg';

      final bytes = await File(file.path).readAsBytes();
      await client.storage
          .from('avatars')
          .uploadBinary(
            storagePath,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: true,
            ),
          );
      final now = DateTime.now().toUtc().toIso8601String();
      await client.from('profiles').update({
        'avatar_path': storagePath,
        'avatar_updated_at': now,
      }).eq('id', profileId);

      if (mounted) {
        setState(() {
          _localProfile['avatar_path'] = storagePath;
          _localProfile['avatar_updated_at'] = now;
          _uploadingAvatar = false;
        });
        ref.read(profilesProvider.notifier).refresh();
      }
    } catch (e) {
      debugPrint('Avatar upload error: $e');
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: Stack(
              children: [
                ProfileAvatar(
                  avatarPath: _localProfile['avatar_path'] as String?,
                  avatarUpdatedAt: _localProfile['avatar_updated_at']?.toString(),
                  displayName: widget.displayName,
                  size: 80,
                  fontSize: 32,
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: GestureDetector(
                    onTap: _uploadingAvatar ? null : _showAvatarSourceDialog,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black, width: 2),
                      ),
                      child: _uploadingAvatar
                          ? const Padding(
                              padding: EdgeInsets.all(6),
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: Colors.black,
                              ),
                            )
                          : const Icon(
                              Icons.camera_alt,
                              color: Colors.black,
                              size: 14,
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              widget.profile['greeting'] ?? '',
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 13,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'VEHICLES',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 4,
                  color: Colors.white38,
                ),
              ),
              IconButton(
                onPressed: () async {
                  final added = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => _AddVehicleScreen(
                        profileId: widget.profile['id'],
                        profileName: widget.profile['display_name'] ?? '',
                      ),
                    ),
                  );
                  if (added == true && mounted) widget.onReload();
                },
                icon: const Icon(Icons.add, color: Colors.white, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (widget.vehicles.isEmpty)
            const Text(
              'No vehicles registered',
              style: TextStyle(color: Colors.white24, fontSize: 13),
            )
          else
            ...widget.vehicles.map(
              (v) => _VehicleRow(
                vehicle: v,
                onTap: () async {
                  final deleted = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => VehicleDetailScreen(
                        vehicle: Map<String, dynamic>.from(v),
                      ),
                    ),
                  );
                  if (deleted == true && mounted) widget.onReload();
                },
              ),
            ),
          const SizedBox(height: 48),
          Center(
            child: TextButton(
              onPressed: widget.onDeleteProfile,
              child: const Text(
                'DELETE PROFILE',
                style: TextStyle(
                  color: Colors.redAccent,
                  fontSize: 12,
                  letterSpacing: 2,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Automation rules tab (stub)
// ─────────────────────────────────────────────────────────────────────────────

class _AutomationRulesTab extends StatelessWidget {
  const _AutomationRulesTab();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'Automation rules coming soon',
        style: TextStyle(color: Colors.white38, fontSize: 13),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Vehicle row
// ─────────────────────────────────────────────────────────────────────────────

class _VehicleRow extends StatelessWidget {
  final dynamic vehicle;
  final VoidCallback onTap;

  const _VehicleRow({required this.vehicle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.white12)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.directions_car_outlined,
              color: Colors.white38,
              size: 20,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    vehicle['nickname'] ??
                        '${vehicle['make'] ?? ''} ${vehicle['model'] ?? ''}'
                            .trim(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                  if (vehicle['nickname'] != null)
                    Text(
                      '${vehicle['make'] ?? ''} ${vehicle['model'] ?? ''}'
                          .trim(),
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white12),
              ),
              child: Text(
                vehicle['fingerprint_seeded'] == true ? 'ENROLLED' : 'PENDING',
                style: TextStyle(
                  color: vehicle['fingerprint_seeded'] == true
                      ? Colors.greenAccent
                      : Colors.white24,
                  fontSize: 9,
                  letterSpacing: 1,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: Colors.white24, size: 18),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Add vehicle screen
// ─────────────────────────────────────────────────────────────────────────────

class _AddVehicleScreen extends StatefulWidget {
  final String profileId;
  final String profileName;

  const _AddVehicleScreen({
    required this.profileId,
    required this.profileName,
  });

  @override
  State<_AddVehicleScreen> createState() => _AddVehicleScreenState();
}

class _AddVehicleScreenState extends State<_AddVehicleScreen> {
  final _makeController = TextEditingController();
  final _modelController = TextEditingController();
  final _colourController = TextEditingController();
  final _plateController = TextEditingController();
  final _nicknameController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _makeController.dispose();
    _modelController.dispose();
    _colourController.dispose();
    _plateController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final make = _makeController.text.trim();
    if (make.isEmpty) {
      setState(() => _error = 'Please enter the vehicle make');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await Supabase.instance.client.from('vehicles').insert({
        'profile_id': widget.profileId,
        'make': make,
        'model': _modelController.text.trim().isNotEmpty
            ? _modelController.text.trim()
            : null,
        'colour': _colourController.text.trim().isNotEmpty
            ? _colourController.text.trim()
            : null,
        'registration': _plateController.text.trim().isNotEmpty
            ? _plateController.text.trim()
            : null,
        'nickname': _nicknameController.text.trim().isNotEmpty
            ? _nicknameController.text.trim()
            : null,
        'is_active': true,
      });

      final vehicle = await Supabase.instance.client
          .from('vehicles')
          .select('*')
          .eq('profile_id', widget.profileId)
          .order('created_at', ascending: false)
          .limit(1)
          .single();

      if (mounted) {
        Navigator.pushReplacement<bool, bool>(
          context,
          MaterialPageRoute(
            builder: (_) => VehicleDetailScreen(
              vehicle: Map<String, dynamic>.from(vehicle),
            ),
          ),
          result: true,
        );
      }
    } catch (e) {
      debugPrint('Add vehicle error: $e');
      setState(() {
        _error = 'Failed to save vehicle. Please try again.';
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
          'ADD VEHICLE',
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
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Text(
                'VEHICLE DETAILS',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 3,
                  color: Colors.white24,
                ),
              ),
              const SizedBox(height: 16),
              _buildField(_makeController, 'Make *', 'e.g. Volkswagen'),
              const SizedBox(height: 16),
              _buildField(_modelController, 'Model', 'e.g. Polo GTI'),
              const SizedBox(height: 16),
              _buildField(_colourController, 'Colour', 'e.g. Silver'),
              const SizedBox(height: 16),
              _buildField(
                _plateController,
                'Registration plate',
                'e.g. CA 123 456',
              ),
              const SizedBox(height: 16),
              _buildField(
                _nicknameController,
                'Nickname (optional)',
                'e.g. My GTI',
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
              const SizedBox(height: 32),
              const Text(
                'REFERENCE IMAGES',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 3,
                  color: Colors.white24,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'You can add reference images after saving the vehicle. A minimum of 3 images from different angles is required for fingerprint recognition.',
                style: TextStyle(
                  color: Colors.white24,
                  fontSize: 12,
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField(
    TextEditingController controller,
    String label,
    String hint,
  ) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white38),
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white24),
        enabledBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.white24),
        ),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.white),
        ),
      ),
    );
  }
}
