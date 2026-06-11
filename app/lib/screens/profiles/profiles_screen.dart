// Profiles screen — manage people and their vehicles

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../providers/profile_provider.dart';
import '../../services/supabase_service.dart';
import 'add_profile_screen.dart';
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
      MaterialPageRoute(
        builder: (_) => _ProfileDetailScreen(profile: profile),
      ),
    );
    if (deleted == true && mounted) {
      ref.read(profilesProvider.notifier).refresh();
    }
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

class _ProfileCard extends StatelessWidget {
  final Map<String, dynamic> profile;
  final VoidCallback onTap;

  const _ProfileCard({required this.profile, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final vehicles = profile['vehicles'] as List? ?? [];

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
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white24),
              ),
              child: Center(
                child: Text(
                  (profile['display_name'] as String? ?? '?')
                      .substring(0, 1)
                      .toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w200,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile['display_name'] ?? 'Unknown',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w300,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    vehicles.isEmpty
                        ? 'No vehicles'
                        : '${vehicles.length} vehicle${vehicles.length == 1 ? '' : 's'}',
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
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

class _ProfileDetailScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> profile;

  const _ProfileDetailScreen({required this.profile});

  @override
  ConsumerState<_ProfileDetailScreen> createState() =>
      _ProfileDetailScreenState();
}

class _ProfileDetailScreenState extends ConsumerState<_ProfileDetailScreen> {
  late List<dynamic> _vehicles;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _vehicles = List.from(widget.profile['vehicles'] as List? ?? []);
    _reloadVehicles();
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
          style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'CANCEL',
              style: TextStyle(color: Colors.white38, letterSpacing: 1),
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
          (widget.profile['display_name'] ?? 'Profile').toUpperCase(),
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
            Center(
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24),
                ),
                child: Center(
                  child: Text(
                    (widget.profile['display_name'] as String? ?? '?')
                        .substring(0, 1)
                        .toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.w200,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
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
            const SizedBox(height: 40),

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
                          profileGreeting: widget.profile['greeting'] ?? '',
                        ),
                      ),
                    );
                    if (added == true && mounted) {
                      await _reloadVehicles();
                    }
                  },
                  icon: const Icon(Icons.add, color: Colors.white, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (_vehicles.isEmpty)
              const Text(
                'No vehicles registered',
                style: TextStyle(color: Colors.white24, fontSize: 13),
              )
            else
              ..._vehicles.map(
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
                    if (deleted == true && mounted) {
                      await _reloadVehicles();
                    }
                  },
                ),
              ),

            const SizedBox(height: 48),
            Center(
              child: _deleting
                  ? const CircularProgressIndicator(
                      color: Colors.white24,
                      strokeWidth: 1,
                    )
                  : TextButton(
                      onPressed: _deleteProfile,
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
      ),
    );
  }
}

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

class _AddVehicleScreen extends StatefulWidget {
  final String profileId;
  final String profileName;
  final String profileGreeting;

  const _AddVehicleScreen({
    required this.profileId,
    required this.profileName,
    required this.profileGreeting,
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
  final _greetingController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _greetingController.text = widget.profileGreeting;
  }

  @override
  void dispose() {
    _makeController.dispose();
    _modelController.dispose();
    _colourController.dispose();
    _plateController.dispose();
    _nicknameController.dispose();
    _greetingController.dispose();
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
      final greeting = _greetingController.text.trim().isNotEmpty
          ? _greetingController.text.trim()
          : widget.profileGreeting.isNotEmpty
          ? widget.profileGreeting
          : 'Welcome, ${widget.profileName}';

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
        'owner_name': widget.profileName,
        'owner_greeting': greeting,
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
      body: SafeArea(
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
            const SizedBox(height: 32),
            const Text(
              'GREETING',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 3,
                color: Colors.white24,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Displayed on the mirror when this vehicle is recognised.',
              style: TextStyle(
                color: Colors.white24,
                fontSize: 12,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 16),
            _buildField(
              _greetingController,
              'Greeting',
              'e.g. Welcome home, Kieron!',
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
