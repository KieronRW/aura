// Profiles screen — manage people and their vehicles

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/supabase_service.dart';
import 'add_profile_screen.dart';
import 'vehicle_detail_screen.dart';

class ProfilesScreen extends StatefulWidget {
  const ProfilesScreen({super.key});

  @override
  State<ProfilesScreen> createState() => _ProfilesScreenState();
}

class _ProfilesScreenState extends State<ProfilesScreen> {
  List<Map<String, dynamic>> _profiles = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  Future<void> _loadProfiles() async {
    final profiles = await SupabaseService.getProfiles();
    if (mounted) {
      setState(() {
        _profiles = profiles;
        _loading = false;
      });
    }
  }

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
      _loadProfiles();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _loadProfiles,
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
                  if (_loading)
                    const Center(
                      child: CircularProgressIndicator(
                        color: Colors.white24,
                        strokeWidth: 1,
                      ),
                    )
                  else if (_profiles.isEmpty)
                    const Center(
                      child: Text(
                        'No profiles yet',
                        style: TextStyle(color: Colors.white24, fontSize: 13),
                      ),
                    )
                  else
                    ..._profiles.map(
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

  void _showProfileDetail(Map<String, dynamic> profile) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _ProfileDetailScreen(
          profile: profile,
          onVehicleAdded: _loadProfiles,
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

class _ProfileDetailScreen extends StatefulWidget {
  final Map<String, dynamic> profile;
  final VoidCallback onVehicleAdded;

  const _ProfileDetailScreen({
    required this.profile,
    required this.onVehicleAdded,
  });

  @override
  State<_ProfileDetailScreen> createState() => _ProfileDetailScreenState();
}

class _ProfileDetailScreenState extends State<_ProfileDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final vehicles = widget.profile['vehicles'] as List? ?? [];

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
                    final nav = Navigator.of(context);
                    final added = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            _AddVehicleScreen(profileId: widget.profile['id']),
                      ),
                    );
                    if (added == true && mounted) {
                      widget.onVehicleAdded();
                      nav.pop();
                    }
                  },
                  icon: const Icon(Icons.add, color: Colors.white, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (vehicles.isEmpty)
              const Text(
                'No vehicles registered',
                style: TextStyle(color: Colors.white24, fontSize: 13),
              )
            else
              ...vehicles.map(
                (v) => _VehicleRow(
                  vehicle: v,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => VehicleDetailScreen(
                        vehicle: Map<String, dynamic>.from(v),
                      ),
                    ),
                  ),
                ),
              ),
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
                vehicle['fingerprint_data'] != null ? 'ENROLLED' : 'PENDING',
                style: TextStyle(
                  color: vehicle['fingerprint_data'] != null
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

  const _AddVehicleScreen({required this.profileId});

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

      if (mounted) Navigator.pop(context, true);
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
      textCapitalization: TextCapitalization.words,
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
