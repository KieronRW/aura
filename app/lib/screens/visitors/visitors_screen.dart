// Visitors screen — expected visitors, unknown vehicles, visitor history

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../providers/installation_provider.dart';
import '../../providers/visitor_provider.dart';

// In-memory signed URL cache shared across all _UnknownRow instances
final Map<String, String> _signedUrlCache = {};

const _kSectionStyle = TextStyle(
  fontSize: 11,
  letterSpacing: 4,
  color: Colors.white38,
);

// ─────────────────────────────────────────────────────────────────────────────
// Main screen
// ─────────────────────────────────────────────────────────────────────────────

class VisitorsScreen extends ConsumerStatefulWidget {
  const VisitorsScreen({super.key});

  @override
  ConsumerState<VisitorsScreen> createState() => _VisitorsScreenState();
}

class _VisitorsScreenState extends ConsumerState<VisitorsScreen> {
  Map<String, dynamic>? _installation;
  List<Map<String, dynamic>> _visitors = [];
  List<Map<String, dynamic>> _unknownVehicles = [];
  List<Map<String, dynamic>> _visitorHistory = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final installation = await ref.read(currentInstallationProvider.future);
    if (!mounted) return;
    setState(() => _installation = installation);
    if (installation != null) {
      await _loadData(installation['id'] as String);
    } else {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadData(String installationId) async {
    try {
      final data = await ref.read(visitorDataProvider(installationId).future);
      if (mounted) {
        setState(() {
          _visitors = data['visitors'] ?? [];
          _unknownVehicles = data['unknownVehicles'] ?? [];
          _visitorHistory = data['history'] ?? [];
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('VisitorsScreen load error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refresh() async {
    final id = _installation?['id'] as String?;
    if (id != null) {
      ref.invalidate(visitorDataProvider(id));
      await _loadData(id);
    }
  }

  Future<void> _openAddEdit(
    BuildContext context,
    Map<String, dynamic>? visitor, {
    Map<String, dynamic>? prefill,
  }) async {
    final installationId = _installation?['id'] as String?;
    if (installationId == null) return;
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _AddEditVisitorScreen(
          installationId: installationId,
          propertyId: _installation?['property_id'] as String?,
          visitor: visitor,
          prefillMake: prefill?['detected_make'] as String?,
          prefillModel: prefill?['detected_model'] as String?,
        ),
      ),
    );
    if (result == true && mounted) _refresh();
  }

  Future<void> _ignoreUnknown(dynamic id) async {
    try {
      await Supabase.instance.client
          .from('unknown_vehicles')
          .update({'status': 'dismissed'}).eq('id', id);
      if (mounted) _refresh();
    } catch (e) {
      debugPrint('Ignore unknown vehicle error: $e');
    }
  }

  Future<void> _addToProfile(
      BuildContext context, Map<String, dynamic> unknownVehicle) async {
    final installationId = _installation?['id'] as String?;
    if (installationId == null) return;

    List<Map<String, dynamic>> profiles;
    try {
      final data = await Supabase.instance.client
          .from('profiles')
          .select('id, display_name')
          .eq('installation_id', installationId)
          .eq('is_active', true)
          .order('display_name');
      profiles = List<Map<String, dynamic>>.from(data as List);
      // keep using direct client here since we need a lightweight id+name query
    } catch (e) {
      debugPrint('Load profiles error: $e');
      return;
    }
    if (!mounted) return;

    if (profiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No active profiles found for this installation'),
          backgroundColor: Color(0xFF111111),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    final profile = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: const Color(0xFF111111),
      builder: (_) => _ProfilePickerSheet(profiles: profiles),
    );
    if (profile == null || !mounted) return;

    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _AddVehicleScreen(
          profileId: profile['id'] as String,
          profileName: profile['display_name'] as String? ?? '',
          prefillMake: unknownVehicle['detected_make'] as String?,
          prefillModel: unknownVehicle['detected_model'] as String?,
          unknownVehicleId: unknownVehicle['id'],
        ),
      ),
    );
    if (saved == true && mounted) _refresh();
  }

  // ── Status helpers ────────────────────────────────────────────────────────

  static String _visitorStatus(Map<String, dynamic> v) {
    final now = DateTime.now().toUtc();
    final from = v['expected_from'] != null
        ? DateTime.parse(v['expected_from'].toString())
        : null;
    final until = v['expected_until'] != null
        ? DateTime.parse(v['expected_until'].toString())
        : null;
    if (until != null && until.isBefore(now)) return 'EXPIRED';
    if (from != null && from.isAfter(now)) return 'UPCOMING';
    return 'ACTIVE';
  }

  static Color _statusColor(String status) {
    if (status == 'ACTIVE') return Colors.greenAccent;
    if (status == 'UPCOMING') return Colors.orangeAccent;
    return Colors.white24;
  }

  static String _formatWindow(Map<String, dynamic> v) {
    final from = v['expected_from'];
    final until = v['expected_until'];
    if (from == null && until == null) return 'Anytime';
    if (from != null && until != null) {
      final fromDt = DateTime.parse(from.toString()).toLocal();
      final untilDt = DateTime.parse(until.toString()).toLocal();
      final fromLabel = _formatDt(fromDt);
      if (fromDt.year == untilDt.year &&
          fromDt.month == untilDt.month &&
          fromDt.day == untilDt.day) {
        final uh = untilDt.hour.toString().padLeft(2, '0');
        final um = untilDt.minute.toString().padLeft(2, '0');
        return '$fromLabel – $uh:$um';
      }
      return '$fromLabel – ${_formatDt(untilDt)}';
    }
    if (from != null) return 'From ${_formatDt(DateTime.parse(from.toString()).toLocal())}';
    return 'Until ${_formatDt(DateTime.parse(until.toString()).toLocal())}';
  }

  static String _formatDt(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${days[dt.weekday - 1]} ${dt.day} ${months[dt.month - 1]}, $h:$m';
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SafeArea(
        child: Center(
          child: CircularProgressIndicator(
            color: Colors.white24,
            strokeWidth: 1,
          ),
        ),
      );
    }

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _refresh,
        color: Colors.white,
        backgroundColor: const Color(0xFF111111),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            // ── Section 1: EXPECTED VISITORS ─────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('EXPECTED VISITORS', style: _kSectionStyle),
                GestureDetector(
                  onTap: () => _openAddEdit(context, null),
                  child: const Icon(Icons.add, color: Colors.white, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_visitors.isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'No expected visitors',
                  style: TextStyle(color: Colors.white24, fontSize: 13),
                ),
              )
            else
              ..._visitors.map((v) {
                final status = _visitorStatus(v);
                return _VisitorRow(
                  visitor: v,
                  status: status,
                  statusColor: _statusColor(status),
                  window: _formatWindow(v),
                  onTap: () => _openAddEdit(context, v),
                );
              }),

            const SizedBox(height: 36),

            // ── Section 2: UNKNOWN VISITORS ───────────────────────────────
            const Text('UNKNOWN VISITORS', style: _kSectionStyle),
            const SizedBox(height: 12),
            if (_unknownVehicles.isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'No unknown visitors',
                  style: TextStyle(color: Colors.white24, fontSize: 13),
                ),
              )
            else
              ..._unknownVehicles.map(
                (uv) => _UnknownRow(
                  vehicle: uv,
                  onIgnore: () => _ignoreUnknown(uv['id']),
                  onAddAsVisitor: () =>
                      _openAddEdit(context, null, prefill: uv),
                  onAddToProfile: () => _addToProfile(context, uv),
                ),
              ),

            const SizedBox(height: 36),

            // ── Section 3: VISITOR HISTORY ────────────────────────────────
            const Text('VISITOR HISTORY', style: _kSectionStyle),
            const SizedBox(height: 12),
            if (_visitorHistory.isEmpty)
              const Text(
                'No visitor history',
                style: TextStyle(color: Colors.white24, fontSize: 13),
              )
            else
              ..._visitorHistory.map((e) => _HistoryRow(event: e)),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Expected visitor row
// ─────────────────────────────────────────────────────────────────────────────

class _VisitorRow extends StatefulWidget {
  final Map<String, dynamic> visitor;
  final String status;
  final Color statusColor;
  final String window;
  final VoidCallback onTap;

  const _VisitorRow({
    required this.visitor,
    required this.status,
    required this.statusColor,
    required this.window,
    required this.onTap,
  });

  @override
  State<_VisitorRow> createState() => _VisitorRowState();
}

class _VisitorRowState extends State<_VisitorRow> {
  late bool _isActive;

  @override
  void initState() {
    super.initState();
    _isActive = widget.visitor['is_active'] as bool? ?? true;
  }

  void _toggleActive() {
    final newValue = !_isActive;
    setState(() => _isActive = newValue);
    _persistActive(newValue);
  }

  Future<void> _persistActive(bool value) async {
    try {
      await Supabase.instance.client
          .from('visitors')
          .update({'is_active': value})
          .eq('id', widget.visitor['id']);
    } catch (_) {
      if (mounted) setState(() => _isActive = !value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.visitor['name'] as String? ?? 'Unknown';
    final make = widget.visitor['vehicle_make'] as String?;
    final model = widget.visitor['vehicle_model'] as String?;
    final vehicleLabel =
        [make, model].where((s) => s != null && s.isNotEmpty).join(' ');

    final nameColor = _isActive ? Colors.white : Colors.white38;
    final subColor = _isActive ? Colors.white38 : Colors.white24;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white12)),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: widget.onTap,
              behavior: HitTestBehavior.opaque,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: TextStyle(
                            color: nameColor,
                            fontSize: 14,
                            fontWeight: FontWeight.w300,
                          ),
                        ),
                        if (vehicleLabel.isNotEmpty)
                          Text(
                            vehicleLabel,
                            style: TextStyle(
                              color: subColor,
                              fontSize: 12,
                            ),
                          ),
                        const SizedBox(height: 2),
                        Text(
                          widget.window,
                          style: TextStyle(
                            color: subColor,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_isActive)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Text(
                        widget.status,
                        style: TextStyle(
                          color: widget.statusColor,
                          fontSize: 9,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right,
                      color: Colors.white24, size: 18),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          ),
          Switch(
            value: _isActive,
            onChanged: (_) => _toggleActive(),
            activeThumbColor: Colors.white,
            activeTrackColor: Colors.white24,
            inactiveThumbColor: Colors.white38,
            inactiveTrackColor: Colors.white12,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Unknown vehicle row
// ─────────────────────────────────────────────────────────────────────────────

class _UnknownRow extends StatefulWidget {
  final Map<String, dynamic> vehicle;
  final VoidCallback onIgnore;
  final VoidCallback onAddAsVisitor;
  final VoidCallback onAddToProfile;

  const _UnknownRow({
    required this.vehicle,
    required this.onIgnore,
    required this.onAddAsVisitor,
    required this.onAddToProfile,
  });

  @override
  State<_UnknownRow> createState() => _UnknownRowState();
}

class _UnknownRowState extends State<_UnknownRow> {
  String? _imageUrl;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    final path = widget.vehicle['image_path'] as String?;
    if (path == null) return;
    final cached = _signedUrlCache[path];
    if (cached != null) {
      if (mounted) setState(() => _imageUrl = cached);
      return;
    }
    try {
      final url = await Supabase.instance.client.storage
          .from('recognition-images')
          .createSignedUrl(path, 3600);
      _signedUrlCache[path] = url;
      if (mounted) setState(() => _imageUrl = url);
    } catch (e) {
      debugPrint('Unknown vehicle image URL error: $e');
    }
  }

  static String _formatTs(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.parse(iso).toLocal();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} ${months[dt.month - 1]}, $h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final make = widget.vehicle['detected_make'] as String?;
    final model = widget.vehicle['detected_model'] as String?;
    final vehicleLabel =
        [make, model].where((s) => s != null && s.isNotEmpty).join(' ');
    final confidence =
        (widget.vehicle['confidence'] as num?)?.toDouble() ?? 0.0;
    final detectedAt = widget.vehicle['created_at'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
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
                width: 64,
                height: 48,
                color: const Color(0xFF222222),
                child: _imageUrl != null
                    ? Image.network(
                        _imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Center(
                          child: Icon(Icons.broken_image_outlined,
                              color: Colors.white24, size: 20),
                        ),
                      )
                    : const Center(
                        child: Icon(Icons.directions_car_outlined,
                            color: Colors.white24, size: 20),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vehicleLabel.isNotEmpty
                          ? vehicleLabel
                          : 'Unknown vehicle',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Text(
                          _formatTs(detectedAt),
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${(confidence * 100).toStringAsFixed(0)}%',
                          style: const TextStyle(
                            color: Colors.white24,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _ActionButton(
                label: 'ADD AS VISITOR',
                onTap: widget.onAddAsVisitor,
              ),
              const SizedBox(width: 6),
              _ActionButton(
                label: 'ADD TO PROFILE',
                onTap: widget.onAddToProfile,
              ),
              const SizedBox(width: 6),
              _ActionButton(
                label: 'IGNORE',
                onTap: widget.onIgnore,
                destructive: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  const _ActionButton({
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            border: Border.all(
              color: destructive ? Colors.redAccent.withOpacity(0.4) : Colors.white12,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: destructive ? Colors.redAccent : Colors.white54,
              fontSize: 9,
              letterSpacing: 0.8,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Visitor history row
// ─────────────────────────────────────────────────────────────────────────────

class _HistoryRow extends StatelessWidget {
  final Map<String, dynamic> event;

  const _HistoryRow({required this.event});

  static String _formatTs(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.parse(iso).toLocal();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} ${months[dt.month - 1]}, $h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final visitors = event['visitors'];
    final visitorName = (visitors is Map)
        ? (visitors['name'] as String? ?? 'Unknown')
        : 'Unknown';
    final make = event['detected_make'] as String? ?? '—';
    final arrivedAt = event['arrived_at'] as String?;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white12)),
      ),
      child: Row(
        children: [
          const Icon(Icons.person_outline, color: Colors.white24, size: 16),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  visitorName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w300,
                  ),
                ),
                Text(
                  make,
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          ),
          Text(
            _formatTs(arrivedAt),
            style: const TextStyle(color: Colors.white24, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Add / Edit visitor screen
// ─────────────────────────────────────────────────────────────────────────────

class _AddEditVisitorScreen extends ConsumerStatefulWidget {
  final String installationId;
  final String? propertyId;
  final Map<String, dynamic>? visitor;
  final String? prefillMake;
  final String? prefillModel;

  const _AddEditVisitorScreen({
    required this.installationId,
    this.propertyId,
    this.visitor,
    this.prefillMake,
    this.prefillModel,
  });

  @override
  ConsumerState<_AddEditVisitorScreen> createState() =>
      _AddEditVisitorScreenState();
}

class _AddEditVisitorScreenState extends ConsumerState<_AddEditVisitorScreen> {
  final _nameCtrl = TextEditingController();
  final _makeCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _registrationCtrl = TextEditingController();
  final _greetingCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _preArrivalMsgCtrl = TextEditingController();
  final _arrivalMsgCtrl = TextEditingController();
  final _bayOccupiedMsgCtrl = TextEditingController();

  DateTime? _expectedFrom;
  DateTime? _expectedUntil;
  List<String> _selectedInstallationIds = [];
  List<Map<String, dynamic>> _availableInstallations = [];
  bool _saving = false;
  bool _deleting = false;
  String? _error;

  bool get _isEditing => widget.visitor != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      final v = widget.visitor!;
      _nameCtrl.text = v['name'] as String? ?? '';
      _makeCtrl.text = v['vehicle_make'] as String? ?? '';
      _modelCtrl.text = v['vehicle_model'] as String? ?? '';
      _registrationCtrl.text = v['registration'] as String? ?? '';
      _greetingCtrl.text = v['greeting'] as String? ?? '';
      _notesCtrl.text = v['notes'] as String? ?? '';
      _preArrivalMsgCtrl.text = v['pre_arrival_message'] as String? ?? '';
      _arrivalMsgCtrl.text = v['arrival_message'] as String? ?? '';
      _bayOccupiedMsgCtrl.text = v['bay_occupied_message'] as String? ?? '';
      if (v['expected_from'] != null) {
        _expectedFrom = DateTime.parse(v['expected_from'].toString());
      }
      if (v['expected_until'] != null) {
        _expectedUntil = DateTime.parse(v['expected_until'].toString());
      }
      final ids = v['installation_ids'];
      if (ids is List) {
        _selectedInstallationIds = ids.map((e) => e.toString()).toList();
      }
    } else {
      _makeCtrl.text = widget.prefillMake ?? '';
      _modelCtrl.text = widget.prefillModel ?? '';
    }
    _loadInstallations();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _makeCtrl.dispose();
    _modelCtrl.dispose();
    _registrationCtrl.dispose();
    _greetingCtrl.dispose();
    _notesCtrl.dispose();
    _preArrivalMsgCtrl.dispose();
    _arrivalMsgCtrl.dispose();
    _bayOccupiedMsgCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadInstallations() async {
    if (widget.propertyId == null) return;
    try {
      final models = await ref.read(
        installationsProvider(widget.propertyId!).future,
      );
      if (mounted) {
        setState(() => _availableInstallations = models.map((i) => i.toMap()).toList());
      }
    } catch (e) {
      debugPrint('Load installations error: $e');
    }
  }

  Future<void> _pickDateTime(bool isFrom) async {
    final initial = isFrom
        ? (_expectedFrom?.toLocal() ?? DateTime.now())
        : (_expectedUntil?.toLocal() ??
            (_expectedFrom?.toLocal() ?? DateTime.now())
                .add(const Duration(hours: 2)));

    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Colors.white,
            onSurface: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      builder: (context, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Colors.white,
            onSurface: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (time == null || !mounted) return;

    final dt = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    ).toUtc();

    setState(() {
      if (isFrom) {
        _expectedFrom = dt;
      } else {
        _expectedUntil = dt;
      }
    });
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Name is required');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });

    final payload = <String, dynamic>{
      'name': name,
      'vehicle_make': _makeCtrl.text.trim().isNotEmpty ? _makeCtrl.text.trim() : null,
      'vehicle_model':
          _modelCtrl.text.trim().isNotEmpty ? _modelCtrl.text.trim() : null,
      'registration': _registrationCtrl.text.trim().isNotEmpty
          ? _registrationCtrl.text.trim()
          : null,
      'greeting': _greetingCtrl.text.trim().isNotEmpty
          ? _greetingCtrl.text.trim()
          : null,
      'notes':
          _notesCtrl.text.trim().isNotEmpty ? _notesCtrl.text.trim() : null,
      'expected_from': _expectedFrom?.toUtc().toIso8601String(),
      'expected_until': _expectedUntil?.toUtc().toIso8601String(),
      'pre_arrival_message': _preArrivalMsgCtrl.text.trim().isNotEmpty
          ? _preArrivalMsgCtrl.text.trim()
          : null,
      'arrival_message': _arrivalMsgCtrl.text.trim().isNotEmpty
          ? _arrivalMsgCtrl.text.trim()
          : null,
      'bay_occupied_message': _bayOccupiedMsgCtrl.text.trim().isNotEmpty
          ? _bayOccupiedMsgCtrl.text.trim()
          : null,
      'installation_ids':
          _selectedInstallationIds.isNotEmpty ? _selectedInstallationIds : null,
      'is_active': true,
    };

    try {
      final client = Supabase.instance.client;
      if (_isEditing) {
        await client
            .from('visitors')
            .update(payload)
            .eq('id', widget.visitor!['id']);
      } else {
        await client.from('visitors').insert({
          ...payload,
          'installation_id': widget.installationId,
        });
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint('Save visitor error: $e');
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Failed to save. Please try again.';
        });
      }
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF111111),
        title: const Text(
          'Delete Visitor',
          style: TextStyle(
            color: Colors.white,
            fontSize: 15,
            letterSpacing: 1,
          ),
        ),
        content: const Text(
          'This will permanently remove this visitor. This cannot be undone.',
          style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'CANCEL',
              style: TextStyle(color: Colors.white38, letterSpacing: 1),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'DELETE',
              style: TextStyle(color: Colors.redAccent, letterSpacing: 1),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      await Supabase.instance.client
          .from('visitors')
          .update({'is_active': false}).eq('id', widget.visitor!['id']);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint('Delete visitor error: $e');
      if (mounted) setState(() => _deleting = false);
    }
  }

  Widget _buildField(
    TextEditingController ctrl,
    String label,
    String hint, {
    int maxLines = 1,
  }) {
    return TextField(
      controller: ctrl,
      style: const TextStyle(color: Colors.white),
      maxLines: maxLines,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white38),
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white24),
        enabledBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.white24),
        ),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.white),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          _isEditing ? 'EDIT VISITOR' : 'ADD VISITOR',
          style: const TextStyle(
            fontSize: 13,
            letterSpacing: 4,
            fontWeight: FontWeight.w300,
          ),
        ),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 1,
                  color: Colors.white24,
                ),
              ),
            )
          else
            TextButton(
              onPressed: _save,
              child: const Text(
                'SAVE',
                style: TextStyle(
                  color: Colors.white,
                  letterSpacing: 2,
                  fontSize: 13,
                ),
              ),
            ),
        ],
      ),
      body: _deleting
          ? const Center(
              child: CircularProgressIndicator(
                color: Colors.white24,
                strokeWidth: 1,
              ),
            )
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  _buildField(_nameCtrl, 'Name *', 'e.g. Simon'),
                  const SizedBox(height: 16),
                  _buildField(_makeCtrl, 'Vehicle make', 'e.g. BMW'),
                  const SizedBox(height: 16),
                  _buildField(_modelCtrl, 'Vehicle model', 'e.g. 3 Series'),
                  const SizedBox(height: 16),
                  _buildField(
                    _registrationCtrl,
                    'Registration',
                    'e.g. CA 123 456',
                  ),
                  const SizedBox(height: 16),
                  _buildField(
                    _greetingCtrl,
                    'Greeting',
                    'e.g. Welcome, Simon',
                  ),
                  const SizedBox(height: 32),

                  const Text(
                    'ARRIVAL WINDOW',
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 3,
                      color: Colors.white24,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _DateTimeRow(
                    label: 'From',
                    value: _expectedFrom,
                    onTap: () => _pickDateTime(true),
                    onClear: () => setState(() => _expectedFrom = null),
                  ),
                  const SizedBox(height: 12),
                  _DateTimeRow(
                    label: 'Until',
                    value: _expectedUntil,
                    onTap: () => _pickDateTime(false),
                    onClear: () => setState(() => _expectedUntil = null),
                  ),

                  const SizedBox(height: 32),
                  const Text(
                    'MESSAGES',
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 3,
                      color: Colors.white24,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildField(
                    _preArrivalMsgCtrl,
                    'Pre-arrival message',
                    'Welcome Dr Andrews, please park here',
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),
                  _buildField(
                    _arrivalMsgCtrl,
                    'Arrival message',
                    'Welcome Dr Andrews! Guest WiFi: 123456qwert',
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),
                  _buildField(
                    _bayOccupiedMsgCtrl,
                    'Bay occupied message',
                    'Kindly use another bay, Dr Andrews is expected shortly',
                    maxLines: 2,
                  ),

                  if (_availableInstallations.isNotEmpty) ...[
                    const SizedBox(height: 32),
                    const Text(
                      'AURA SELECTION',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 3,
                        color: Colors.white24,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Leave empty to apply to all Auras',
                      style: TextStyle(color: Colors.white24, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    ..._availableInstallations.map((inst) {
                      final id = inst['id'] as String;
                      final selected = _selectedInstallationIds.contains(id);
                      return GestureDetector(
                        onTap: () => setState(() {
                          if (selected) {
                            _selectedInstallationIds.remove(id);
                          } else {
                            _selectedInstallationIds.add(id);
                          }
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: const BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: Colors.white12),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                selected
                                    ? Icons.check_box
                                    : Icons.check_box_outline_blank,
                                color: selected ? Colors.white : Colors.white38,
                                size: 18,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                inst['name'] as String? ?? 'Aura',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w300,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],

                  const SizedBox(height: 32),
                  _buildField(
                    _notesCtrl,
                    'Notes',
                    'Optional notes',
                    maxLines: 3,
                  ),

                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 13,
                      ),
                    ),
                  ],

                  if (_isEditing) ...[
                    const SizedBox(height: 48),
                    Center(
                      child: TextButton(
                        onPressed: _delete,
                        child: const Text(
                          'DELETE VISITOR',
                          style: TextStyle(
                            color: Colors.redAccent,
                            fontSize: 12,
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Date/time picker row
// ─────────────────────────────────────────────────────────────────────────────

class _DateTimeRow extends StatelessWidget {
  final String label;
  final DateTime? value;
  final VoidCallback onTap;
  final VoidCallback onClear;

  const _DateTimeRow({
    required this.label,
    required this.value,
    required this.onTap,
    required this.onClear,
  });

  static String _format(DateTime dt) {
    final local = dt.toLocal();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '${days[local.weekday - 1]} ${local.day} ${months[local.month - 1]}, $h:$m';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.white24)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 40,
              child: Text(
                label,
                style: const TextStyle(color: Colors.white38, fontSize: 14),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                value != null ? _format(value!) : 'Tap to set',
                style: TextStyle(
                  color: value != null ? Colors.white : Colors.white24,
                  fontSize: 14,
                ),
              ),
            ),
            if (value != null)
              GestureDetector(
                onTap: onClear,
                child: const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(Icons.clear, color: Colors.white24, size: 16),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Profile picker bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class _ProfilePickerSheet extends StatelessWidget {
  final List<Map<String, dynamic>> profiles;

  const _ProfilePickerSheet({required this.profiles});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: const Text(
              'SELECT PROFILE',
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 4,
                color: Colors.white38,
              ),
            ),
          ),
          ...profiles.map(
            (p) => InkWell(
              onTap: () => Navigator.pop(context, p),
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.white12)),
                ),
                child: Text(
                  p['display_name'] as String? ?? 'Unknown',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w300,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Add vehicle to profile screen
// ─────────────────────────────────────────────────────────────────────────────

class _AddVehicleScreen extends StatefulWidget {
  final String profileId;
  final String profileName;
  final String? prefillMake;
  final String? prefillModel;
  final dynamic unknownVehicleId;

  const _AddVehicleScreen({
    required this.profileId,
    required this.profileName,
    required this.unknownVehicleId,
    this.prefillMake,
    this.prefillModel,
  });

  @override
  State<_AddVehicleScreen> createState() => _AddVehicleScreenState();
}

class _AddVehicleScreenState extends State<_AddVehicleScreen> {
  final _makeCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _colourCtrl = TextEditingController();
  final _registrationCtrl = TextEditingController();
  final _nicknameCtrl = TextEditingController();
  final _ownerNameCtrl = TextEditingController();
  final _ownerGreetingCtrl = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _makeCtrl.text = widget.prefillMake ?? '';
    _modelCtrl.text = widget.prefillModel ?? '';
    _ownerNameCtrl.text = widget.profileName;
  }

  @override
  void dispose() {
    _makeCtrl.dispose();
    _modelCtrl.dispose();
    _colourCtrl.dispose();
    _registrationCtrl.dispose();
    _nicknameCtrl.dispose();
    _ownerNameCtrl.dispose();
    _ownerGreetingCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final make = _makeCtrl.text.trim();
    if (make.isEmpty) {
      setState(() => _error = 'Make is required');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final client = Supabase.instance.client;

      final vehicleRow = await client
          .from('vehicles')
          .insert({
            'profile_id': widget.profileId,
            'make': make,
            'model': _modelCtrl.text.trim().isNotEmpty
                ? _modelCtrl.text.trim()
                : null,
            'colour': _colourCtrl.text.trim().isNotEmpty
                ? _colourCtrl.text.trim()
                : null,
            'registration': _registrationCtrl.text.trim().isNotEmpty
                ? _registrationCtrl.text.trim()
                : null,
            'nickname': _nicknameCtrl.text.trim().isNotEmpty
                ? _nicknameCtrl.text.trim()
                : null,
            'owner_name': _ownerNameCtrl.text.trim().isNotEmpty
                ? _ownerNameCtrl.text.trim()
                : null,
            'owner_greeting': _ownerGreetingCtrl.text.trim().isNotEmpty
                ? _ownerGreetingCtrl.text.trim()
                : null,
            'is_active': true,
          })
          .select('id')
          .single();

      await client.from('unknown_vehicles').update({
        'status': 'assigned',
        'assigned_vehicle_id': vehicleRow['id'],
        'assigned_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', widget.unknownVehicleId);

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint('Add vehicle error: $e');
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Failed to save. Please try again.';
        });
      }
    }
  }

  Widget _buildField(
    TextEditingController ctrl,
    String label,
    String hint, {
    int maxLines = 1,
  }) {
    return TextField(
      controller: ctrl,
      style: const TextStyle(color: Colors.white),
      maxLines: maxLines,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white38),
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white24),
        enabledBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.white24),
        ),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.white),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'ADD VEHICLE',
          style: TextStyle(
            fontSize: 13,
            letterSpacing: 4,
            fontWeight: FontWeight.w300,
          ),
        ),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 1,
                  color: Colors.white24,
                ),
              ),
            )
          else
            TextButton(
              onPressed: _save,
              child: const Text(
                'SAVE',
                style: TextStyle(
                  color: Colors.white,
                  letterSpacing: 2,
                  fontSize: 13,
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Profile: ${widget.profileName}',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
            const SizedBox(height: 24),
            _buildField(_makeCtrl, 'Make *', 'e.g. BMW'),
            const SizedBox(height: 16),
            _buildField(_modelCtrl, 'Model', 'e.g. 3 Series'),
            const SizedBox(height: 16),
            _buildField(_colourCtrl, 'Colour', 'e.g. White'),
            const SizedBox(height: 16),
            _buildField(_registrationCtrl, 'Registration', 'e.g. CA 123 456'),
            const SizedBox(height: 16),
            _buildField(_nicknameCtrl, 'Nickname', 'e.g. Dad\'s BMW'),
            const SizedBox(height: 32),
            const Text(
              'DISPLAY',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 3,
                color: Colors.white24,
              ),
            ),
            const SizedBox(height: 16),
            _buildField(_ownerNameCtrl, 'Owner name', 'e.g. Simon'),
            const SizedBox(height: 16),
            _buildField(
              _ownerGreetingCtrl,
              'Greeting',
              'e.g. Welcome back, Simon',
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style:
                    const TextStyle(color: Colors.redAccent, fontSize: 13),
              ),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
