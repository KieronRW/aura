import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../providers/installation_provider.dart';
import '../../providers/property_provider.dart';
import 'aura_settings_screen.dart';

const _kSectionStyle = TextStyle(
  fontSize: 10,
  letterSpacing: 3,
  color: Colors.white24,
);

const _kPropertyTypes = [
  'Residential',
  'Office',
  'Commercial',
  'Industrial',
  'Showroom',
];

const _kToneMap = {
  'Residential': 'Friendly & Casual',
  'Office': 'Formal but Friendly',
  'Commercial': 'Professional',
  'Industrial': 'Safety-focused',
  'Showroom': 'Friendly & Professional',
};

class LocationDetailScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> property;

  const LocationDetailScreen({super.key, required this.property});

  @override
  ConsumerState<LocationDetailScreen> createState() =>
      _LocationDetailScreenState();
}

class _LocationDetailScreenState extends ConsumerState<LocationDetailScreen> {
  final _nameCtrl = TextEditingController();
  final _countryCtrl = TextEditingController();
  final _provinceCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _streetCtrl = TextEditingController();
  final _postalCtrl = TextEditingController();
  final _toneCtrl = TextEditingController();
  final _safetyCtrl = TextEditingController();

  String? _propertyType;
  bool _toneManuallyEdited = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.property;
    _nameCtrl.text = p['name'] as String? ?? '';
    _propertyType = p['property_type'] as String?;
    _countryCtrl.text = p['country'] as String? ?? '';
    _provinceCtrl.text = p['province'] as String? ?? '';
    _cityCtrl.text = p['city'] as String? ?? '';
    _streetCtrl.text = p['street_address'] as String? ?? '';
    _postalCtrl.text = p['postal_code'] as String? ?? '';
    _toneCtrl.text = p['greeting_tone'] as String? ?? '';
    _safetyCtrl.text = p['safety_reminder'] as String? ?? '';

    // If greeting_tone already had a value, treat it as manually set so
    // selecting a property type won't overwrite it.
    if (_toneCtrl.text.isNotEmpty) _toneManuallyEdited = true;

