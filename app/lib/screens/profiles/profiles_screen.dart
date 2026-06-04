// Profiles screen — manage people and their vehicles

import 'package:flutter/material.dart';
import '../../services/supabase_service.dart';

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
                        onPressed: () {},
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
                        onTap: () => _showProfileDetail(context, profile),
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

  void _showProfileDetail(BuildContext context, Map<String, dynamic> profile) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _ProfileDetailScreen(profile: profile)),
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
            // Avatar
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
            // Name and vehicle count
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

class _ProfileDetailScreen extends StatelessWidget {
  final Map<String, dynamic> profile;

  const _ProfileDetailScreen({required this.profile});

  @override
  Widget build(BuildContext context) {
    final vehicles = profile['vehicles'] as List? ?? [];

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          profile['display_name'] ?? 'Profile',
          style: const TextStyle(
            fontSize: 14,
            letterSpacing: 3,
            fontWeight: FontWeight.w300,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            // Profile header
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
                    (profile['display_name'] as String? ?? '?')
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
                profile['greeting'] ?? '',
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
            const SizedBox(height: 40),

            // Vehicles section
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
                  onPressed: () {},
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
              ...vehicles.map((v) => _VehicleRow(vehicle: v)),
          ],
        ),
      ),
    );
  }
}

class _VehicleRow extends StatelessWidget {
  final dynamic vehicle;

  const _VehicleRow({required this.vehicle});

  @override
  Widget build(BuildContext context) {
    return Container(
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
                      '${vehicle['make']} ${vehicle['model'] ?? ''}'.trim(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w300,
                  ),
                ),
                if (vehicle['nickname'] != null)
                  Text(
                    '${vehicle['make']} ${vehicle['model'] ?? ''}'.trim(),
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
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
        ],
      ),
    );
  }
}
