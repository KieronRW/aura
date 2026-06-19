// Aura Detail screen — status, activity, settings for a specific Aura

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../widgets/skeleton.dart';
import '../../providers/installation_provider.dart';
import '../../providers/recognition_provider.dart';
import '../../services/supabase_service.dart';
import '../../theme/aura_theme.dart';

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
    final vehiclePart = [
      make,
      model,
    ].where((s) => s != null && s.isNotEmpty).join(' ');

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

    final parts = [
      ownerName,
      vehiclePart,
      timeLabel,
    ].where((s) => s.isNotEmpty).toList();
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
          SnackBar(
            content: Text('Update command sent', style: kBody()),
            backgroundColor: kCard,
          ),
        );
        setState(() => _updateDismissed = true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send update command', style: kBody()),
            backgroundColor: kError,
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
        backgroundColor: kCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: kCardBorder),
        ),
        title: Text(
          'RENAME AURA',
          style: kHeading(),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: kBody(),
          decoration: InputDecoration(
            hintText: 'e.g. Front Gate, Garage',
            hintStyle: kBody(const Color(0x40FFFFFF)),
            enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: kInputBorder),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => nav.pop(),
            child: Text(
              'CANCEL',
              style: kBody(kVioletText),
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
            child: Text(
              'SAVE',
              style: kBody(kVioletText),
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
      backgroundColor: kVoid,
      appBar: AppBar(
        backgroundColor: kVoid,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          auraName.toUpperCase(),
          style: kHeading(),
        ),
        actions: [
          IconButton(
            onPressed: _showRenameDialog,
            icon: const Icon(Icons.edit_outlined, size: 20),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: kBgGradient),
        child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: _loadData,
            color: kViolet,
            backgroundColor: kCard,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                // ── Update available banner ──────────────────────────────────
                if (_deviceStatus?['update_available'] == true &&
                    !_updateDismissed)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: kCardDim,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: kWarning.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.system_update_outlined,
                          color: kWarning,
                          size: 16,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Update available',
                            style: kCaption(kWarningText),
                          ),
                        ),
                        GestureDetector(
                          onTap: _sendUpdateCommand,
                          child: Text(
                            'UPDATE NOW',
                            style: kLabel(kWarningText),
                          ),
                        ),
                        const SizedBox(width: 16),
                        GestureDetector(
                          onTap: () => setState(() => _updateDismissed = true),
                          child: const Icon(
                            Icons.close,
                            color: Color(0x40FFFFFF),
                            size: 16,
                          ),
                        ),
                      ],
                    ),
                  ),

                // ── Status card ───────────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: kCard,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: kCardBorder),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: isOnline ? kOnline : kError,
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
                              style: kBody(isOnline ? kOnlineText : kErrorText),
                            ),
                          ],
                        ),
                      ),
                      if (isOnline)
                        Text(
                          (_deviceStatus?['current_state'] ?? '')
                              .toString()
                              .toUpperCase(),
                          style: kLabel(),
                        ),
                    ],
                  ),
                ),

                // ─────────────────────────────────────────────────────────────
                const SizedBox(height: 32),

                Text(
                  'LAST SEEN',
                  style: kLabel(),
                ),
                const SizedBox(height: 12),

                // Last seen row
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: kCard,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: kCardBorder),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.history,
                        color: Color(0x66FFFFFF),
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
                          style: kCaption(),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                Text(
                  'RECENT ACTIVITY',
                  style: kLabel(),
                ),
                const SizedBox(height: 12),

                // Search bar
                Container(
                  decoration: BoxDecoration(
                    color: kCard,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: kCardBorder),
                  ),
                  child: TextField(
                    style: kCaption(),
                    onChanged: (v) => setState(() => _searchQuery = v),
                    decoration: InputDecoration(
                      hintText: 'Search by name, vehicle, day or time...',
                      hintStyle: kCaption(const Color(0x40FFFFFF)),
                      prefixIcon: const Icon(
                        Icons.search,
                        color: Color(0x66FFFFFF),
                        size: 18,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                if (_loading)
                  SkeletonList(
                    itemCount: 5,
                    itemBuilder: (ctx, i) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Row(
                        children: [
                          const SkeletonBox(width: 56, height: 56, borderRadius: 0),
                          const SizedBox(width: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              SkeletonBox(width: 120, height: 13, borderRadius: 4),
                              SizedBox(height: 6),
                              SkeletonBox(width: 80, height: 11, borderRadius: 4),
                            ],
                          ),
                        ],
                      ),
                    ),
                  )
                else if (_filteredEvents.isEmpty)
                  Text(
                    _searchQuery.isNotEmpty
                        ? 'No results for "$_searchQuery"'
                        : 'No recent activity',
                    style: kCaption(),
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
        return kOnlineText;
      case 'vision':
        return kVioletText;
      case 'yolo':
        return kWarningText;
      case 'test':
        return const Color(0x40FFFFFF);
      default:
        return const Color(0x40FFFFFF);
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
        border: Border(bottom: BorderSide(color: kRowDivider)),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: kCard,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: kCardBorder),
            ),
            child: _imageLoading
                ? const Center(
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: kViolet,
                      ),
                    ),
                  )
                : _imageUrl != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: CachedNetworkImage(
                    imageUrl: _imageUrl!,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => const Center(
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: kViolet,
                        ),
                      ),
                    ),
                    errorWidget: (context, url, error) => const Icon(
                      Icons.directions_car_outlined,
                      color: Color(0x40FFFFFF),
                      size: 24,
                    ),
                  ),
                  )
                : const Icon(
                    Icons.directions_car_outlined,
                    color: Color(0x40FFFFFF),
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
                  style: kBody(),
                ),
                const SizedBox(height: 4),
                Text(
                  '${widget.date} · ${widget.time}',
                  style: kCaption(),
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
                    style: kCaption(const Color(0x40FFFFFF)),
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
