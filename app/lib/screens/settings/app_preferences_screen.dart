import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../providers/property_provider.dart';
import '../../theme/aura_theme.dart';

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
          SnackBar(
            content: Text('Failed to save preferences.', style: kBody()),
            backgroundColor: kError,
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
          style: kLabel(),
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
        dropdownColor: kCard,
        style: TextStyle(
          color: enabled ? const Color(0xD9FFFFFF) : const Color(0x66FFFFFF),
          fontSize: 15,
          fontWeight: FontWeight.w400,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: kCaption(),
          enabledBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: kInputBorder),
          ),
          focusedBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: kViolet),
          ),
          disabledBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: kRowDivider),
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
      backgroundColor: kVoid,
      appBar: AppBar(
        backgroundColor: kVoid,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'App Preferences',
          style: kHeading(),
        ),
        actions: [
          _saving
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Center(
                    child: SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        color: kViolet,
                        strokeWidth: 1.5,
                      ),
                    ),
                  ),
                )
              : TextButton(
                  onPressed: _save,
                  child: Text(
                    'Save',
                    style: kBody(kVioletText),
                  ),
                ),
        ],
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Container(
          decoration: const BoxDecoration(gradient: kBgGradient),
          child: SafeArea(
            child: _loading
                ? Center(
                    child: CircularProgressIndicator(
                      color: kViolet,
                      strokeWidth: 1.5,
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
                          dropdownColor: kCard,
                          style: TextStyle(
                            color: const Color(0xD9FFFFFF),
                            fontSize: 15,
                            fontWeight: FontWeight.w400,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Default Property',
                            labelStyle: kCaption(),
                            enabledBorder: const UnderlineInputBorder(
                              borderSide: BorderSide(color: kInputBorder),
                            ),
                            focusedBorder: const UnderlineInputBorder(
                              borderSide: BorderSide(color: kViolet),
                            ),
                            isDense: true,
                          ),
                          items: [
                            DropdownMenuItem<String?>(
                              value: null,
                              child: Text('No preference (show all)', style: kBody()),
                            ),
                            ...properties.map(
                              (p) => DropdownMenuItem<String?>(
                                value: p.id,
                                child: Text(p.name, style: kBody()),
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
                        items: [
                          DropdownMenuItem(value: 'metric', child: Text('Metric', style: kBody())),
                          DropdownMenuItem(
                              value: 'imperial', child: Text('Imperial', style: kBody())),
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
                        items: [
                          DropdownMenuItem(
                              value: '24h', child: Text('24-hour', style: kBody())),
                          DropdownMenuItem(
                              value: '12h', child: Text('12-hour', style: kBody())),
                        ],
                        onChanged: (v) {
                          if (v != null) setState(() => _timeFormat = v);
                        },
                      ),
                      _dropdown<String>(
                        label: 'Date Format',
                        value: _dateFormat,
                        items: [
                          DropdownMenuItem(
                              value: 'dd/mm/yyyy', child: Text('DD/MM/YYYY', style: kBody())),
                          DropdownMenuItem(
                              value: 'mm/dd/yyyy', child: Text('MM/DD/YYYY', style: kBody())),
                          DropdownMenuItem(
                              value: 'yyyy-mm-dd', child: Text('YYYY-MM-DD', style: kBody())),
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
                        items: [
                          DropdownMenuItem(value: 'en', child: Text('English', style: kBody())),
                        ],
                        onChanged: (_) {},
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 2, bottom: 8),
                        child: Text(
                          'More languages coming soon',
                          style: kCaption(),
                        ),
                      ),

                      const SizedBox(height: 32),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
