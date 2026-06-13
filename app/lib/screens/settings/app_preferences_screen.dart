import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../providers/property_provider.dart';

class AppPreferencesScreen extends ConsumerStatefulWidget {
  const AppPreferencesScreen({super.key});

  @override
  ConsumerState<AppPreferencesScreen> createState() =>
      _AppPreferencesScreenState();
}

class _AppPreferencesScreenState extends ConsumerState<AppPreferencesScreen> {
  bool _loading = true;
  bool _saving = false;

  String? _defaultPropertyId; // null = "No preference"
  String _units = 'metric';
  String _timeFormat = '24h';
  String _dateFormat = 'dd/mm/yyyy';
  String _language = 'en';

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final response = await client
          .from('app_preferences')
          .select()
          .eq('user_id', userId)
          .maybeSingle();
      if (response != null && mounted) {
        setState(() {
          _defaultPropertyId = response['default_property_id'] as String?;
          _units = response['units'] as String? ?? 'metric';
          _timeFormat = response['time_format'] as String? ?? '24h';
          _dateFormat = response['date_format'] as String? ?? 'dd/mm/yyyy';
          _language = response['language'] as String? ?? 'en';
        });
      }
    } catch (e) {
      debugPrint('Load app_preferences error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) setState(() => _saving = false);
      return;
    }
    try {
      await client.from('app_preferences').upsert({
        'user_id': userId,
        'default_property_id': _defaultPropertyId,
        'units': _units,
        'time_format': _timeFormat,
        'date_format': _dateFormat,
        'language': _language,
      }, onConflict: 'user_id');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint('Save app_preferences error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to save preferences.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _sectionHeader(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 10,
            letterSpacing: 3,
            color: Colors.white24,
          ),
        ),
      );

  Widget _dropdown<T>({
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
    bool enabled = true,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: DropdownButtonFormField<T>(
        initialValue: value,
        dropdownColor: const Color(0xFF1A1A1A),
        style: TextStyle(
          color: enabled ? Colors.white : Colors.white38,
          fontSize: 14,
          fontWeight: FontWeight.w300,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white38),
          enabledBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.white24),
          ),
          focusedBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.white),
          ),
          disabledBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.white12),
          ),
          isDense: true,
        ),
        items: items,
        onChanged: enabled ? onChanged : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final propertiesAsync = ref.watch(propertiesProvider);
    final properties = propertiesAsync.valueOrNull ?? [];

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'APP PREFERENCES',
          style: TextStyle(
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
                    // ── DEFAULT PROPERTY ────────────────────────────────────
                    _sectionHeader('DEFAULT PROPERTY'),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: DropdownButtonFormField<String?>(
                        initialValue: _defaultPropertyId,
                        dropdownColor: const Color(0xFF1A1A1A),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w300,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Default Property',
                          labelStyle: TextStyle(color: Colors.white38),
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.white24),
                          ),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.white),
                          ),
                          isDense: true,
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('No preference (show all)'),
                          ),
                          ...properties.map(
                            (p) => DropdownMenuItem<String?>(
                              value: p.id,
                              child: Text(p.name),
                            ),
                          ),
                        ],
                        onChanged: (v) =>
                            setState(() => _defaultPropertyId = v),
                      ),
                    ),

                    const SizedBox(height: 8),

                    // ── UNITS ───────────────────────────────────────────────
                    _sectionHeader('UNITS'),
                    _dropdown<String>(
                      label: 'Units',
                      value: _units,
                      items: const [
                        DropdownMenuItem(value: 'metric', child: Text('Metric')),
                        DropdownMenuItem(
                            value: 'imperial', child: Text('Imperial')),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _units = v);
                      },
                    ),

                    const SizedBox(height: 8),

                    // ── DATE & TIME FORMAT ──────────────────────────────────
                    _sectionHeader('DATE & TIME FORMAT'),
                    _dropdown<String>(
                      label: 'Time Format',
                      value: _timeFormat,
                      items: const [
                        DropdownMenuItem(
                            value: '24h', child: Text('24-hour')),
                        DropdownMenuItem(
                            value: '12h', child: Text('12-hour')),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _timeFormat = v);
                      },
                    ),
                    _dropdown<String>(
                      label: 'Date Format',
                      value: _dateFormat,
                      items: const [
                        DropdownMenuItem(
                            value: 'dd/mm/yyyy', child: Text('DD/MM/YYYY')),
                        DropdownMenuItem(
                            value: 'mm/dd/yyyy', child: Text('MM/DD/YYYY')),
                        DropdownMenuItem(
                            value: 'yyyy-mm-dd', child: Text('YYYY-MM-DD')),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _dateFormat = v);
                      },
                    ),

                    const SizedBox(height: 8),

                    // ── LANGUAGE ────────────────────────────────────────────
                    _sectionHeader('LANGUAGE'),
                    _dropdown<String>(
                      label: 'Language',
                      value: _language,
                      enabled: false,
                      items: const [
                        DropdownMenuItem(value: 'en', child: Text('English')),
                      ],
                      onChanged: (_) {},
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 2, bottom: 8),
                      child: Text(
                        'More languages coming soon',
                        style: TextStyle(color: Colors.white24, fontSize: 11),
                      ),
                    ),

                    const SizedBox(height: 32),
                  ],
                ),
        ),
      ),
    );
  }
}
