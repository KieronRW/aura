// Aura Detail screen — status, activity, settings for a specific Aura

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../providers/installation_provider.dart';
import '../../providers/recognition_provider.dart';
import '../../services/supabase_service.dart';

// In-memory signed URL cache — shared across all _EventRow instances
final Map<String, String> _signedUrlCache = {};

class AuraDetailScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> installation;

  const AuraDetailScreen({super.key, required this.installation});

  @override
  ConsumerState<AuraDetailScreen> createState() => _AuraDetailScreenState();
}

class _AuraDetailScreenState extends ConsumerState<AuraDetailScreen> {
  Map<String, dynamic>? _deviceStatus;
  List<Map<String, dynamic>> _recentEvents = [];
  bool _loading = true;
  RealtimeChannel? _statusChannel;
  RealtimeChannel? _eventsChannel;
  Timer? _statusTimer;
  String _searchQuery = '';
  bool _updateDismissed = false;

  @override
  void initState() {
    super.initState();
    _loadData();
    _subscribeToRealtime();
    _statusTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _refreshStatus(),
    );
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _statusChannel?.unsubscribe();
    _eventsChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _refreshStatus() async {
    final installationId = widget.installation['id'] as String;
    ref.invalidate(deviceStatusProvider(installationId));
    final status = await ref.read(deviceStatusProvider(installationId).future);
    if (mounted) setState(() => _deviceStatus = status);
  }

  void _subscribeToRealtime() {
    final installationId = widget.installation['id'] as String;

    _statusChannel = Supabase.instance.client
        .channel('aura_detail_status')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'device_status',
          callback: (payload) {
            if (mounted) {
              ref.invalidate(deviceStatusProvider(installationId));
              _loadData();
            }
          },
        )
        .subscribe();

