// Diagnostics overview (Level 1) — all Auras on the current property at a glance

import 'package:flutter/material.dart';
import '../../services/supabase_service.dart';
import 'diagnostics_screen.dart';

class DiagnosticsOverviewScreen extends StatefulWidget {
  const DiagnosticsOverviewScreen({super.key});

  @override
  State<DiagnosticsOverviewScreen> createState() =>
      _DiagnosticsOverviewScreenState();
}

class _DiagnosticsOverviewScreenState
    extends State<DiagnosticsOverviewScreen> {
  List<Map<String, dynamic>> _summaries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (mounted) setState(() => _loading = true);

    final installation = await SupabaseService.getInstallation();
    final propertyId = installation?['property_id'] as String?;
    if (propertyId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    final summaries =
        await SupabaseService.getInstallationsDiagnosticsSummary(propertyId);

    if (mounted) {
      setState(() {
        _summaries = summaries;
        _loading = false;
      });
    }
  }

  bool _isOnline(Map<String, dynamic>? status) {
    if (status == null) return false;
    if (status['is_online'] != true) return false;
    final lastSeen = status['last_seen_at'];
    if (lastSeen == null) return false;
    final dt = DateTime.tryParse(lastSeen.toString());
    if (dt == null) return false;
    return DateTime.now().toUtc().difference(dt.toUtc()).inSeconds < 45;
  }

  String _formatUptime(dynamic seconds) {
    if (seconds == null) return '—';
    final s = int.tryParse(seconds.toString()) ?? 0;
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final onlineCount =
        _summaries.where((s) => _isOnline(s['device_status'])).length;
    final totalErrors =
        _summaries.fold<int>(0, (sum, s) => sum + (s['error_count'] as int));
    final anyUpdates = _summaries
        .any((s) => (s['device_status'])?['update_available'] == true);

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
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(
                    color: Colors.white24,
                    strokeWidth: 1,
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    // ── Summary banner ──────────────────────────────────────
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF111111),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                margin: const EdgeInsets.only(right: 10),
                                decoration: BoxDecoration(
                                  color: onlineCount > 0
                                      ? Colors.greenAccent
                                      : Colors.white24,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              Text(
                                '$onlineCount of ${_summaries.length} Aura${_summaries.length == 1 ? '' : 's'} Online',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w300,
                                ),
                              ),
                            ],
                          ),
                          if (totalErrors > 0) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(Icons.warning_amber_outlined,
                                    color: Colors.amberAccent, size: 14),
                                const SizedBox(width: 8),
                                Text(
                                  '$totalErrors Error${totalErrors == 1 ? '' : 's'} in last 12h',
                                  style: const TextStyle(
                                    color: Colors.amberAccent,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w300,
                                  ),
                                ),
                              ],
                            ),
                          ] else ...[
                            const SizedBox(height: 8),
                            const Row(
                              children: [
                                Icon(Icons.check_circle_outline,
                                    color: Colors.greenAccent, size: 14),
                                SizedBox(width: 8),
                                Text(
                                  'No Errors',
                                  style: TextStyle(
                                    color: Colors.greenAccent,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w300,
                                  ),
                                ),
                              ],
                            ),
                          ],
                          if (anyUpdates) ...[
                            const SizedBox(height: 8),
                            const Row(
                              children: [
                                Icon(Icons.system_update_outlined,
                                    color: Colors.amberAccent, size: 14),
                                SizedBox(width: 8),
                                Text(
                                  'Updates Available',
                                  style: TextStyle(
                                    color: Colors.amberAccent,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w300,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    if (_summaries.isEmpty)
                      const Center(
                        child: Text(
                          'No Auras found for this property',
                          style: TextStyle(color: Colors.white24, fontSize: 13),
                        ),
                      )
                    else ...[
                      const Text(
                        'AURAS',
                        style: TextStyle(
                          fontSize: 10,
                          letterSpacing: 3,
                          color: Colors.white24,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ..._summaries.map((summary) {
                        final inst =
                            summary['installation'] as Map<String, dynamic>;
                        final status =
                            summary['device_status'] as Map<String, dynamic>?;
                        final hasErrors = summary['has_recent_errors'] as bool;
                        final errorCount = summary['error_count'] as int;
                        final online = _isOnline(status);
                        final updateAvailable =
                            status?['update_available'] == true;

                        return GestureDetector(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => DiagnosticsScreen(
                                installationId: inst['id'] as String,
                              ),
                            ),
                          ),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF111111),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: Row(
                              children: [
                                // Online dot
                                Container(
                                  width: 7,
                                  height: 7,
                                  margin: const EdgeInsets.only(right: 12),
                                  decoration: BoxDecoration(
                                    color: online
                                        ? Colors.greenAccent
                                        : Colors.white24,
                                    shape: BoxShape.circle,
                                  ),
                                ),

                                // Name + meta
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            inst['name'] ?? 'Aura',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w300,
                                            ),
                                          ),
                                          if (hasErrors) ...[
                                            const SizedBox(width: 8),
                                            Tooltip(
                                              message:
                                                  '$errorCount error${errorCount == 1 ? '' : 's'} in last 12h',
                                              child: const Icon(
                                                Icons.warning_amber_outlined,
                                                color: Colors.amberAccent,
                                                size: 14,
                                              ),
                                            ),
                                          ],
                                          if (updateAvailable) ...[
                                            const SizedBox(width: 6),
                                            const Tooltip(
                                              message: 'Update available',
                                              child: Icon(
                                                Icons.system_update_outlined,
                                                color: Colors.amberAccent,
                                                size: 14,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        [
                                          if (status?['software_version'] !=
                                              null)
                                            'v${status!['software_version']}',
                                          if (status?['uptime_seconds'] != null)
                                            _formatUptime(
                                                status!['uptime_seconds']),
                                        ].join(' · '),
                                        style: const TextStyle(
                                          color: Colors.white38,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                const Icon(Icons.chevron_right,
                                    color: Colors.white24, size: 18),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}
