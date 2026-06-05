// Home screen — four tab navigation: Home, Profiles, Automations, Settings

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/supabase_service.dart';
import '../profiles/profiles_screen.dart';
import '../automations/automations_screen.dart';
import '../admin/admin_screen.dart';
import '../onboarding/discover_mirror_screen.dart';
import '../aura/aura_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    _DashboardTab(),
    ProfilesScreen(),
    AutomationsScreen(),
    AdminScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        backgroundColor: const Color(0xFF111111),
        selectedItemColor: Colors.white,
        unselectedItemColor: Colors.white38,
        selectedLabelStyle: const TextStyle(letterSpacing: 2, fontSize: 10),
        unselectedLabelStyle: const TextStyle(letterSpacing: 2, fontSize: 10),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'HOME',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'PROFILES',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bolt_outlined),
            activeIcon: Icon(Icons.bolt),
            label: 'AUTOMATIONS',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            activeIcon: Icon(Icons.settings),
            label: 'SETTINGS',
          ),
        ],
      ),
    );
  }
}

class _DashboardTab extends StatefulWidget {
  const _DashboardTab();

  @override
  State<_DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<_DashboardTab> {
  List<Map<String, dynamic>> _properties = [];
  Map<String, dynamic>? _selectedProperty;
  List<Map<String, dynamic>> _installations = [];
  Map<String, dynamic>? _deviceStatus;
  List<Map<String, dynamic>> _recentEvents = [];
  bool _loading = true;
  RealtimeChannel? _statusChannel;
  RealtimeChannel? _eventsChannel;

  late final _authSubscription = Supabase.instance.client.auth.onAuthStateChange
      .listen((data) {
        if (mounted) {
          setState(() {
            _properties = [];
            _selectedProperty = null;
            _installations = [];
            _deviceStatus = null;
            _recentEvents = [];
            _loading = true;
          });
          _loadData();
        }
      });

  @override
  void initState() {
    super.initState();
    _loadData();
    _subscribeToRealtime();
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    _statusChannel?.unsubscribe();
    _eventsChannel?.unsubscribe();
    super.dispose();
  }

  void _subscribeToRealtime() {
    _statusChannel = Supabase.instance.client
        .channel('device_status_changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'device_status',
          callback: (payload) {
            if (mounted) _loadInstallations();
          },
        )
        .subscribe();

    _eventsChannel = Supabase.instance.client
        .channel('recognition_events_changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'recognition_events',
          callback: (payload) {
            if (mounted) _loadInstallations();
          },
        )
        .subscribe();
  }

  Future<void> _loadData() async {
    final properties = await SupabaseService.getProperties();
    if (mounted) {
      setState(() {
        _properties = properties;
        _selectedProperty = properties.isNotEmpty ? properties.first : null;
      });
      await _loadInstallations();
    }
  }

  Future<void> _loadInstallations() async {
    if (_selectedProperty == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    final installations = await SupabaseService.getInstallationsByProperty(
      _selectedProperty!['id'],
    );

    // Get device status for first installation
    Map<String, dynamic>? status;
    List<Map<String, dynamic>> events = [];

    if (installations.isNotEmpty) {
      final installation = installations.first;
      status = await SupabaseService.getDeviceStatusById(installation['id']);
      events = await SupabaseService.getRecentEventsByInstallation(
        installation['id'],
      );
    }

    if (mounted) {
      setState(() {
        _installations = installations;
        _deviceStatus = status;
        _recentEvents = events;
        _loading = false;
      });
    }
  }

  void _showPropertySelector() {
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
            ..._properties.map(
              (property) => ListTile(
                title: Text(
                  property['name'],
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w300,
                  ),
                ),
                trailing: _selectedProperty?['id'] == property['id']
                    ? const Icon(Icons.check, color: Colors.white, size: 18)
                    : null,
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _selectedProperty = property;
                    _loading = true;
                  });
                  _loadInstallations();
                },
              ),
            ),
            const Divider(color: Colors.white12),
            ListTile(
              leading: const Icon(Icons.add, color: Colors.white38, size: 20),
              title: const Text(
                'Add Location',
                style: TextStyle(color: Colors.white38, fontSize: 14),
              ),
              onTap: () {
                Navigator.pop(context);
                // TODO: navigate to add location screen
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  bool _isActuallyOnline(Map<String, dynamic>? status) {
    if (status == null) return false;
    if (status['is_online'] != true) return false;
    final lastSeen = status['last_seen_at'];
    if (lastSeen == null) return false;
    final lastSeenDt = DateTime.parse(lastSeen.toString());
    return DateTime.now().toUtc().difference(lastSeenDt).inSeconds < 45;
  }

  String _formatTime(String? isoString) {
    if (isoString == null) return '';
    final dt = DateTime.parse(isoString).toLocal();
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _formatDate(String? isoString) {
    if (isoString == null) return '';
    final dt = DateTime.parse(isoString).toLocal();
    final now = DateTime.now();
    if (dt.day == now.day && dt.month == now.month) return 'Today';
    if (dt.day == now.day - 1 && dt.month == now.month) return 'Yesterday';
    return '${dt.day}/${dt.month}';
  }

  Widget _buildEmptyState() {
    return Column(
      children: [
        const SizedBox(height: 48),
        const Icon(Icons.sensors, color: Colors.white12, size: 64),
        const SizedBox(height: 24),
        const Text(
          'No Aura found',
          style: TextStyle(
            color: Colors.white38,
            fontSize: 15,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Add your Aura to get started',
          style: TextStyle(color: Colors.white24, fontSize: 13),
        ),
        const SizedBox(height: 32),
        OutlinedButton(
          onPressed: () async {
            final added = await Navigator.push<bool>(
              context,
              MaterialPageRoute(builder: (_) => const DiscoverMirrorScreen()),
            );
            if (added == true && mounted) {
              setState(() => _loading = true);
              _loadData();
            }
          },
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: Colors.white24),
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.zero,
            ),
          ),
          child: const Text(
            'ADD AURA',
            style: TextStyle(letterSpacing: 4, fontSize: 12),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final propertyName = _selectedProperty?['name'] ?? 'AURA';

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _loadData,
        color: Colors.white,
        backgroundColor: const Color(0xFF111111),
        child: ListView(
          padding: const EdgeInsets.all(24.0),
          children: [
            // Property selector header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GestureDetector(
                  onTap: _properties.length > 1 ? _showPropertySelector : null,
                  child: Row(
                    children: [
                      Text(
                        propertyName.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w200,
                          letterSpacing: 6,
                          color: Colors.white,
                        ),
                      ),
                      if (_properties.length > 1) ...[
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.keyboard_arrow_down,
                          color: Colors.white38,
                          size: 20,
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () async {
                    final added = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const DiscoverMirrorScreen(),
                      ),
                    );
                    if (added == true && mounted) {
                      setState(() => _loading = true);
                      _loadData();
                    }
                  },
                  icon: const Icon(Icons.add, color: Colors.white, size: 22),
                ),
              ],
            ),

            const SizedBox(height: 32),

            if (_loading)
              const Center(
                child: CircularProgressIndicator(
                  color: Colors.white24,
                  strokeWidth: 1,
                ),
              )
            else if (_installations.isEmpty)
              _buildEmptyState()
            else
              ..._installations.map((installation) {
                final status = installation['id'] == _installations.first['id']
                    ? _deviceStatus
                    : null;
                final online = _isActuallyOnline(status);
                return GestureDetector(
                  onTap: () async {
                    final result = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            AuraDetailScreen(installation: installation),
                      ),
                    );
                    if (result == true && mounted) {
                      setState(() => _loading = true);
                      _loadData();
                    }
                  },
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
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: online
                                ? Colors.greenAccent
                                : Colors.redAccent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                installation['name'] ?? 'Aura',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  letterSpacing: 1,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                online
                                    ? 'Online · ${status?['local_ip'] ?? ''}'
                                    : 'Offline',
                                style: const TextStyle(
                                  color: Colors.white38,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (online)
                          Text(
                            (status?['current_state'] ?? '')
                                .toString()
                                .toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 10,
                              letterSpacing: 2,
                            ),
                          ),
                        const SizedBox(width: 8),
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

            const SizedBox(height: 32),

            if (_installations.isNotEmpty) ...[
              const Text(
                'RECENT ACTIVITY',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 4,
                  color: Colors.white38,
                ),
              ),
              const SizedBox(height: 16),
              if (_recentEvents.isEmpty)
                const Center(
                  child: Text(
                    'No recent activity',
                    style: TextStyle(color: Colors.white24, fontSize: 13),
                  ),
                )
              else
                ..._recentEvents.map(
                  (event) => _EventRow(
                    make: event['detected_make'] ?? 'Unknown vehicle',
                    model: event['detected_model'],
                    time: _formatTime(event['arrived_at']),
                    date: _formatDate(event['arrived_at']),
                    method: event['method'] ?? '',
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  final String make;
  final String? model;
  final String time;
  final String date;
  final String method;

  const _EventRow({
    required this.make,
    required this.model,
    required this.time,
    required this.date,
    required this.method,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white12)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  time,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w300,
                  ),
                ),
                Text(
                  date,
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  model != null ? '$make · $model' : make,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'arrived',
                  style: TextStyle(color: Colors.white38, fontSize: 11),
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
              method.toUpperCase(),
              style: const TextStyle(
                color: Colors.white38,
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
