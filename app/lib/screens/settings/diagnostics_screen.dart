// Diagnostics screen (Level 2) — live device status, system resources, remote logs

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../providers/installation_provider.dart';
import '../../services/supabase_service.dart';
import '../../theme/aura_theme.dart';
import '../../widgets/skeleton.dart';

class DiagnosticsScreen extends ConsumerStatefulWidget {
  final String installationId;

  const DiagnosticsScreen({super.key, required this.installationId});

  @override
  ConsumerState<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends ConsumerState<DiagnosticsScreen> {
  static final _statusSwr = <String, Map<String, dynamic>?>{};
  static final _logsSwr = <String, List<Map<String, dynamic>>>{};

  Map<String, dynamic>? _deviceStatus;
  bool _loading = true;
  RealtimeChannel? _statusChannel;

  List<Map<String, dynamic>> _logs = [];
  bool _logsLoading = true;
  String? _selectedSeverity; // null = ALL
  Timer? _logsTimer;

  @override
  void initState() {
    super.initState();
    // SWR: pre-populate from static cache so skeleton isn't shown on revisit
    final id = widget.installationId;
    if (_statusSwr.containsKey(id)) {
      _deviceStatus = _statusSwr[id];
      _logs = _logsSwr[id] ?? [];
      _loading = false;
      _logsLoading = false;
    }
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
    ref.invalidate(deviceStatusProvider(widget.installationId));
    final status = await ref.read(
      deviceStatusProvider(widget.installationId).future,
    );
    if (mounted) {
      setState(() {
        _deviceStatus = status;
        _loading = false;
      });
      _statusSwr[widget.installationId] = status;
    }
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    final logs = await SupabaseService.getRecentDiagnosticLogs(
      widget.installationId,
      limit: 50,
      severity: _selectedSeverity,
    );
    if (mounted) {
      setState(() {
        _logs = logs;
        _logsLoading = false;
      });
      _logsSwr[widget.installationId] = logs;
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
        return kErrorText;
      case 'error':
        return kErrorText;
      case 'warning':
        return kWarningText;
      case 'info':
        return Colors.white;
      default:
        return const Color(0x80FFFFFF);
    }
  }

  Color _severityDotColor(String? severity) {
    switch (severity) {
      case 'critical':
        return kError;
      case 'error':
        return kError;
      case 'warning':
        return kWarning;
      case 'info':
        return kOnline;
      default:
        return const Color(0x40FFFFFF);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOnline = _isActuallyOnline(_deviceStatus);

    return Scaffold(
      backgroundColor: kVoid,
      appBar: AppBar(
        backgroundColor: kVoid,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'DIAGNOSTICS',
          style: kHeading(),
        ),
      ),
      body: SafeArea(
        child: Container(
          decoration: const BoxDecoration(gradient: kBgGradient),
          child: RefreshIndicator(
          onRefresh: _loadData,
          color: Colors.white,
          backgroundColor: kCard,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (_loading)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: kCard,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: kCardBorder),
                  ),
                  child: Column(
                    children: const [
                      SkeletonSettingsRow(),
                      SizedBox(height: 8),
                      SkeletonSettingsRow(),
                      SizedBox(height: 8),
                      SkeletonSettingsRow(),
                      SizedBox(height: 8),
                      SkeletonSettingsRow(),
                      SizedBox(height: 8),
                      SkeletonSettingsRow(),
                      SizedBox(height: 8),
                      SkeletonSettingsRow(),
                    ],
                  ),
                )
              else ...[
                // Mirror status
                Text(
                  'MIRROR STATUS',
                  style: kLabel(),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: kCard,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: kCardBorder),
                  ),
                  child: Column(
                    children: [
                      _DiagnosticRow(
                        label: 'Status',
                        value: isOnline ? 'Online' : 'Offline',
                        valueColor: isOnline
                            ? kOnlineText
                            : kErrorText,
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
                            ? kOnlineText
                            : kErrorText,
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
                Text(
                  'SYSTEM RESOURCES',
                  style: kLabel(),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: kCard,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: kCardBorder),
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
                Text(
                  'RECENT LOGS',
                  style: kLabel(),
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
                  Column(
                    children: List.generate(
                      4,
                      (i) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: i > 0
                            ? const BoxDecoration(
                                border: Border(top: BorderSide(color: Color(0xFF1C1C1C))),
                              )
                            : null,
                        child: Row(
                          children: const [
                            SkeletonBox(width: 7, height: 7, borderRadius: 4),
                            SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SkeletonBox(width: 60, height: 9, borderRadius: 3),
                                  SizedBox(height: 4),
                                  SkeletonBox(width: 200, height: 12, borderRadius: 4),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else if (_logs.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        'No logs found',
                        style: kCaption(),
                      ),
                    ),
                  )
                else
                  Container(
                    decoration: BoxDecoration(
                      color: kCardDim,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: kCardBorder),
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
                              const Divider(height: 1, color: kRowDivider),
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
                                      color: _severityDotColor(severity),
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
                                              style: kMono(const Color(0x40FFFFFF)),
                                            ),
                                            const Spacer(),
                                            Text(
                                              ts,
                                              style: kMono(const Color(0x40FFFFFF)),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          message,
                                          style: kMono(_severityColor(severity)),
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
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? Colors.white : kCardBorder,
          ),
        ),
        child: Text(
          label,
          style: selected
              ? kLabel(Colors.black)
              : kLabel(),
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
            style: kCaption(),
          ),
          Text(
            value,
            style: valueColor != null ? kMono(valueColor!) : kMono(),
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
    if (t >= 80) return kErrorText;
    if (t >= 70) return kWarningText;
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
              style: kCaption(),
            ),
          ),
          Text('—', style: kMono(const Color(0x80FFFFFF))),
        ],
      );
    }
    return Row(
      children: [
        SizedBox(
          width: 64,
          child: Text(
            label,
            style: kCaption(),
          ),
        ),
        Text(
          '${tempC!.toStringAsFixed(1)}°C',
          style: kMono(_tempColor(tempC!)),
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
    if (v > 80) return kError;
    if (v > 60) return kWarning;
    return kViolet;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 64,
          child: Text(
            label,
            style: kCaption(),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: value / 100,
              backgroundColor: const Color(0x1FFFFFFF),
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
            style: kMono(),
          ),
        ),
      ],
    );
  }
}
