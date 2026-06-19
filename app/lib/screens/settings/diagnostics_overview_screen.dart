// Diagnostics overview (Level 1) — all Auras on the current property at a glance

import 'dart:async';

import 'package:flutter/material.dart';
import '../../services/supabase_service.dart';
import '../../theme/aura_theme.dart';
import 'diagnostics_screen.dart';

class DiagnosticsOverviewScreen extends StatefulWidget {
  const DiagnosticsOverviewScreen({super.key});

  @override
  State<DiagnosticsOverviewScreen> createState() =>
      _DiagnosticsOverviewScreenState();
}

class _DiagnosticsOverviewScreenState extends State<DiagnosticsOverviewScreen>
    with SingleTickerProviderStateMixin {
  // Stale-while-revalidate: survives navigate-away-and-back within the session.
  static List<Map<String, dynamic>>? _cache;

  List<Map<String, dynamic>> _summaries = [];
  bool _loading = true;
  bool _error = false;

  late final AnimationController _shimmerController;
  late final Animation<double> _shimmerOpacity;

  @override
  void initState() {
    super.initState();

    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _shimmerOpacity =
        Tween<double>(begin: 0.3, end: 0.7).animate(_shimmerController);

    if (_cache != null) {
      // Cached data available — show immediately, refresh silently in background.
      _summaries = _cache!;
      _loading = false;
      _loadData(foreground: false);
    } else {
      _loadData(foreground: true);
    }
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _fetch() async {
    final installation = await SupabaseService.getInstallation();
    final propertyId = installation?['property_id'] as String?;
    if (propertyId == null) return [];
    return SupabaseService.getInstallationsDiagnosticsSummary(propertyId);
  }

  Future<void> _loadData({bool foreground = true}) async {
    if (foreground) {
      if (mounted) setState(() { _loading = true; _error = false; });
    }

    try {
      final summaries = await _fetch().timeout(const Duration(seconds: 8));
      _cache = summaries;
      if (mounted) {
        setState(() {
          _summaries = summaries;
          _loading = false;
          _error = false;
        });
      }
    } on TimeoutException {
      if (mounted) {
        setState(() {
          _loading = false;
          // Only surface the error when there's nothing cached to show.
          if (_cache == null) _error = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          if (_cache == null) _error = true;
        });
      }
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

  // ── Skeleton ────────────────────────────────────────────────────────────────

  Widget _buildSkeleton() {
    return AnimatedBuilder(
      animation: _shimmerOpacity,
      builder: (context, _) {
        return Opacity(
          opacity: _shimmerOpacity.value,
          child: ListView(
            padding: const EdgeInsets.all(24),
            physics: const NeverScrollableScrollPhysics(),
            children: [
              // Summary banner placeholder (~80px)
              Container(
                height: 80,
                decoration: const BoxDecoration(color: Color(0xFF1C1C1C)),
              ),
              const SizedBox(height: 24),
              // Section label placeholder
              Container(width: 48, height: 9, color: const Color(0xFF1C1C1C)),
              const SizedBox(height: 12),
              // Aura card placeholders (~64px each)
              for (int i = 0; i < 2; i++)
                Container(
                  height: 64,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: const BoxDecoration(color: Color(0xFF1C1C1C)),
                ),
            ],
          ),
        );
      },
    );
  }

  // ── Error state ─────────────────────────────────────────────────────────────

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Could not load diagnostics',
            style: kCaption(),
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: () => _loadData(foreground: true),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(color: kCardBorder),
              ),
              child: Text(
                'RETRY',
                style: kLabel(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Main content ─────────────────────────────────────────────────────────────

  Widget _buildContent() {
    final onlineCount =
        _summaries.where((s) => _isOnline(s['device_status'])).length;
    final totalErrors =
        _summaries.fold<int>(0, (sum, s) => sum + (s['error_count'] as int));
    final anyUpdates = _summaries
        .any((s) => (s['device_status'])?['update_available'] == true);

    return RefreshIndicator(
      onRefresh: () => _loadData(foreground: false),
      color: Colors.white,
      backgroundColor: kCard,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // ── Summary banner ──────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: kCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: kCardBorder),
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
                            ? kOnline
                            : const Color(0x40FFFFFF),
                        shape: BoxShape.circle,
                      ),
                    ),
                    Text(
                      '$onlineCount of ${_summaries.length} Aura${_summaries.length == 1 ? '' : 's'} Online',
                      style: kBody(),
                    ),
                  ],
                ),
                if (totalErrors > 0) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.warning_amber_outlined,
                          color: kWarning, size: 14),
                      const SizedBox(width: 8),
                      Text(
                        '$totalErrors Error${totalErrors == 1 ? '' : 's'} in last 12h',
                        style: kCaption(kWarningText),
                      ),
                    ],
                  ),
                ] else ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.check_circle_outline,
                          color: kOnline, size: 14),
                      const SizedBox(width: 8),
                      Text(
                        'No Errors',
                        style: kCaption(kOnlineText),
                      ),
                    ],
                  ),
                ],
                if (anyUpdates) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.system_update_outlined,
                          color: kWarning, size: 14),
                      const SizedBox(width: 8),
                      Text(
                        'Updates Available',
                        style: kCaption(kWarningText),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 24),

          if (_summaries.isEmpty)
            Center(
              child: Text(
                'No Auras found for this property',
                style: kCaption(),
              ),
            )
          else ...[
            Text(
              'AURAS',
              style: kLabel(),
            ),
            const SizedBox(height: 12),
            ..._summaries.map((summary) {
              final inst = summary['installation'] as Map<String, dynamic>;
              final status =
                  summary['device_status'] as Map<String, dynamic>?;
              final hasErrors = summary['has_recent_errors'] as bool;
              final errorCount = summary['error_count'] as int;
              final online = _isOnline(status);
              final updateAvailable = status?['update_available'] == true;

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
                    color: kCard,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: kCardBorder),
                  ),
                  child: Row(
                    children: [
                      // Online dot
                      Container(
                        width: 7,
                        height: 7,
                        margin: const EdgeInsets.only(right: 12),
                        decoration: BoxDecoration(
                          color:
                              online ? kOnline : const Color(0x40FFFFFF),
                          shape: BoxShape.circle,
                        ),
                      ),

                      // Name + meta
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  inst['name'] ?? 'Aura',
                                  style: kBody(),
                                ),
                                if (hasErrors) ...[
                                  const SizedBox(width: 8),
                                  Tooltip(
                                    message:
                                        '$errorCount error${errorCount == 1 ? '' : 's'} in last 12h',
                                    child: const Icon(
                                      Icons.warning_amber_outlined,
                                      color: kWarning,
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
                                      color: kWarning,
                                      size: 14,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              [
                                if (status?['software_version'] != null)
                                  'v${status!['software_version']}',
                                if (status?['uptime_seconds'] != null)
                                  _formatUptime(status!['uptime_seconds']),
                              ].join(' · '),
                              style: kMono(const Color(0x80FFFFFF)),
                            ),
                          ],
                        ),
                      ),

                      const Icon(Icons.chevron_right,
                          color: Color(0x40FFFFFF), size: 18),
                    ],
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
          child: _loading
              ? _buildSkeleton()
              : _error
                  ? _buildError()
                  : _buildContent(),
        ),
      ),
    );
  }
}
