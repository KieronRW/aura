import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../providers/installation_provider.dart';
import '../../providers/property_provider.dart';
import '../../theme/aura_theme.dart';
import 'aura_settings_screen.dart';

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
        SnackBar(
          content: Text('Property name is required', style: kBody()),
          backgroundColor: kError,
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final street = _streetCtrl.text.trim();
      final city = _cityCtrl.text.trim();
      final country = _countryCtrl.text.trim();
      final addressParts = [street, city].where((s) => s.isNotEmpty).toList();
      final address = addressParts.isNotEmpty ? addressParts.join(', ') : null;

      // Geocode city → lat/lon via Open-Meteo (best-effort, never blocks save)
      double? lat;
      double? lon;
      final geocodeQuery = city.isNotEmpty ? city : null;
      if (geocodeQuery != null) {
        try {
          final params = <String, String>{
            'name': geocodeQuery,
            'count': '1',
            if (country.isNotEmpty) 'country': country,
          };
          final uri = Uri.https('geocoding-api.open-meteo.com', '/v1/search', params);
          final geoResp = await http.get(uri).timeout(const Duration(seconds: 5));
          if (geoResp.statusCode == 200) {
            final body = jsonDecode(geoResp.body) as Map<String, dynamic>;
            final results = body['results'] as List<dynamic>?;
            if (results != null && results.isNotEmpty) {
              final first = results[0] as Map<String, dynamic>;
              lat = (first['latitude'] as num?)?.toDouble();
              lon = (first['longitude'] as num?)?.toDouble();
              debugPrint('Geocode: $geocodeQuery → lat=$lat, lon=$lon');
            } else {
              debugPrint('Geocode: no results for $geocodeQuery');
            }
          }
        } catch (e) {
          debugPrint('Geocode error (non-fatal): $e');
        }
      }

      await Supabase.instance.client.from('properties').update({
        'name': name,
        'address': address,
        'property_type': _propertyType,
        'country': country.isNotEmpty ? country : null,
        'province': _provinceCtrl.text.trim().isNotEmpty ? _provinceCtrl.text.trim() : null,
        'city': city.isNotEmpty ? city : null,
        'street_address': street.isNotEmpty ? street : null,
        'postal_code': _postalCtrl.text.trim().isNotEmpty ? _postalCtrl.text.trim() : null,
        'greeting_tone': _toneCtrl.text.trim().isNotEmpty ? _toneCtrl.text.trim() : null,
        'safety_reminder': _safetyCtrl.text.trim().isNotEmpty ? _safetyCtrl.text.trim() : null,
        'latitude': ?lat,
        'longitude': ?lon,
      }).eq('id', widget.property['id']);

      ref.invalidate(propertiesProvider);

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint('Save location error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save location', style: kBody()),
            backgroundColor: kError,
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
        backgroundColor: kCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          'DELETE LOCATION',
          style: kHeading(),
        ),
        content: Text(
          "Delete '$propertyName'? All Auras at this location will be released.",
          style: kBody(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'CANCEL',
              style: kBody(),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'DELETE',
              style: kBody(kErrorText),
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
          SnackBar(
            content: Text('Failed to delete location', style: kBody()),
            backgroundColor: kError,
          ),
        );
      }
    }
  }

  Widget _sectionHeader(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Text(text, style: kLabel()),
      );

  Widget _field(
    TextEditingController ctrl,
    String label, {
    String? hint,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0x0EFFFFFF),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kInputBorder),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: TextField(
          controller: ctrl,
          style: kBody(),
          maxLines: maxLines,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: label,
            labelStyle: kBody(const Color(0x66FFFFFF)),
            hintText: hint,
            hintStyle: kBody(const Color(0x66FFFFFF)),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            isDense: true,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final propertyId = widget.property['id'] as String;
    final installationsAsync = ref.watch(installationsProvider(propertyId));

    return Scaffold(
      backgroundColor: kVoid,
      appBar: AppBar(
        backgroundColor: kVoid,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          (_nameCtrl.text.isNotEmpty ? _nameCtrl.text : 'LOCATION').toUpperCase(),
          style: kHeading(),
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
                        color: kViolet,
                        strokeWidth: 1.5,
                      ),
                    ),
                  ),
                )
              : TextButton(
                  onPressed: _save,
                  child: Text(
                    'SAVE',
                    style: kBody(),
                  ),
                ),
        ],
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Container(
          decoration: const BoxDecoration(gradient: kBgGradient),
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                // ── PROPERTY DETAILS ────────────────────────────────────────
                _sectionHeader('PROPERTY DETAILS'),
                _field(_nameCtrl, 'Property Name *'),
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0x0EFFFFFF),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: kInputBorder),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: DropdownButtonFormField<String>(
                      initialValue: _propertyType,
                      dropdownColor: kCard,
                      style: kBody(),
                      decoration: InputDecoration(
                        labelText: 'Property Type',
                        labelStyle: kBody(const Color(0x66FFFFFF)),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        isDense: true,
                      ),
                      hint: Text(
                        'Select type',
                        style: kBody(const Color(0x66FFFFFF)),
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
                  loading: () => Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: const Center(
                      child: CircularProgressIndicator(
                        color: kViolet,
                        strokeWidth: 1.5,
                      ),
                    ),
                  ),
                  error: (_, _) => Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      'Failed to load Auras',
                      style: kCaption(),
                    ),
                  ),
                  data: (installationModels) {
                    if (installationModels.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Text(
                          'No Auras at this location',
                          style: kCaption(),
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
                              color: kCard,
                              border: Border.all(color: kCardBorder),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.sensors,
                                  color: Color(0x66FFFFFF),
                                  size: 20,
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Text(
                                    installation['name'] as String? ?? 'Aura',
                                    style: kBody(),
                                  ),
                                ),
                                const Icon(
                                  Icons.chevron_right,
                                  color: Color(0x40FFFFFF),
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
                    child: Text(
                      'DELETE LOCATION',
                      style: kBody(kErrorText),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
