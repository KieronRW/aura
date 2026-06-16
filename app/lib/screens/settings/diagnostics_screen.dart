// Diagnostics screen — live device status, CPU, memory, disk, and remote log viewer

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../providers/installation_provider.dart';
import '../../services/supabase_service.dart';

class DiagnosticsScreen extends ConsumerStatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  ConsumerState<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends ConsumerState<DiagnosticsScreen> {
  Map<String, dynamic>? _deviceStatus;
  bool _loading = true;
  RealtimeChannel? _statusChannel;

  List<Map<String, dynamic>> _logs = [];
  bool _logsLoading = true;
  String? _selectedSeverity; // null = ALL
  String? _installationId;
  Timer? _logsTimer;

  @override
  void initState() {
    super.initState();
    _loadData();
    _subscribeToRealtime();
    _logsTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _loadLogs(),
    );
  }

  @override
  void dispose() {
    _statusChannel?.unsubscribe();
    _logsTimer?.cancel();
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
    _installationId = installation['id'] as String?;
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
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    final id = _installationId;
    if (id == null) return;
    final logs = await SupabaseService.getRecentDiagnosticLogs(
      id,
      limit: 50,
      severity: _selectedSeverity,
    );
    if (mounted) {
      setState(() {
        _logs = logs;
        _logsLoading = false;
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

  String _relativeTime(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final diff = DateTime.now().toUtc().difference(dt.toUtc());
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hr ago';
    return '${diff.inDays}d ago';
  }

  Color _severityColor(String? severity) {
    switch (severity) {
      case 'critical':
        return Colors.redAccent;
      case 'error':
        return Colors.redAccent;
      case 'warning':
        return Colors.amberAccent;
      case 'info':
        return Colors.white;
      default:
        return Colors.white38;
    }
  }

  bool _severityBold(String? severity) =>
      severity == 'critical' || severity == 'error';

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
                      const SizedBox(height: 12),
                      _TempRow(
                        tempC: (_deviceStatus?['cpu_temp_c'] as num?)
                            ?.toDouble(),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                // Recent logs header
                const Text(
                  'RECENT LOGS',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 3,
                    color: Colors.white24,
                  ),
                ),
                const SizedBox(height: 12),

                // Severity filter chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _FilterChip(
                        label: 'ALL',
                        selected: _selectedSeverity == null,
                        onTap: () {
                          setState(() {
                            _selectedSeverity = null;
                            _logsLoading = true;
                          });
                          _loadLogs();
                        },
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: 'INFO',
                        selected: _selectedSeverity == 'info',
                        onTap: () {
                          setState(() {
                            _selectedSeverity = 'info';
                            _logsLoading = true;
                          });
                          _loadLogs();
                        },
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: 'WARNING',
                        selected: _selectedSeverity == 'warning',
                        onTap: () {
                          setState(() {
                            _selectedSeverity = 'warning';
                            _logsLoading = true;
                          });
                          _loadLogs();
                        },
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: 'ERROR',
                        selected: _selectedSeverity == 'error',
                        onTap: () {
                          setState(() {
                            _selectedSeverity = 'error';
                            _logsLoading = true;
                          });
                          _loadLogs();
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Log list
                if (_logsLoading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(
                        color: Colors.white24,
                        strokeWidth: 1,
                      ),
                    ),
                  )
                else if (_logs.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        'No logs found',
                        style: TextStyle(color: Colors.white24, fontSize: 13),
                      ),
                    ),
                  )
                else
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF111111),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Column(
                      children: _logs.asMap().entries.map((entry) {
                        final i = entry.key;
                        final log = entry.value;
                        final severity = log['severity'] as String?;
                        final category = (log['category'] as String? ?? '').toUpperCase();
                        final message = log['message'] as String? ?? '';
                        final ts = _relativeTime(log['created_at'] as String?);
                        return Column(
                          children: [
                            if (i > 0)
                              const Divider(height: 1, color: Colors.white12),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Severity badge
                                  Container(
                                    width: 7,
                                    height: 7,
                                    margin: const EdgeInsets.only(top: 4, right: 10),
                                    decoration: BoxDecoration(
                                      color: _severityColor(severity),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              category,
                                              style: const TextStyle(
                                                fontSize: 9,
                                                letterSpacing: 1.5,
                                                color: Colors.white24,
                                              ),
                                            ),
                                            const Spacer(),
                                            Text(
                                              ts,
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: Colors.white24,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          message,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: _severityColor(severity),
                                            fontWeight: _severityBold(severity)
                                                ? FontWeight.w600
                                                : FontWeight.normal,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),

                const SizedBox(height: 24),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          border: Border.all(
            color: selected ? Colors.white : Colors.white24,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            letterSpacing: 1.5,
            color: selected ? Colors.black : Colors.white38,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
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

class _TempRow extends StatelessWidget {
  final double? tempC;

  const _TempRow({this.tempC});

  Color _tempColor(double t) {
    if (t >= 80) return Colors.redAccent;
    if (t >= 70) return Colors.orangeAccent;
    return Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    final label = 'CPU TEMP';
    if (tempC == null) {
      return Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white38, fontSize: 13),
            ),
          ),
          const Text('—', style: TextStyle(color: Colors.white38, fontSize: 13)),
        ],
      );
    }
    return Row(
      children: [
        SizedBox(
          width: 64,
          child: Text(
            label,
            style: const TextStyle(color: Colors.white38, fontSize: 13),
          ),
        ),
        Text(
          '${tempC!.toStringAsFixed(1)}°C',
          style: TextStyle(color: _tempColor(tempC!), fontSize: 13),
        ),
      ],
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
