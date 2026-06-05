// Home screen — four tab navigation: Home, Profiles, Automations, Settings

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/supabase_service.dart';
import '../profiles/profiles_screen.dart';
import '../automations/automations_screen.dart';
import '../settings/settings_screen.dart';
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
    SettingsScreen(),
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
  final Map<String, Map<String, dynamic>> _statusCache = {};
  bool _loading = true;
  bool _backgroundRefreshing = false;
  RealtimeChannel? _statusChannel;

  late final _authSubscription = Supabase.instance.client.auth.onAuthStateChange
      .listen((data) {
        if (mounted) {
          setState(() {
            _properties = [];
            _selectedProperty = null;
            _installations = [];
            _statusCache.clear();
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
            if (mounted) _refreshStatusInBackground();
          },
        )
        .subscribe();
  }

  Future<void> _loadData() async {
    // Only show loading spinner on first load — subsequent refreshes use cache
    if (_installations.isEmpty) {
      setState(() => _loading = true);
    }

    final properties = await SupabaseService.getProperties();

    if (mounted) {
      final selected = _selectedProperty != null
          ? properties.firstWhere(
              (p) => p['id'] == _selectedProperty!['id'],
              orElse: () => properties.isNotEmpty ? properties.first : {},
            )
          : (properties.isNotEmpty ? properties.first : null);

      setState(() {
        _properties = properties;
        _selectedProperty = selected != null && (selected as Map).isNotEmpty
            ? selected
            : null;
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

    if (mounted) {
      setState(() {
        _installations = installations;
        _loading = false;
      });
    }

    // Load status for each installation into cache
    for (final installation in installations) {
      final status = await SupabaseService.getDeviceStatusById(
        installation['id'],
      );
      if (mounted && status != null) {
        setState(() {
          _statusCache[installation['id']] = status;
        });
      }
    }
  }

  Future<void> _refreshStatusInBackground() async {
    if (_backgroundRefreshing) return;
    _backgroundRefreshing = true;
    for (final installation in _installations) {
      final status = await SupabaseService.getDeviceStatusById(
        installation['id'],
      );
      if (mounted && status != null) {
        setState(() {
          _statusCache[installation['id']] = status;
        });
      }
    }
    _backgroundRefreshing = false;
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
                    _installations = [];
                    _statusCache.clear();
                    _loading = true;
                  });
                  _loadInstallations();
                },
              ),
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
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final propertyName = _selectedProperty?['name'] ?? 'AURA';

    return Scaffold(
      backgroundColor: Colors.black,
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final added = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  DiscoverMirrorScreen(propertyId: _selectedProperty?['id']),
            ),
          );
          if (added == true && mounted) {
            _loadData();
          }
        },
        backgroundColor: const Color(0xFF222222),
        foregroundColor: Colors.white,
        elevation: 4,
        child: const Icon(Icons.camera_alt_outlined),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadData,
          color: Colors.white,
          backgroundColor: const Color(0xFF111111),
          child: ListView(
            padding: const EdgeInsets.all(24.0),
            children: [
              // Header
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
                  final status = _statusCache[installation['id']];
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
            ],
          ),
        ),
      ),
    );
  }
}
