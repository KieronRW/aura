// Home screen — four tab navigation: Home, Profiles, Visitors, Settings

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/aura_theme.dart';
import '../../widgets/skeleton.dart';
import '../../providers/property_provider.dart';
import '../../providers/installation_provider.dart';
import '../../services/supabase_service.dart';
import '../profiles/profiles_screen.dart';
import '../visitors/visitors_screen.dart';
import '../settings/settings_screen.dart';
import '../aura/aura_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  static void switchToTab(int index) => HomeScreenState._instance?.switchToTab(index);

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  static HomeScreenState? _instance;

  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _instance = this;
  }

  @override
  void dispose() {
    if (_instance == this) _instance = null;
    super.dispose();
  }

  void switchToTab(int index) {
    if (mounted) setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kVoid,
      body: IndexedStack(
        index: _currentIndex,
        children: const [
          _DashboardTab(),
          ProfilesScreen(),
          VisitorsScreen(),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        backgroundColor: kCard,
        selectedItemColor: kVioletText,
        unselectedItemColor: const Color(0x66FFFFFF),
        selectedLabelStyle: kLabel(),
        unselectedLabelStyle: kLabel(),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Profiles',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.people_outline),
            activeIcon: Icon(Icons.people),
            label: 'Visitors',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            activeIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

class _DashboardTab extends ConsumerStatefulWidget {
  const _DashboardTab();

  @override
  ConsumerState<_DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends ConsumerState<_DashboardTab> {
  static List<Map<String, dynamic>>? _cachedProperties;
  static Map<String, List<Map<String, dynamic>>> _cachedInstallations = {};

  List<Map<String, dynamic>> _properties = [];
  final Map<String, List<Map<String, dynamic>>> _propertyInstallations = {};
  final Map<String, Map<String, dynamic>> _statusCache = {};
  final Map<String, Map<String, dynamic>?> _lastEventCache = {};
  bool _loading = true;
  RealtimeChannel? _statusChannel;
  RealtimeChannel? _eventsChannel;
  Timer? _statusTimer;

  late final _authSubscription =
      Supabase.instance.client.auth.onAuthStateChange.listen((data) {
        if (mounted) {
          ref.invalidate(propertiesProvider);
          setState(() {
            _properties = [];
            _propertyInstallations.clear();
            _statusCache.clear();
            _lastEventCache.clear();
            _loading = true;
          });
          _loadData();
        }
      });

  @override
  void initState() {
    super.initState();
    // SWR: pre-populate from static cache so skeleton isn't shown on revisit
    if (_cachedProperties != null) {
      _properties = List.from(_cachedProperties!);
      _propertyInstallations.addAll(_cachedInstallations);
      _loading = false;
    }
    _loadData();
    _subscribeToRealtime();
    _statusTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _refreshStatuses(),
    );
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _authSubscription.cancel();
    _statusChannel?.unsubscribe();
    _eventsChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _refreshStatuses() async {
    final ids = _propertyInstallations.values
        .expand((list) => list)
        .map((i) => i['id'] as String)
        .toList();
    if (ids.isEmpty) return;
    for (final id in ids) {
      ref.invalidate(deviceStatusProvider(id));
    }
    for (final id in ids) {
      final status = await ref.read(deviceStatusProvider(id).future);
      if (mounted && status != null) {
        setState(() => _statusCache[id] = status);
      }
    }
  }

  void _subscribeToRealtime() {
    _statusChannel = Supabase.instance.client
        .channel('device_status_changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'device_status',
          callback: (payload) {
            if (!mounted) return;
            final record = payload.newRecord;
            final id = record['installation_id'] as String?;
            if (id != null && record.isNotEmpty) {
              setState(
                () => _statusCache[id] = Map<String, dynamic>.from(record),
              );
            }
          },
        )
        .subscribe();

    _eventsChannel = Supabase.instance.client
        .channel('recognition_events_home')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'recognition_events',
          callback: (payload) {
            if (!mounted) return;
            final id = payload.newRecord['installation_id'] as String?;
            if (id != null) {
              _refreshLastEvent(id);
              if (_statusCache.containsKey(id)) {
                setState(() {
                  _statusCache[id] = {
                    ..._statusCache[id]!,
                    'current_state': 'recognition',
                  };
                });
              }
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'recognition_events',
          callback: (payload) {
            if (!mounted) return;
            final record = payload.newRecord;
            final id = record['installation_id'] as String?;
            if (id != null && _statusCache.containsKey(id)) {
              if (record['departed_at'] != null) {
                setState(() {
                  _statusCache[id] = {
                    ..._statusCache[id]!,
                    'current_state': 'idle',
                  };
                });
                _refreshLastEvent(id);
              }
            }
          },
        )
        .subscribe();
  }

  Future<void> _refreshLastEvent(String installationId) async {
    final event = await SupabaseService.getLastEventWithOwner(installationId);
    if (mounted) setState(() => _lastEventCache[installationId] = event);
  }

  Future<void> _loadData() async {
    final hasData =
        _propertyInstallations.values.expand((i) => i).isNotEmpty;
    if (!hasData) setState(() => _loading = true);

    final propertyModels = await ref.read(propertiesProvider.future);
    final properties = propertyModels.map((p) => p.toMap()).toList();

    if (!mounted) return;

    for (final property in properties) {
      final installationModels = await ref.read(
        installationsProvider(property['id'] as String).future,
      );
      if (mounted) {
        setState(() {
          _propertyInstallations[property['id'] as String] =
              installationModels.map((i) => i.toMap()).toList();
        });
      }
    }

    if (mounted) {
      setState(() {
        _properties = properties;
        _loading = false;
      });
      _cachedProperties = List.from(properties);
      _cachedInstallations = Map.from(_propertyInstallations);
    }

    for (final property in properties) {
      final installations =
          _propertyInstallations[property['id'] as String] ?? [];
      for (final installation in installations) {
        final id = installation['id'] as String;
        final status = await ref.read(deviceStatusProvider(id).future);
        final lastEvent = await SupabaseService.getLastEventWithOwner(id);
        if (mounted) {
          setState(() {
            if (status != null) _statusCache[id] = status;
            _lastEventCache[id] = lastEvent;
          });
        }
      }
    }
  }

  bool _isActuallyOnline(Map<String, dynamic>? status) {
    if (status == null) return false;
    if (status['is_online'] != true) return false;
    final lastSeen = status['last_seen_at'];
    if (lastSeen == null) return false;
    final lastSeenDt = DateTime.parse(lastSeen.toString());
    return DateTime.now().toUtc().difference(lastSeenDt).inSeconds < 45;
  }

  String _formatLastSeen(Map<String, dynamic>? event) {
    if (event == null) return 'No recent activity';
    final arrivedAt = event['arrived_at'] as String?;
    if (arrivedAt == null) return 'No recent activity';

    String ownerName = '';
    final visitors = event['visitors'];
    if (visitors is Map && visitors['name'] != null) {
      ownerName = visitors['name'] as String;
    } else {
      final make = event['detected_make'] as String?;
      if (make != null && make.isNotEmpty) ownerName = make;
    }

    if (ownerName.isEmpty) return 'No recent activity';

    final dt = DateTime.parse(arrivedAt).toLocal();
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$ownerName at $h:$m';
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(propertiesProvider, (prev, next) {
      if (next.hasValue && prev != next) _loadData();
    });

    return Scaffold(
      backgroundColor: kVoid,
      body: Container(
        decoration: const BoxDecoration(gradient: kBgGradient),
        child: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadData,
          color: kCyan,
          backgroundColor: kCard,
          child: _loading
              ? ListView(
                  padding: const EdgeInsets.all(24),
                  children: const [
                    SkeletonBox(width: 160, height: 20, borderRadius: 4),
                    SizedBox(height: 16),
                    SkeletonCard(height: 80),
                    SizedBox(height: 12),
                    SkeletonCard(height: 80),
                  ],
                )
              : _properties.isEmpty
              ? ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    const SizedBox(height: 48),
                    const Icon(Icons.sensors, color: Color(0x1AFFFFFF), size: 64),
                    const SizedBox(height: 24),
                    Text(
                      'No Aura found',
                      textAlign: TextAlign.center,
                      style: kBody(const Color(0x66FFFFFF)),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Add your Aura from Settings → Manage Auras',
                      textAlign: TextAlign.center,
                      style: kCaption(),
                    ),
                  ],
                )
              : ListView(
                  padding: const EdgeInsets.all(24.0),
                  children: [
                    ..._properties.expand<Widget>((property) {
                      final installations =
                          _propertyInstallations[property['id'] as String] ??
                          [];
                      return [
                        Text(
                          property['name'] as String,
                          style: kScreenTitle(),
                        ),
                        const SizedBox(height: 16),
                        if (installations.isEmpty)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 16),
                            child: Text(
                              'No Auras at this location',
                              style: TextStyle(
                                color: Colors.white24,
                                fontSize: 13,
                              ),
                            ),
                          )
                        else
                          ...installations.map((installation) {
                            final id = installation['id'] as String;
                            final status = _statusCache[id];
                            final online = _isActuallyOnline(status);
                            final lastSeenText =
                                _formatLastSeen(_lastEventCache[id]);

                            return GestureDetector(
                              onTap: () async {
                                await Navigator.push<bool>(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => AuraDetailScreen(
                                      installation: installation,
                                    ),
                                  ),
                                );
                                if (mounted) _loadData();
                              },
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: online ? kCard : kCardDim,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: kCardBorder),
                                ),
                                child: Column(
                                  children: [
                                    Row(
                                      children: [
                                        AnimatedContainer(
                                          duration: const Duration(
                                            milliseconds: 600,
                                          ),
                                          width: 8,
                                          height: 8,
                                          decoration: BoxDecoration(
                                            color: online
                                                ? kOnline
                                                : kError,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            installation['name'] ?? 'Aura',
                                            style: kBody(),
                                          ),
                                        ),
                                        AnimatedSwitcher(
                                          duration: const Duration(
                                            milliseconds: 600,
                                          ),
                                          child: Text(
                                            online ? 'Online' : 'Offline',
                                            key: ValueKey(online),
                                            style: kCaption(online ? kOnlineText : kErrorText),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        const Icon(
                                          Icons.chevron_right,
                                          color: Color(0x40FFFFFF),
                                          size: 18,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        const SizedBox(width: 20),
                                        Text(
                                          'Last Seen:',
                                          style: kCaption(),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            lastSeenText,
                                            style: kCaption(const Color(0x80FFFFFF)),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                        const SizedBox(height: 16),
                      ];
                    }),
                  ],
                ),
        ),
        ),
      ),
    );
  }
}
