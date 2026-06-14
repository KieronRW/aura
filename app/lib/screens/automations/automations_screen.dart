// Automations screen — manage event-driven rules

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────────────

const _kSectionStyle = TextStyle(
  fontSize: 10,
  letterSpacing: 3,
  color: Colors.white24,
);

// trigger_type enum value → human label (add/edit dropdown)
const _kTriggerOptions = [
  ('profile_detected', 'Specific person arrives'),
  ('any_resident_detected', 'Any resident arrives'),
  ('visitor_arrival', 'Expected visitor arrives'),
  ('unknown_vehicle', 'Unknown vehicle detected'),
  ('departure', 'Vehicle departs'),
  ('bay_occupied', 'Parking bay becomes occupied'),
  ('bay_empty', 'Parking bay becomes empty'),
  ('aura_offline', 'Aura goes offline'),
  ('aura_online', 'Aura comes back online'),
];

// action_type enum value → human label
const _kActionOptions = [
  ('webhook', 'Send webhook'),
  ('notification', 'Push notification'),
];

String _triggerLabel(String? type) {
  for (final t in _kTriggerOptions) {
    if (t.$1 == type) return t.$2;
  }
  return type ?? '—';
}

String _actionLabel(String? type) {
  for (final a in _kActionOptions) {
    if (a.$1 == type) return a.$2;
  }
  return type ?? '—';
}

// ─────────────────────────────────────────────────────────────────────────────
// List screen — embedded as a tab (no Scaffold)
// ─────────────────────────────────────────────────────────────────────────────

class AutomationsScreen extends ConsumerStatefulWidget {
  const AutomationsScreen({super.key});

  @override
  ConsumerState<AutomationsScreen> createState() => _AutomationsScreenState();
}

class _AutomationsScreenState extends ConsumerState<AutomationsScreen> {
  List<Map<String, dynamic>> _rules = [];
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
      final data = await client
          .from('automation_rules')
          .select('*, profiles(display_name)')
          .eq('user_id', userId)
          .order('created_at', ascending: true);
      if (mounted) {
        setState(() {
          _rules = List<Map<String, dynamic>>.from(data as List);
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Load automation rules error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleActive(Map<String, dynamic> rule, bool value) async {
    try {
      await Supabase.instance.client
          .from('automation_rules')
          .update({'is_active': value})
          .eq('id', rule['id']);
      setState(() {
        final idx = _rules.indexWhere((r) => r['id'] == rule['id']);
        if (idx != -1) _rules[idx] = {..._rules[idx], 'is_active': value};
      });
    } catch (e) {
      debugPrint('Toggle rule error: $e');
    }
  }

  Future<void> _openAddEdit([Map<String, dynamic>? rule]) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddEditAutomationRuleScreen(rule: rule),
      ),
    );
    if (result == true && mounted) _load();
  }

  String _triggerDescription(Map<String, dynamic> rule) {
    final type = rule['trigger_type'] as String?;
    if (type == 'profile_detected') {
      final profile = rule['profiles'];
      final name = profile is Map
          ? profile['display_name'] as String? ?? 'someone'
          : 'someone';
      return 'When $name arrives';
    }
    return 'When ${_triggerLabel(type).toLowerCase()}';
  }

