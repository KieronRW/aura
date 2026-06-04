// Admin screen — live diagnostics, settings, software updates

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/supabase_service.dart';
import '../auth/login_screen.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  Map<String, dynamic>? _deviceStatus;
  bool _loading = true;
  RealtimeChannel? _statusChannel;

  @override
  void initState() {
    super.initState();
    _loadData();
    _subscribeToRealtime();
  }

  @override
  void dispose() {
    _statusChannel?.unsubscribe();
    super.dispose();
  }

  void _subscribeToRealtime() {
    _statusChannel = Supabase.instance.client
        .channel('admin_device_status')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'device_status',
          callback: (payload) {
            if (mounted) _loadData();
          },
        )
        .subscribe();
  }

  Future<void> _loadData() async {
    final status = await SupabaseService.getDeviceStatus();
    if (mounted) {
      setState(() {
        _deviceStatus = status;
        _loading = false;
      });
    }
  }

  String _formatUptime(dynamic seconds) {
    if (seconds == null) return 'Unknown';
    final s = int.tryParse(seconds.toString()) ?? 0;
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  Future<void> _signOut() async {
    await Supabase.instance.client.auth.signOut();
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOnline = _deviceStatus?['is_online'] == true;

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _loadData,
        color: Colors.white,
        backgroundColor: const Color(0xFF111111),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'ADMIN',
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 4,
                color: Colors.white38,
              ),
            ),
            const SizedBox(height: 32),

            // Mirror status
            const Text(
              'MIRROR STATUS',
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
            else
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF111111),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  children: [
                    _DiagnosticRow(
                      label: 'Status',
                      value: isOnline ? 'Online' : 'Offline',
                      valueColor: isOnline
                          ? Colors.greenAccent
                          : Colors.redAccent,
                    ),
                    _DiagnosticRow(
                      label: 'IP Address',
                      value: _deviceStatus?['local_ip'] ?? '—',
                    ),
                    _DiagnosticRow(
                      label: 'Uptime',
                      value: _formatUptime(_deviceStatus?['uptime_seconds']),
                    ),
                    _DiagnosticRow(
                      label: 'Software',
                      value: _deviceStatus?['software_version'] ?? '—',
                    ),
                    _DiagnosticRow(
                      label: 'Camera',
                      value: _deviceStatus?['camera_ok'] == true
                          ? 'OK'
                          : 'Error',
                      valueColor: _deviceStatus?['camera_ok'] == true
                          ? Colors.greenAccent
                          : Colors.redAccent,
                    ),
                    _DiagnosticRow(
                      label: 'Display',
                      value: '${_deviceStatus?['display_clients'] ?? 0} client',
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 24),

            // System resources
            const Text(
              'SYSTEM RESOURCES',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 3,
                color: Colors.white24,
              ),
            ),
            const SizedBox(height: 12),

            if (!_loading)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF111111),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  children: [
                    _ResourceRow(
                      label: 'CPU',
                      value: _deviceStatus?['cpu_percent']?.toDouble() ?? 0,
                    ),
                    const SizedBox(height: 12),
                    _ResourceRow(
                      label: 'Memory',
                      value: _deviceStatus?['memory_percent']?.toDouble() ?? 0,
                    ),
                    const SizedBox(height: 12),
                    _ResourceRow(
                      label: 'Disk',
                      value: _deviceStatus?['disk_percent']?.toDouble() ?? 0,
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 32),

            // Sign out
            GestureDetector(
              onTap: _signOut,
              child: const Text(
                'SIGN OUT',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 4,
                  color: Colors.white38,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiagnosticRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _DiagnosticRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white38, fontSize: 13),
          ),
          Text(
            value,
            style: TextStyle(color: valueColor ?? Colors.white, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _ResourceRow extends StatelessWidget {
  final String label;
  final double value;

  const _ResourceRow({required this.label, required this.value});

  Color _barColor(double v) {
    if (v > 80) return Colors.redAccent;
    if (v > 60) return Colors.orangeAccent;
    return Colors.greenAccent;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 64,
          child: Text(
            label,
            style: const TextStyle(color: Colors.white38, fontSize: 13),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: value / 100,
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation<Color>(_barColor(value)),
              minHeight: 4,
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 40,
          child: Text(
            '${value.toStringAsFixed(0)}%',
            textAlign: TextAlign.right,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
      ],
    );
  }
}