    _eventsChannel = Supabase.instance.client
        .channel('aura_detail_events')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'recognition_events',
          callback: (payload) {
            if (mounted) {
              ref.invalidate(recognitionEventsProvider(installationId));
              _loadData();
            }
          },
        )
        .subscribe();
  }

  Future<void> _loadData() async {
    if (_recentEvents.isEmpty) {
      if (mounted) setState(() => _loading = true);
    }

    final installationId = widget.installation['id'] as String;
    final status = await ref.read(deviceStatusProvider(installationId).future);
    final eventModels = await ref.read(
      recognitionEventsProvider(installationId).future,
    );
    final events = eventModels.map((e) => e.toMap()).toList();
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

  String _formatLastSeen(Map<String, dynamic>? event) {
    if (event == null) return 'No recent activity';
    final arrivedAt = event['arrived_at'] as String?;
    final departedAt = event['departed_at'] as String?;
    if (arrivedAt == null) return 'No recent activity';

    String ownerName = '';
    final visitors = event['visitors'];
    if (visitors is Map && visitors['name'] != null) {
      ownerName = visitors['name'] as String;
    }

    final make = event['detected_make'] as String?;
    final model = event['detected_model'] as String?;
    final vehiclePart = [make, model]
        .where((s) => s != null && s.isNotEmpty)
        .join(' ');

    final arrivedDt = DateTime.parse(arrivedAt).toLocal();
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final dayLabel = days[arrivedDt.weekday - 1];
    final ah = arrivedDt.hour.toString().padLeft(2, '0');
    final am = arrivedDt.minute.toString().padLeft(2, '0');
    final arrivedLabel = '$dayLabel $ah:$am';

    String timeLabel;
    if (departedAt != null) {
      final departedDt = DateTime.parse(departedAt).toLocal();
      final dh = departedDt.hour.toString().padLeft(2, '0');
      final dm = departedDt.minute.toString().padLeft(2, '0');
      final depDayLabel = days[departedDt.weekday - 1];
      timeLabel = 'Arrived $arrivedLabel → Departed $depDayLabel $dh:$dm';
    } else {
      timeLabel = 'Arrived $arrivedLabel';
    }

    final parts = [ownerName, vehiclePart, timeLabel]
        .where((s) => s.isNotEmpty)
        .toList();
    return parts.join(' · ');
  }

  List<Map<String, dynamic>> get _filteredEvents {
    if (_searchQuery.isEmpty) return _recentEvents;
    final q = _searchQuery.toLowerCase();
    return _recentEvents.where((event) {
      final make = (event['detected_make'] ?? '').toString().toLowerCase();
      final model = (event['detected_model'] ?? '').toString().toLowerCase();
      final time = _formatTime(event['arrived_at'] as String?).toLowerCase();
      final date = _formatDate(event['arrived_at'] as String?).toLowerCase();
      return make.contains(q) ||
          model.contains(q) ||
          time.contains(q) ||
          date.contains(q);
    }).toList();
  }

  String _formatDate(String? isoString) {
    if (isoString == null) return '';
    final dt = DateTime.parse(isoString).toLocal();
    final now = DateTime.now();
    if (dt.day == now.day && dt.month == now.month) return 'Today';
    if (dt.day == now.day - 1 && dt.month == now.month) return 'Yesterday';
    return '${dt.day}/${dt.month}';
  }

  Future<void> _sendUpdateCommand() async {
    final installationId = widget.installation['id'] as String;
    try {
      await Supabase.instance.client.from('commands').insert({
        'installation_id': installationId,
        'command_type': 'update_software',
        'status': 'pending',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Update command sent'),
            backgroundColor: Colors.white12,
          ),
        );
        setState(() => _updateDismissed = true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to send update command'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
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
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: _loadData,
            color: Colors.white,
            backgroundColor: const Color(0xFF111111),
              child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
              // ── Update available banner ──────────────────────────────────
              if (_deviceStatus?['update_available'] == true && !_updateDismissed)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1500),
                    border: Border.all(color: Colors.amberAccent.withOpacity(0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.system_update_outlined,
                          color: Colors.amberAccent, size: 16),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Update available',
                          style: TextStyle(
                            color: Colors.amberAccent,
                            fontSize: 13,
                            fontWeight: FontWeight.w300,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: _sendUpdateCommand,
                        child: const Text(
                          'UPDATE NOW',
                          style: TextStyle(
                            color: Colors.amberAccent,
                            fontSize: 10,
                            letterSpacing: 1.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      GestureDetector(
                        onTap: () => setState(() => _updateDismissed = true),
                        child: const Icon(Icons.close,
                            color: Colors.white24, size: 16),
                      ),
                    ],
                  ),
                ),

              // ── Status card ───────────────────────────────────────────────
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
              // ─────────────────────────────────────────────────────────────

              const SizedBox(height: 32),

              const Text(
                'LAST SEEN',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 3,
                  color: Colors.white24,
                ),
              ),
              const SizedBox(height: 12),

              // Last seen row
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF111111),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.history,
                      color: Colors.white38,
                      size: 16,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _loading
                            ? '...'
                            : _formatLastSeen(
                                _recentEvents.isNotEmpty
                                    ? _recentEvents.first
                                    : null,
                              ),
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              const Text(
                'RECENT ACTIVITY',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 3,
                  color: Colors.white24,
                ),
              ),
              const SizedBox(height: 12),

              // Search bar
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF111111),
                  border: Border.all(color: Colors.white12),
                ),
                child: TextField(
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  onChanged: (v) => setState(() => _searchQuery = v),
                  decoration: const InputDecoration(
                    hintText: 'Search by name, vehicle, day or time...',
                    hintStyle: TextStyle(color: Colors.white24, fontSize: 13),
                    prefixIcon: Icon(
                      Icons.search,
                      color: Colors.white24,
                      size: 18,
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 12,
                    ),
                  ),
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
              else if (_filteredEvents.isEmpty)
                Text(
                  _searchQuery.isNotEmpty
                      ? 'No results for "$_searchQuery"'
                      : 'No recent activity',
                  style: const TextStyle(color: Colors.white24, fontSize: 13),
                )
              else
                ..._filteredEvents
                    .take(10)
                    .map(
                      (event) => _EventRow(
                        make: event['detected_make'] ?? 'Unknown',
                        model: event['detected_model'],
                        method: event['method'],
                        confidence: event['confidence'] as double?,
                        time: _formatTime(event['arrived_at']),
                        date: _formatDate(event['arrived_at']),
                        imagePath: event['image_path'],
                      ),
                    ),

            ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EventRow extends StatefulWidget {
  final String make;
  final String? model;
  final String? method;
  final double? confidence;
  final String time;
  final String date;
  final String? imagePath;

  const _EventRow({
    required this.make,
    required this.model,
    required this.method,
    this.confidence,
    required this.time,
    required this.date,
    this.imagePath,
  });

  @override
  State<_EventRow> createState() => _EventRowState();
}

class _EventRowState extends State<_EventRow> {
  String? _imageUrl;
  bool _imageLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.imagePath != null) {
      _loadImage();
    }
  }

  Future<void> _loadImage() async {
    if (_signedUrlCache.containsKey(widget.imagePath)) {
      setState(() => _imageUrl = _signedUrlCache[widget.imagePath]);
      return;
    }

    setState(() => _imageLoading = true);
    final url = await SupabaseService.getSignedImageUrl(widget.imagePath!);
    if (url != null) {
      _signedUrlCache[widget.imagePath!] = url;
    }
    if (mounted) {
      setState(() {
        _imageUrl = url;
        _imageLoading = false;
      });
    }
  }

  IconData get _methodIcon {
    switch (widget.method) {
      case 'fingerprint':
        return Icons.fingerprint;
      case 'vision':
        return Icons.auto_awesome;
      case 'yolo':
        return Icons.smart_toy_outlined;
      case 'test':
        return Icons.bug_report_outlined;
      default:
        return Icons.help_outline;
    }
  }

  Color get _methodColor {
    switch (widget.method) {
      case 'fingerprint':
        return Colors.greenAccent;
      case 'vision':
        return Colors.white38;
      case 'yolo':
        return Colors.amber;
      case 'test':
        return Colors.white24;
      default:
        return Colors.white24;
    }
  }

  String get _methodTooltip {
    switch (widget.method) {
      case 'fingerprint':
        return 'Identified by fingerprint match';
      case 'vision':
        return 'Identified by Vision API';
      case 'yolo':
        return 'Identified by YOLO detection';
      case 'test':
        return 'Test recognition';
      default:
        return 'Unknown method';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white12)),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFF111111),
              border: Border.all(color: Colors.white12),
            ),
            child: _imageLoading
                ? const Center(
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 1,
                        color: Colors.white24,
                      ),
                    ),
                  )
                : _imageUrl != null
                ? CachedNetworkImage(
                    imageUrl: _imageUrl!,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => const Center(
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 1,
                          color: Colors.white24,
                        ),
                      ),
                    ),
                    errorWidget: (context, url, error) => const Icon(
                      Icons.directions_car_outlined,
                      color: Colors.white24,
                      size: 24,
                    ),
                  )
                : const Icon(
                    Icons.directions_car_outlined,
                    color: Colors.white24,
                    size: 24,
                  ),
          ),

          const SizedBox(width: 16),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.model != null
                      ? '${widget.make} · ${widget.model}'
                      : widget.make,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${widget.date} · ${widget.time}',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),

          Tooltip(
            message: _methodTooltip,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_methodIcon, color: _methodColor, size: 16),
                if (widget.confidence != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${(widget.confidence! * 100).round()}%',
                    style: const TextStyle(color: Colors.white24, fontSize: 9),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
