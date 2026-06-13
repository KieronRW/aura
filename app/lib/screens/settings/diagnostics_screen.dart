// Diagnostics screen — live device status, CPU, memory, disk

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../providers/installation_provider.dart';

class DiagnosticsScreen extends ConsumerStatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  ConsumerState<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends ConsumerState<DiagnosticsScreen> {
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
        .channel('diagnostics_device_status')
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
    final installation = await ref.read(currentInstallationProvider.future);
    if (installation == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    ref.invalidate(deviceStatusProvider(installation['id']));
    final status = await ref.read(
      deviceStatusProvider(installation['id']).future,
    );
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

  bool _isActuallyOnline(Map<String, dynamic>? status) {
    if (status == null) return false;
    if (status['is_online'] != true) return false;
    final lastSeen = status['last_seen_at'];
    if (lastSeen == null) return false;
    final lastSeenDt = DateTime.parse(lastSeen.toString());
    return DateTime.now().toUtc().difference(lastSeenDt).inSeconds < 45;
  }

  @override
  Widget build(BuildContext context) {
    final isOnline = _isActuallyOnline(_deviceStatus);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'DIAGNOSTICS',
          style: TextStyle(
            fontSize: 13,
            letterSpacing: 4,
            fontWeight: FontWeight.w300,
          ),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadData,
          color: Colors.white,
          backgroundColor: const Color(0xFF111111),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (_loading)
                const Center(
                  child: CircularProgressIndicator(
                    color: Colors.white24,
                    strokeWidth: 1,
                  ),
                )
              else ...[
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
                        value:
                            '${_deviceStatus?['display_clients'] ?? 0} client',
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
                        value:
                            (_deviceStatus?['cpu_percent'] as num?)
                                ?.toDouble() ??
                            0,
                      ),
                      const SizedBox(height: 12),
                      _ResourceRow(
                        label: 'Memory',
                        value:
                            (_deviceStatus?['memory_percent'] as num?)
                                ?.toDouble() ??
                            0,
                      ),
                      const SizedBox(height: 12),
                      _ResourceRow(
                        label: 'Disk',
                        value:
                            (_deviceStatus?['disk_percent'] as num?)
                                ?.toDouble() ??
                            0,
                      ),
                    ],
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