    _toneCtrl.addListener(() => _toneManuallyEdited = true);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _countryCtrl.dispose();
    _provinceCtrl.dispose();
    _cityCtrl.dispose();
    _streetCtrl.dispose();
    _postalCtrl.dispose();
    _toneCtrl.dispose();
    _safetyCtrl.dispose();
    super.dispose();
  }

  void _onPropertyTypeChanged(String? value) {
    setState(() {
      _propertyType = value;
      if (!_toneManuallyEdited || _toneCtrl.text.isEmpty) {
        final suggestion = _kToneMap[value] ?? '';
        _toneCtrl.text = suggestion;
        // Temporarily suppress the listener flag so auto-fill doesn't count
        // as a manual edit.
        _toneManuallyEdited = false;
      }
    });
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Property name is required'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final street = _streetCtrl.text.trim();
      final city = _cityCtrl.text.trim();
      final addressParts = [street, city].where((s) => s.isNotEmpty).toList();
      final address = addressParts.isNotEmpty ? addressParts.join(', ') : null;

      await Supabase.instance.client.from('properties').update({
        'name': name,
        'address': address,
        'property_type': _propertyType,
        'country': _countryCtrl.text.trim().isNotEmpty ? _countryCtrl.text.trim() : null,
        'province': _provinceCtrl.text.trim().isNotEmpty ? _provinceCtrl.text.trim() : null,
        'city': city.isNotEmpty ? city : null,
        'street_address': street.isNotEmpty ? street : null,
        'postal_code': _postalCtrl.text.trim().isNotEmpty ? _postalCtrl.text.trim() : null,
        'greeting_tone': _toneCtrl.text.trim().isNotEmpty ? _toneCtrl.text.trim() : null,
        'safety_reminder': _safetyCtrl.text.trim().isNotEmpty ? _safetyCtrl.text.trim() : null,
      }).eq('id', widget.property['id']);

      ref.invalidate(propertiesProvider);

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint('Save location error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to save location'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteLocation() async {
    final propertyName = widget.property['name'] as String? ?? 'this location';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF111111),
        title: const Text(
          'DELETE LOCATION',
          style: TextStyle(
            color: Colors.white,
            fontSize: 13,
            letterSpacing: 3,
            fontWeight: FontWeight.w300,
          ),
        ),
        content: Text(
          "Delete '$propertyName'? All Auras at this location will be released.",
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 13,
            height: 1.6,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'CANCEL',
              style: TextStyle(color: Colors.white70, letterSpacing: 2),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'DELETE',
              style: TextStyle(color: Colors.redAccent, letterSpacing: 2),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final client = Supabase.instance.client;
      final propertyId = widget.property['id'] as String;

      // Release all installations at this property
      await client.from('installations').update({
        'status': 'unclaimed',
        'claimed_by': null,
        'property_id': null,
        'claimed_at': null,
      }).eq('property_id', propertyId);

      // Soft-delete the property
      await client.from('properties').update({'is_active': false}).eq('id', propertyId);

      ref.invalidate(propertiesProvider);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint('Delete location error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to delete location'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Widget _sectionHeader(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Text(text, style: _kSectionStyle),
      );

  Widget _field(
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
          isDense: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final propertyId = widget.property['id'] as String;
    final installationsAsync = ref.watch(installationsProvider(propertyId));

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          (_nameCtrl.text.isNotEmpty ? _nameCtrl.text : 'LOCATION').toUpperCase(),
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
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              // ── PROPERTY DETAILS ────────────────────────────────────────
              _sectionHeader('PROPERTY DETAILS'),
              _field(_nameCtrl, 'Property Name *'),
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: DropdownButtonFormField<String>(
                  initialValue: _propertyType,
                  dropdownColor: const Color(0xFF1A1A1A),
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  decoration: const InputDecoration(
                    labelText: 'Property Type',
                    labelStyle: TextStyle(color: Colors.white38),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white),
                    ),
                    isDense: true,
                  ),
                  hint: const Text(
                    'Select type',
                    style: TextStyle(color: Colors.white24),
                  ),
                  items: _kPropertyTypes
                      .map((t) => DropdownMenuItem(
                            value: t,
                            child: Text(t),
                          ))
                      .toList(),
                  onChanged: _onPropertyTypeChanged,
                ),
              ),

              const SizedBox(height: 8),

              // ── ADDRESS ─────────────────────────────────────────────────
              _sectionHeader('ADDRESS'),
              _field(_countryCtrl, 'Country'),
              _field(_provinceCtrl, 'Province / State'),
              _field(_cityCtrl, 'City / Suburb'),
              _field(_streetCtrl, 'Street Address'),
              _field(_postalCtrl, 'Postal Code'),

              const SizedBox(height: 8),

              // ── DEFAULT BEHAVIOUR ────────────────────────────────────────
              _sectionHeader('DEFAULT BEHAVIOUR'),
              _field(_toneCtrl, 'Greeting Tone'),
              _field(
                _safetyCtrl,
                'Safety Reminder',
                hint: 'Optional message shown to visitors',
                maxLines: 3,
              ),

              const SizedBox(height: 8),

              // ── AURAS AT THIS LOCATION ───────────────────────────────────
              _sectionHeader('AURAS AT THIS LOCATION'),
              installationsAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: Colors.white24,
                      strokeWidth: 1,
                    ),
                  ),
                ),
                error: (_, _) => const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: Text(
                    'Failed to load Auras',
                    style: TextStyle(color: Colors.white24, fontSize: 13),
                  ),
                ),
                data: (installationModels) {
                  if (installationModels.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.only(bottom: 16),
                      child: Text(
                        'No Auras at this location',
                        style: TextStyle(color: Colors.white24, fontSize: 13),
                      ),
                    );
                  }
                  return Column(
                    children: installationModels.map((model) {
                      final installation = model.toMap();
                      return GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AuraSettingsScreen(
                              installation: installation,
                              propertyId: propertyId,
                            ),
                          ),
                        ),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF111111),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.sensors,
                                color: Colors.white38,
                                size: 20,
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Text(
                                  installation['name'] as String? ?? 'Aura',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w300,
                                  ),
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right,
                                color: Colors.white24,
                                size: 18,
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),

              const SizedBox(height: 32),

              // ── DANGER ZONE ──────────────────────────────────────────────
              _sectionHeader('DANGER ZONE'),
              Center(
                child: TextButton(
                  onPressed: _deleteLocation,
                  child: const Text(
                    'DELETE LOCATION',
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontSize: 12,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
