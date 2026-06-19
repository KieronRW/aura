import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/aura_theme.dart';
import '../../widgets/skeleton.dart';

const _kAppVersion = '1.0.0';
const _kSupportEmail = 'support@vivosmartlife.co.za';

// ─────────────────────────────────────────────────────────────────────────────
// Data model
// ─────────────────────────────────────────────────────────────────────────────

class _AuraStatus {
  final String id;
  final String name;
  final String propertyName;
  final Map<String, dynamic>? deviceStatus;

  const _AuraStatus({
    required this.id,
    required this.name,
    required this.propertyName,
    this.deviceStatus,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Quick-help data
// ─────────────────────────────────────────────────────────────────────────────

const _kQuickHelp = [
  (
    'Aura is offline',
    [
      'Confirm the Aura has power',
      'Confirm the network is available',
      'Try restarting Aura from Device Actions below',
      'If the issue persists, send a diagnostic report',
    ]
  ),
  (
    'Camera is not detecting vehicles',
    [
      'Check the camera lens is unobstructed',
      'Restart Aura',
      'Check Camera settings under Manage Auras',
      'Send a diagnostic report if the issue continues',
    ]
  ),
  (
    'Wrong vehicle is being recognised',
    [
      'Add more reference images for the vehicle under Profiles',
      'Check recognition confidence thresholds',
      'Send a diagnostic report if this continues',
    ]
  ),
  (
    'Badge is not displaying',
    [
      'Restart Aura',
      'Confirm the display is connected',
      'Send a diagnostic report',
    ]
  ),
  (
    'App cannot find Aura',
    [
      'Confirm your phone is on the same WiFi network as Aura',
      'Restart Aura',
      'Try adding the Aura again from Manage Auras',
    ]
  ),
];

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────

class SupportScreen extends ConsumerStatefulWidget {
  const SupportScreen({super.key});

  @override
  ConsumerState<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends ConsumerState<SupportScreen> {
  List<_AuraStatus> _auras = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id ?? '';

      final instsRaw = await client
          .from('installations')
          .select('id, name, property_id, properties(name)')
          .eq('claimed_by', userId)
          .eq('status', 'active');

      final instList = List<Map<String, dynamic>>.from(instsRaw as List);
      if (instList.isEmpty) {
        if (mounted) setState(() { _auras = []; _loading = false; });
        return;
      }

      final instIds = instList.map((i) => i['id'] as String).toList();
      final statusRaw = await client
          .from('device_status')
          .select('*')
          .inFilter('installation_id', instIds);

      final statusMap = <String, Map<String, dynamic>>{};
      for (final s in statusRaw as List) {
        statusMap[s['installation_id'] as String] = Map<String, dynamic>.from(s);
      }

      final auras = instList.map((i) {
        final props = i['properties'];
        return _AuraStatus(
          id: i['id'] as String,
          name: i['name'] as String? ?? 'Aura',
          propertyName: props is Map ? props['name'] as String? ?? '' : '',
          deviceStatus: statusMap[i['id'] as String],
        );
      }).toList();

      if (mounted) setState(() { _auras = auras; _loading = false; });
    } catch (e) {
      debugPrint('SupportScreen load error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  bool _isActuallyOnline(Map<String, dynamic>? status) {
    if (status == null) return false;
    if (status['is_online'] != true) return false;
    final lastSeen = status['last_seen_at'] as String?;
    if (lastSeen == null) return false;
    final lastSeenDt = DateTime.tryParse(lastSeen);
    if (lastSeenDt == null) return false;
    return DateTime.now().toUtc().difference(lastSeenDt).inSeconds < 45;
  }

  String _relativeTime(String? isoString) {
    if (isoString == null) return 'Never';
    final dt = DateTime.tryParse(isoString);
    if (dt == null) return 'Unknown';
    final diff = DateTime.now().toUtc().difference(dt.toUtc());
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  String? get _lastSyncIso {
    DateTime? latest;
    for (final a in _auras) {
      final raw = a.deviceStatus?['last_seen_at'] as String?;
      if (raw == null) continue;
      final dt = DateTime.tryParse(raw);
      if (dt == null) continue;
      if (latest == null || dt.isAfter(latest)) latest = dt;
    }
    return latest?.toIso8601String();
  }

  // ── Command dispatch ──────────────────────────────────────────────────────

  Future<void> _doCommand(
    String commandType,
    String label,
    String confirmMessage,
  ) async {
    if (_auras.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No Aura found', style: kBody()),
          backgroundColor: kError,
        ),
      );
      return;
    }

    String? installationId;
    if (_auras.length == 1) {
      installationId = _auras[0].id;
    } else {
      installationId = await _pickAura();
      if (installationId == null || !mounted) return;
    }

    final confirmed = await _showConfirmDialog(label, confirmMessage);
    if (!confirmed || !mounted) return;

    try {
      await Supabase.instance.client.from('commands').insert({
        'installation_id': installationId,
        'command_type': commandType,
        'status': 'pending',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$label command sent', style: kBody()),
            backgroundColor: kCard,
          ),
        );
      }
    } catch (e) {
      debugPrint('Command insert error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send command', style: kBody()),
            backgroundColor: kError,
          ),
        );
      }
    }
  }

  Future<String?> _pickAura() => showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: kCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: kCardBorder),
          ),
          title: Text(
            'Select Aura',
            style: kHeading(),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: _auras
                .map(
                  (a) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      a.name,
                      style: kBody(),
                    ),
                    subtitle: Text(
                      a.propertyName,
                      style: kCaption(),
                    ),
                    onTap: () => Navigator.pop(context, a.id),
                  ),
                )
                .toList(),
          ),
        ),
      );

  Future<bool> _showConfirmDialog(String title, String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: kCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: kCardBorder),
        ),
        title: Text(
          title,
          style: kHeading(),
        ),
        content: Text(
          message,
          style: kCaption(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: kBody()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Confirm', style: kBody(kVioletText)),
          ),
        ],
      ),
    );
    return result == true;
  }

  // ── Diagnostic report ─────────────────────────────────────────────────────

  Future<void> _showDiagnosticForm() async {
    final ctrl = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: kCardBorder),
        ),
        title: Text(
          'Diagnostic Report',
          style: kHeading(),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Briefly describe the issue:',
              style: kCaption(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              maxLines: 4,
              style: kBody(),
              decoration: InputDecoration(
                hintText: 'e.g. Camera stopped detecting vehicles',
                hintStyle: kBody(const Color(0x66FFFFFF)),
                enabledBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: kInputBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: kViolet),
                ),
                isDense: true,
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              ctrl.dispose();
              Navigator.pop(ctx);
            },
            child: Text('Cancel', style: kBody()),
          ),
          TextButton(
            onPressed: () {
              final description = ctrl.text.trim();
              ctrl.dispose();
              Navigator.pop(ctx);
              _sendDiagnosticReport(description);
            },
            child: Text('Send', style: kBody(kVioletText)),
          ),
        ],
      ),
    );
  }

  Future<void> _sendDiagnosticReport(String description) async {
    final user = Supabase.instance.client.auth.currentUser;
    final buf = StringBuffer()
      ..writeln('AURA Diagnostic Report')
      ..writeln('======================')
      ..writeln('User: ${user?.email ?? "Unknown"}')
      ..writeln('App Version: $_kAppVersion')
      ..writeln('Platform: ${Platform.operatingSystem}')
      ..writeln();

    buf.writeln('INSTALLATIONS:');
    for (final a in _auras) {
      buf
        ..writeln('  Name: ${a.name}')
        ..writeln('  ID: ${a.id}')
        ..writeln('  Property: ${a.propertyName}')
        ..writeln('  Status: ${_isActuallyOnline(a.deviceStatus) ? "Online" : "Offline"}')
        ..writeln('  Software: ${a.deviceStatus?["software_version"] ?? "—"}')
        ..writeln('  Last Seen: ${a.deviceStatus?["last_seen_at"] ?? "Never"}')
        ..writeln();
    }

    if (description.isNotEmpty) {
      buf
        ..writeln('DESCRIPTION:')
        ..writeln(description);
    }

    final subject = Uri.encodeComponent('AURA Diagnostic Report');
    final body = Uri.encodeComponent(buf.toString());
    final uri = Uri.parse('mailto:$_kSupportEmail?subject=$subject&body=$body');

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No email app available', style: kBody()),
            backgroundColor: kError,
          ),
        );
      }
    } catch (e) {
      debugPrint('Launch email error: $e');
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final firstAura = _auras.isNotEmpty ? _auras.first : null;

    return Scaffold(
      backgroundColor: kVoid,
      appBar: AppBar(
        backgroundColor: kVoid,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'Support',
          style: kHeading(),
        ),
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Container(
          decoration: const BoxDecoration(gradient: kBgGradient),
          child: SafeArea(
            child: RefreshIndicator(
              onRefresh: _load,
              color: kViolet,
              backgroundColor: kCard,
              child: _loading
                  ? ListView(
                      padding: const EdgeInsets.all(24),
                      children: [
                        const SkeletonBox(width: 100, height: 10, borderRadius: 3),
                        const SizedBox(height: 16),
                        Container(
                          decoration: BoxDecoration(
                            color: kCard,
                            border: Border.all(color: kCardBorder),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            children: List.generate(
                              3,
                              (i) => Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                decoration: i > 0
                                    ? const BoxDecoration(
                                        border: Border(top: BorderSide(color: kRowDivider)),
                                      )
                                    : null,
                                child: Row(
                                  children: const [
                                    SkeletonBox(width: 8, height: 8, borderRadius: 4),
                                    SizedBox(width: 12),
                                    Expanded(child: SkeletonBox(width: double.infinity, height: 13, borderRadius: 4)),
                                    SizedBox(width: 40),
                                    SkeletonBox(width: 50, height: 12, borderRadius: 4),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  : ListView(
                      padding: const EdgeInsets.all(24),
                      children: [
                        // ── SYSTEM STATUS ───────────────────────────────────
                        Text('SYSTEM STATUS', style: kLabel()),
                        const SizedBox(height: 16),
                        _buildStatusRows(),
                        const SizedBox(height: 32),

                        // ── QUICK HELP ──────────────────────────────────────
                        Text('QUICK HELP', style: kLabel()),
                        const SizedBox(height: 8),
                        _buildQuickHelp(),
                        const SizedBox(height: 32),

                        // ── DEVICE ACTIONS ──────────────────────────────────
                        Text('DEVICE ACTIONS', style: kLabel()),
                        const SizedBox(height: 16),
                        _buildDeviceActions(),
                        const SizedBox(height: 32),

                        // ── SEND DIAGNOSTIC REPORT ──────────────────────────
                        Text('SEND DIAGNOSTIC REPORT', style: kLabel()),
                        const SizedBox(height: 16),
                        _buildDiagnosticButton(),
                        const SizedBox(height: 32),

                        // ── ABOUT THIS AURA ─────────────────────────────────
                        Text('ABOUT THIS AURA', style: kLabel()),
                        const SizedBox(height: 16),
                        _buildAbout(firstAura),
                        const SizedBox(height: 32),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Section builders ──────────────────────────────────────────────────────

  Widget _buildStatusRows() {
    return Container(
      decoration: BoxDecoration(
        color: kCard,
        border: Border.all(color: kCardBorder),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          // Supabase Cloud — static
          _StatusRow(
            label: 'Supabase Cloud',
            online: true,
            trailing: 'Online',
          ),
          // Last Sync
          _StatusRow(
            label: 'Last Sync',
            online: _lastSyncIso != null,
            trailing: _relativeTime(_lastSyncIso),
            onlineColor: const Color(0x66FFFFFF),
          ),
          // One row per installation
          ..._auras.map((a) {
            final online = _isActuallyOnline(a.deviceStatus);
            return _StatusRow(
              label: a.name,
              sublabel: a.propertyName.isNotEmpty ? a.propertyName : null,
              online: online,
              trailing: online ? 'Online' : 'Offline',
            );
          }),
          if (_auras.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'No Auras claimed yet',
                style: kCaption(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildQuickHelp() {
    return Container(
      decoration: BoxDecoration(
        color: kCard,
        border: Border.all(color: kCardBorder),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: _kQuickHelp.map((item) {
          final (title, steps) = item;
          return ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 16),
            childrenPadding:
                const EdgeInsets.fromLTRB(16, 0, 16, 16),
            collapsedTextColor: Colors.white,
            textColor: Colors.white,
            collapsedIconColor: const Color(0x40FFFFFF),
            iconColor: const Color(0x66FFFFFF),
            shape: const Border(),
            collapsedShape: const Border(),
            title: Text(
              title,
              style: kBody(),
            ),
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: steps.asMap().entries.map((e) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${e.key + 1}. ',
                          style: kCaption(),
                        ),
                        Expanded(
                          child: Text(
                            e.value,
                            style: kCaption(),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDeviceActions() {
    return Column(
      children: [
        _ActionButton(
          label: 'RESTART AURA',
          icon: Icons.restart_alt_outlined,
          onPressed: () => _doCommand(
            'reboot',
            'Restart Aura',
            'The display will be unavailable for about a minute.',
          ),
        ),
        const SizedBox(height: 12),
        _ActionButton(
          label: 'SYNC SETTINGS',
          icon: Icons.sync_outlined,
          onPressed: () => _doCommand(
            'sync_settings',
            'Sync Settings',
            'Aura will re-fetch its settings from the cloud.',
          ),
        ),
        const SizedBox(height: 12),
        _ActionButton(
          label: 'CHECK FOR UPDATE',
          icon: Icons.system_update_alt_outlined,
          onPressed: () => _doCommand(
            'update_software',
            'Check for Update',
            'Check for software update? The Aura will restart if an update is available.',
          ),
        ),
      ],
    );
  }

  Widget _buildDiagnosticButton() {
    return _ActionButton(
      label: 'SEND DIAGNOSTIC REPORT',
      icon: Icons.send_outlined,
      onPressed: _showDiagnosticForm,
    );
  }

  Widget _buildAbout(_AuraStatus? aura) {
    final ds = aura?.deviceStatus;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kCard,
        border: Border.all(color: kCardBorder),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          _AboutRow(
              label: 'Aura name',
              value: aura?.name ?? '—'),
          _AboutRow(
              label: 'Software version',
              value: ds?['software_version'] as String? ?? '—'),
          _AboutRow(
              label: 'Hardware version',
              value: ds?['hardware_version'] as String? ?? '—'),
          _AboutRow(
              label: 'App version',
              value: _kAppVersion),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Private widgets
// ─────────────────────────────────────────────────────────────────────────────

class _StatusRow extends StatelessWidget {
  final String label;
  final String? sublabel;
  final bool online;
  final String trailing;
  final Color? onlineColor;

  const _StatusRow({
    required this.label,
    this.sublabel,
    required this.online,
    required this.trailing,
    this.onlineColor,
  });

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: online
            ? (onlineColor ?? kOnline)
            : const Color(0x40FFFFFF),
        shape: BoxShape.circle,
      ),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: kRowDivider)),
      ),
      child: Row(
        children: [
          dot,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: kBody(),
                ),
                if (sublabel != null && sublabel!.isNotEmpty)
                  Text(
                    sublabel!,
                    style: kCaption(),
                  ),
              ],
            ),
          ),
          Text(
            trailing,
            style: kCaption(online
                ? (onlineColor ?? kOnline)
                : const Color(0x66FFFFFF)),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: const BorderSide(color: kCardBorder),
          padding: const EdgeInsets.symmetric(vertical: 14),
          textStyle: const TextStyle(
            letterSpacing: 2,
            fontSize: 12,
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _AboutRow extends StatelessWidget {
  final String label;
  final String value;

  const _AboutRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: kCaption(),
            ),
          ),
          Text(
            value,
            style: kCaption(),
          ),
        ],
      ),
    );
  }
}