  String _actionDescription(Map<String, dynamic> rule) {
    final type = rule['action_type'] as String?;
    if (type == 'webhook') {
      final config = rule['action_config'];
      final url = config is Map ? config['url'] as String? ?? '' : '';
      final short = url.length > 40 ? '${url.substring(0, 40)}…' : url;
      return 'Webhook → $short';
    }
    return _actionLabel(type);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        color: Colors.white,
        backgroundColor: const Color(0xFF111111),
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(
                  color: Colors.white24,
                  strokeWidth: 1,
                ),
              )
            : CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 24, 8, 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'AUTOMATION RULES',
                            style: TextStyle(
                              fontSize: 11,
                              letterSpacing: 4,
                              color: Colors.white38,
                            ),
                          ),
                          IconButton(
                            onPressed: () => _openAddEdit(),
                            icon: const Icon(Icons.add, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_rules.isEmpty)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Padding(
                          padding: EdgeInsets.all(40),
                          child: Text(
                            'No automation rules yet.\nAura can notify your smart home system the moment someone arrives.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white24,
                              fontSize: 13,
                              height: 1.7,
                            ),
                          ),
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final rule = _rules[index];
                            final active = rule['is_active'] as bool? ?? true;
                            return GestureDetector(
                              onTap: () => _openAddEdit(rule),
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF111111),
                                  border: Border.all(color: Colors.white12),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            rule['name'] as String? ?? 'Unnamed rule',
                                            style: TextStyle(
                                              color: active ? Colors.white : Colors.white38,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w300,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            _triggerDescription(rule),
                                            style: const TextStyle(
                                              color: Colors.white38,
                                              fontSize: 12,
                                            ),
                                          ),
                                          Text(
                                            _actionDescription(rule),
                                            style: const TextStyle(
                                              color: Colors.white24,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Switch(
                                      value: active,
                                      onChanged: (v) => _toggleActive(rule, v),
                                      activeThumbColor: Colors.white,
                                      activeTrackColor: Colors.white24,
                                      inactiveThumbColor: Colors.white38,
                                      inactiveTrackColor: Colors.white12,
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                          childCount: _rules.length,
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Add / Edit screen
// ─────────────────────────────────────────────────────────────────────────────

class AddEditAutomationRuleScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic>? rule;

  const AddEditAutomationRuleScreen({super.key, this.rule});

  @override
  ConsumerState<AddEditAutomationRuleScreen> createState() =>
      _AddEditAutomationRuleScreenState();
}

class _AddEditAutomationRuleScreenState
    extends ConsumerState<AddEditAutomationRuleScreen> {
  final _nameCtrl = TextEditingController();
  final _webhookUrlCtrl = TextEditingController();
  final _headersCtrl = TextEditingController();

  String? _triggerType;
  String? _profileId;
  String _actionType = 'webhook';
  bool _isActive = true;
  bool _appliesToAll = true;
  Set<String> _selectedInstallationIds = {};

  bool _saving = false;
  bool _loadingData = true;
  String? _error;

  List<Map<String, dynamic>> _profiles = [];
  // Each entry: {id, name, propertyName}
  List<Map<String, dynamic>> _installations = [];

  bool get _isEditing => widget.rule != null;

  @override
  void initState() {
    super.initState();
    _populateFromRule();
    _loadData();
  }

  void _populateFromRule() {
    final rule = widget.rule;
    if (rule == null) return;

    _nameCtrl.text = rule['name'] as String? ?? '';
    _triggerType = rule['trigger_type'] as String?;
    _profileId = rule['profile_id'] as String?;
    _actionType = rule['action_type'] as String? ?? 'webhook';
    _isActive = rule['is_active'] as bool? ?? true;

    final ids = rule['installation_ids'];
    if (ids is List && ids.isNotEmpty) {
      _appliesToAll = false;
      _selectedInstallationIds = ids.map((e) => e.toString()).toSet();
    } else {
      _appliesToAll = true;
    }

    final config = rule['action_config'];
    if (config is Map) {
      _webhookUrlCtrl.text = config['url'] as String? ?? '';
      final headers = config['headers'];
      if (headers is Map) {
        _headersCtrl.text = const JsonEncoder.withIndent('  ').convert(headers);
      } else if (headers is String) {
        _headersCtrl.text = headers;
      }
    }
  }

  Future<void> _loadData() async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id ?? '';
    try {
      final installationsRaw = await client
          .from('installations')
          .select('id, name, properties(name)')
          .eq('claimed_by', userId)
          .eq('status', 'active');

      final List<Map<String, dynamic>> installations = [];
      for (final i in installationsRaw as List) {
        final props = i['properties'];
        installations.add({
          'id': i['id'],
          'name': i['name'] ?? 'Aura',
          'propertyName': props is Map ? props['name'] as String? ?? '' : '',
        });
      }

      final installationIds = installations.map((i) => i['id'] as String).toList();

      List<Map<String, dynamic>> profiles = [];
      if (installationIds.isNotEmpty) {
        final profilesRaw = await client
            .from('profiles')
            .select('id, display_name')
            .inFilter('installation_id', installationIds)
            .eq('is_active', true)
            .order('display_name');
        profiles = List<Map<String, dynamic>>.from(profilesRaw as List);
      }

      if (mounted) {
        setState(() {
          _installations = installations;
          _profiles = profiles;
          _loadingData = false;
        });
      }
    } catch (e) {
      debugPrint('Load automation data error: $e');
      if (mounted) setState(() => _loadingData = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _webhookUrlCtrl.dispose();
    _headersCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Name is required');
      return;
    }
    if (_triggerType == null) {
      setState(() => _error = 'Please select a trigger');
      return;
    }
    if (_actionType == 'webhook' && _webhookUrlCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Webhook URL is required');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      // Build action_config
      Map<String, dynamic> actionConfig = {};
      if (_actionType == 'webhook') {
        final headersText = _headersCtrl.text.trim();
        dynamic headers;
        if (headersText.isNotEmpty) {
          try {
            headers = jsonDecode(headersText);
          } catch (_) {
            headers = headersText;
          }
        }
        actionConfig = {
          'url': _webhookUrlCtrl.text.trim(),
          'headers': ?headers,
        };
      }

      final client = Supabase.instance.client;
      final payload = {
        'name': name,
        'trigger_type': _triggerType,
        'profile_id': _triggerType == 'profile_detected' ? _profileId : null,
        'installation_ids': _appliesToAll
            ? null
            : _selectedInstallationIds.toList(),
        'action_type': _actionType,
        'action_config': actionConfig,
        'is_active': _isActive,
      };

      if (_isEditing) {
        await client
            .from('automation_rules')
            .update(payload)
            .eq('id', widget.rule!['id']);
      } else {
        await client.from('automation_rules').insert({
          ...payload,
          'user_id': client.auth.currentUser!.id,
        });
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint('Save automation rule error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to save. Please try again.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF111111),
        title: const Text(
          'DELETE RULE',
          style: TextStyle(
            color: Colors.white,
            fontSize: 13,
            letterSpacing: 3,
            fontWeight: FontWeight.w300,
          ),
        ),
        content: const Text(
          'Delete this automation rule? This cannot be undone.',
          style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL',
                style: TextStyle(color: Colors.white70, letterSpacing: 2)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('DELETE',
                style: TextStyle(color: Colors.redAccent, letterSpacing: 2)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await Supabase.instance.client
          .from('automation_rules')
          .delete()
          .eq('id', widget.rule!['id']);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint('Delete automation rule error: $e');
    }
  }

  Widget _sectionHeader(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Text(text, style: _kSectionStyle),
      );

  Widget _textField(
    TextEditingController ctrl,
    String label, {
    String? hint,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: ctrl,
        style: const TextStyle(color: Colors.white),
        maxLines: maxLines,
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
          isDense: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Group installations by property for the multi-select UI
    final Map<String, List<Map<String, dynamic>>> byProperty = {};
    for (final inst in _installations) {
      final propName = inst['propertyName'] as String? ?? '';
      byProperty.putIfAbsent(propName, () => []).add(inst);
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          _isEditing ? 'EDIT RULE' : 'NEW RULE',
          style: const TextStyle(
            fontSize: 13,
            letterSpacing: 4,
            fontWeight: FontWeight.w300,
          ),
        ),
        actions: [
          _saving
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Center(
                    child: SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        color: Colors.white38,
                        strokeWidth: 1.5,
                      ),
                    ),
                  ),
                )
              : TextButton(
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
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
          child: _loadingData
              ? const Center(
                  child: CircularProgressIndicator(
                    color: Colors.white24,
                    strokeWidth: 1,
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    // ── RULE DETAILS ───────────────────────────────────────
                    _sectionHeader('RULE DETAILS'),
                    _textField(_nameCtrl, 'Name *', hint: 'e.g. Notify on arrival'),

                    // ── TRIGGER ────────────────────────────────────────────
                    const SizedBox(height: 8),
                    _sectionHeader('TRIGGER'),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: DropdownButtonFormField<String>(
                        initialValue: _triggerType,
                        dropdownColor: const Color(0xFF1A1A1A),
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: const InputDecoration(
                          labelText: 'When this happens',
                          labelStyle: TextStyle(color: Colors.white38),
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.white24),
                          ),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.white),
                          ),
                          isDense: true,
                        ),
                        hint: const Text('Select trigger',
                            style: TextStyle(color: Colors.white24)),
                        items: _kTriggerOptions
                            .map((t) => DropdownMenuItem(
                                  value: t.$1,
                                  child: Text(t.$2),
                                ))
                            .toList(),
                        onChanged: (v) =>
                            setState(() {
                              _triggerType = v;
                              if (v != 'profile_detected') _profileId = null;
                            }),
                      ),
                    ),

                    // Profile picker — only for profile_detected
                    if (_triggerType == 'profile_detected') ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: DropdownButtonFormField<String>(
                          initialValue: _profileId,
                          dropdownColor: const Color(0xFF1A1A1A),
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          decoration: const InputDecoration(
                            labelText: 'Person',
                            labelStyle: TextStyle(color: Colors.white38),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.white24),
                            ),
                            focusedBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.white),
                            ),
                            isDense: true,
                          ),
                          hint: const Text('Select person',
                              style: TextStyle(color: Colors.white24)),
                          items: _profiles
                              .map((p) => DropdownMenuItem(
                                    value: p['id'] as String,
                                    child: Text(
                                        p['display_name'] as String? ?? 'Unknown'),
                                  ))
                              .toList(),
                          onChanged: (v) => setState(() => _profileId = v),
                        ),
                      ),
                    ],

                    // ── APPLIES TO ─────────────────────────────────────────
                    const SizedBox(height: 8),
                    _sectionHeader('APPLIES TO'),
                    _AppliesTo(
                      appliesToAll: _appliesToAll,
                      selectedIds: _selectedInstallationIds,
                      installationsByProperty: byProperty,
                      onAppliesToAllChanged: (v) =>
                          setState(() => _appliesToAll = v),
                      onSelectionChanged: (ids) =>
                          setState(() => _selectedInstallationIds = ids),
                    ),

                    // ── ACTION ─────────────────────────────────────────────
                    const SizedBox(height: 8),
                    _sectionHeader('ACTION'),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: DropdownButtonFormField<String>(
                        initialValue: _actionType,
                        dropdownColor: const Color(0xFF1A1A1A),
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: const InputDecoration(
                          labelText: 'Do this',
                          labelStyle: TextStyle(color: Colors.white38),
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.white24),
                          ),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.white),
                          ),
                          isDense: true,
                        ),
                        items: _kActionOptions
                            .map((a) => DropdownMenuItem(
                                  value: a.$1,
                                  child: Text(a.$2),
                                ))
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _actionType = v ?? 'webhook'),
                      ),
                    ),

                    if (_actionType == 'webhook') ...[
                      _textField(
                        _webhookUrlCtrl,
                        'Webhook URL *',
                        hint: 'https://example.com/webhook',
                      ),
                      _textField(
                        _headersCtrl,
                        'Custom Headers (JSON, optional)',
                        hint: '{"Authorization": "Bearer ..."}',
                        maxLines: 4,
                      ),
                    ],

                    // ── ACTIVE ─────────────────────────────────────────────
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: const BoxDecoration(
                        border: Border(
                            bottom: BorderSide(color: Colors.white12)),
                      ),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Active',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w300,
                              ),
                            ),
                          ),
                          Switch(
                            value: _isActive,
                            onChanged: (v) => setState(() => _isActive = v),
                            activeThumbColor: Colors.white,
                            activeTrackColor: Colors.white24,
                            inactiveThumbColor: Colors.white38,
                            inactiveTrackColor: Colors.white12,
                          ),
                        ],
                      ),
                    ),

                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        style: const TextStyle(
                            color: Colors.redAccent, fontSize: 13),
                      ),
                    ],

                    if (_isEditing) ...[
                      const SizedBox(height: 48),
                      Center(
                        child: TextButton(
                          onPressed: _delete,
                          child: const Text(
                            'DELETE RULE',
                            style: TextStyle(
                              color: Colors.redAccent,
                              fontSize: 12,
                              letterSpacing: 2,
                            ),
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 32),
                  ],
                ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Applies-To widget
// ─────────────────────────────────────────────────────────────────────────────

class _AppliesTo extends StatelessWidget {
  final bool appliesToAll;
  final Set<String> selectedIds;
  final Map<String, List<Map<String, dynamic>>> installationsByProperty;
  final ValueChanged<bool> onAppliesToAllChanged;
  final ValueChanged<Set<String>> onSelectionChanged;

  const _AppliesTo({
    required this.appliesToAll,
    required this.selectedIds,
    required this.installationsByProperty,
    required this.onAppliesToAllChanged,
    required this.onSelectionChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _RadioRow(
          label: 'Any Aura',
          selected: appliesToAll,
          onTap: () => onAppliesToAllChanged(true),
        ),
        _RadioRow(
          label: 'Specific Aura(s)',
          selected: !appliesToAll,
          onTap: () => onAppliesToAllChanged(false),
        ),
        if (!appliesToAll) ...[
          const SizedBox(height: 8),
          ...installationsByProperty.entries.expand((entry) {
            final propName = entry.key;
            final installations = entry.value;
            return [
              if (propName.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 4),
                  child: Text(
                    propName.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white24,
                      fontSize: 10,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              ...installations.map((inst) {
                final id = inst['id'] as String;
                final checked = selectedIds.contains(id);
                return InkWell(
                  onTap: () {
                    final next = Set<String>.from(selectedIds);
                    if (checked) {
                      next.remove(id);
                    } else {
                      next.add(id);
                    }
                    onSelectionChanged(next);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Icon(
                          checked
                              ? Icons.check_box
                              : Icons.check_box_outline_blank,
                          color: checked ? Colors.white : Colors.white24,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          inst['name'] as String? ?? 'Aura',
                          style: TextStyle(
                            color: checked ? Colors.white : Colors.white38,
                            fontSize: 14,
                            fontWeight: FontWeight.w300,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ];
          }),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _RadioRow extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _RadioRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? Colors.white : Colors.white24,
              size: 20,
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : Colors.white38,
                fontSize: 14,
                fontWeight: FontWeight.w300,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
