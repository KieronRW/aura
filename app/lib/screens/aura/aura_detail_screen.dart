// Aura Detail screen — status, activity, settings for a specific Aura

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/supabase_service.dart';

class AuraDetailScreen extends StatefulWidget {
  final Map<String, dynamic> installation;

  const AuraDetailScreen({super.key, required this.installation});

  @override
  State<AuraDetailScreen> createState() => _AuraDetailScreenState();
}

class _AuraDetailScreenState extends State<AuraDetailScreen> {
  Map<String, dynamic>? _deviceStatus;
  List<Map<String, dynamic>> _recentEvents = [];
  bool _loading = true;
  RealtimeChannel? _statusChannel;
  RealtimeChannel? _eventsChannel;

  @override
  void initState() {
    super.initState();
    _loadData();
    _subscribeToRealtime();
  }

  @override
  void dispose() {
    _statusChannel?.unsubscribe();
    _eventsChannel?.unsubscribe();
    super.dispose();
  }

  void _subscribeToRealtime() {
    _statusChannel = Supabase.instance.client
        .channel('aura_detail_status')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'device_status',
          callback: (payload) {
            if (mounted) _loadData();
          },
        )
        .subscribe();

    _eventsChannel = Supabase.instance.client
        .channel('aura_detail_events')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'recognition_events',
          callback: (payload) {
            if (mounted) _loadData();
          },
        )
        .subscribe();
  }

  Future<void> _loadData() async {
    final status = await SupabaseService.getDeviceStatus();
    final events = await SupabaseService.getRecentEvents();
    if (mounted) {
      setState(() {
        _deviceStatus = status;
        _recentEvents = events;
        _loading = false;
      });
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

  void _showRenameDialog() {
    final controller = TextEditingController(
      text: widget.installation['name'] ?? '',
    );
    final nav = Navigator.of(context);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF111111),
        title: const Text(
          'RENAME AURA',
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
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'e.g. Front Gate, Garage',
            hintStyle: TextStyle(color: Colors.white24),
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
                    .from('installations')
                    .update({'name': name})
                    .eq('id', widget.installation['id']);
              }
              nav.pop(name);
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

  void _showReleaseDialog() {
    final nav = Navigator.of(context);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF111111),
        title: const Text(
          'RELEASE AURA',
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            letterSpacing: 3,
            fontWeight: FontWeight.w300,
          ),
        ),
        content: const Text(
          'This will unlink this Aura from your account. It can then be claimed by another user.',
          style: TextStyle(color: Colors.white38, fontSize: 13, height: 1.6),
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
                  .from('installations')
                  .update({
                    'status': 'unclaimed',
                    'claimed_at': null,
                    'claimed_by': null,
                    'property_id': null,
                  })
                  .eq('id', widget.installation['id']);
              nav.pop();
              nav.pop(true);
            },
            child: const Text(
              'RELEASE',
              style: TextStyle(color: Colors.redAccent, letterSpacing: 2),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isOnline = _isActuallyOnline(_deviceStatus);
    final auraName = widget.installation['name'] ?? 'Aura';

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          auraName.toUpperCase(),
          style: const TextStyle(
            fontSize: 13,
            letterSpacing: 4,
            fontWeight: FontWeight.w300,
          ),
        ),
        actions: [
          IconButton(
            onPressed: _showRenameDialog,
            icon: const Icon(Icons.edit_outlined, size: 20),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadData,
          color: Colors.white,
          backgroundColor: const Color(0xFF111111),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              // Status card
              Container(
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
                        color: isOnline ? Colors.greenAccent : Colors.redAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isOnline ? 'Online' : 'Offline',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                          ),
                          if (isOnline)
                            Text(
                              _deviceStatus?['local_ip'] ?? '',
                              style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (isOnline)
                      Text(
                        (_deviceStatus?['current_state'] ?? '')
                            .toString()
                            .toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 10,
                          letterSpacing: 2,
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Settings section
              const Text(
                'AURA SETTINGS',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 3,
                  color: Colors.white24,
                ),
              ),
              const SizedBox(height: 12),
              _SettingsRow(
                icon: Icons.brightness_6_outlined,
                title: 'Display',
                subtitle: 'Brightness, orientation',
                onTap: () {},
              ),
              _SettingsRow(
                icon: Icons.camera_outlined,
                title: 'Camera',
                subtitle: 'Sensitivity, quality',
                onTap: () {},
              ),
              _SettingsRow(
                icon: Icons.wifi_outlined,
                title: 'Network',
                subtitle: _deviceStatus?['local_ip'] ?? 'DHCP',
                onTap: () {},
              ),
              _SettingsRow(
                icon: Icons.tune_outlined,
                title: 'Recognition',
                subtitle: 'Confidence thresholds',
                onTap: () {},
              ),

              const SizedBox(height: 32),

              // Recent activity
              const Text(
                'RECENT ACTIVITY',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 3,
                  color: Colors.white24,
                ),
              ),
              const SizedBox(height: 12),

              if (_loading)
                const Center(
                  child: CircularProgressIndicator(
                    color: Colors.white24,
                    strokeWidth: 1,
                  ),
                )
              else if (_recentEvents.isEmpty)
                const Text(
                  'No recent activity',
                  style: TextStyle(color: Colors.white24, fontSize: 13),
                )
              else
                ..._recentEvents
                    .take(10)
                    .map(
                      (event) => _EventRow(
                        make: event['detected_make'] ?? 'Unknown',
                        model: event['detected_model'],
                        time: _formatTime(event['arrived_at']),
                        date: _formatDate(event['arrived_at']),
                        method: event['method'] ?? '',
                      ),
                    ),

              const SizedBox(height: 32),

              // Danger zone
              const Text(
                'DANGER ZONE',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 3,
                  color: Colors.white24,
                ),
              ),
              const SizedBox(height: 12),
              _SettingsRow(
                icon: Icons.link_off,
                title: 'Release Aura',
                subtitle: 'Unlink this Aura from your account',
                destructive: true,
                onTap: _showReleaseDialog,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool destructive;
  final VoidCallback onTap;

  const _SettingsRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.destructive = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.white12)),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: destructive ? Colors.redAccent : Colors.white38,
              size: 20,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: destructive ? Colors.redAccent : Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
            if (!destructive)
              const Icon(Icons.chevron_right, color: Colors.white24, size: 18),
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
      padding: const EdgeInsets.symmetric(vertical: 14),
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
                  style: const TextStyle(color: Colors.white, fontSize: 13),
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
            child: Text(
              model != null ? '$make · $model' : make,
              style: const TextStyle(color: Colors.white, fontSize: 13),
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
