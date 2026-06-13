import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class DisplaySettingsScreen extends StatefulWidget {
  final Map<String, dynamic> installation;
  final String localIp;

  const DisplaySettingsScreen({
    super.key,
    required this.installation,
    required this.localIp,
  });

  @override
  State<DisplaySettingsScreen> createState() => _DisplaySettingsScreenState();
}

class _DisplaySettingsScreenState extends State<DisplaySettingsScreen> {
  Map<String, dynamic> _settings = {
    'display_brightness': 100,
    'display_rotation': 0,
  };
  bool _loading = true;
  bool _saving = false;
  Timer? _debounce;

  String get _baseUrl => 'http://${widget.localIp}:8000';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/display/settings'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200 && mounted) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        setState(() {
          _settings = {..._settings, ...data};
          _loading = false;
        });
        return;
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  void _onSliderChanged(String key, double raw) {
    final value = raw.round();
    setState(() => _settings[key] = value);
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => _postSetting(key, value),
    );
  }

  void _onRotationChanged(int value) {
    setState(() => _settings['display_rotation'] = value);
    _postSetting('display_rotation', value);
  }

  Future<void> _postSetting(String key, dynamic value) async {
    if (!mounted) return;
    setState(() => _saving = true);
    try {
      await http
          .post(
            Uri.parse('$_baseUrl/display/settings'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({key: value}),
          )
          .timeout(const Duration(seconds: 5));
    } catch (_) {}
    if (mounted) setState(() => _saving = false);
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
          'DISPLAY',
          style: TextStyle(
            fontSize: 13,
            letterSpacing: 4,
            fontWeight: FontWeight.w300,
          ),
        ),
        actions: [
          AnimatedOpacity(
            opacity: _saving ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: const Padding(
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
            ),
          ),
        ],
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(
                  color: Colors.white24,
                  strokeWidth: 1,
                ),
              )
            : ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionLabel('IMAGE'),
                        const SizedBox(height: 12),
                        _SliderRow(
                          label: 'BRIGHTNESS',
                          value: (_settings['display_brightness'] as num).toDouble(),
                          min: 0,
                          max: 100,
                          divisions: 100,
                          onChanged: (v) => _onSliderChanged('display_brightness', v),
                        ),
                        const SizedBox(height: 28),
                        _sectionLabel('ORIENTATION'),
                        const SizedBox(height: 16),
                        _RotationSelector(
                          value: _settings['display_rotation'] as int? ?? 0,
                          onChanged: _onRotationChanged,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 10,
          letterSpacing: 3,
          color: Colors.white24,
        ),
      );
}

// ---------------------------------------------------------------------------
// Slider row
// ---------------------------------------------------------------------------

class _SliderRow extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 11,
                letterSpacing: 1.5,
              ),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: Colors.white38,
                inactiveTrackColor: Colors.white12,
                thumbColor: Colors.white,
                overlayColor: Colors.white.withAlpha(20),
                trackHeight: 1,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              ),
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                divisions: divisions,
                onChanged: onChanged,
              ),
            ),
          ),
          SizedBox(
            width: 36,
            child: Text(
              value.round().toString(),
              textAlign: TextAlign.end,
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Rotation selector
// ---------------------------------------------------------------------------

class _RotationSelector extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;

  const _RotationSelector({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'ROTATION',
          style: TextStyle(
            color: Colors.white38,
            fontSize: 11,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [0, 90, 180, 270].map((deg) {
            final selected = value == deg;
            final isLast = deg == 270;
            return Expanded(
              child: GestureDetector(
                onTap: () => onChanged(deg),
                child: Container(
                  margin: isLast ? EdgeInsets.zero : const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: selected ? Colors.white : Colors.transparent,
                    border: Border.all(
                      color: selected ? Colors.white : Colors.white24,
                    ),
                  ),
                  child: Text(
                    '$deg°',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: selected ? Colors.black : Colors.white38,
                      fontSize: 12,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
