import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class RecognitionSettingsScreen extends StatefulWidget {
  final Map<String, dynamic> installation;
  final String localIp;

  const RecognitionSettingsScreen({
    super.key,
    required this.installation,
    required this.localIp,
  });

  @override
  State<RecognitionSettingsScreen> createState() =>
      _RecognitionSettingsScreenState();
}

class _RecognitionSettingsScreenState
    extends State<RecognitionSettingsScreen> {
  // Stored internally as 0–100 (percentage of 0.0–1.0) for slider display.
  // Converted to/from float on load and post.
  final Map<String, dynamic> _settings = {
    'vision_confidence_gate': 75,
    'auto_learn_min': 60,
    'auto_learn_max': 72,
    'offline_fp_threshold': 60,
  };
  bool _loading = true;
  bool _saving = false;
  Timer? _debounce;

  String get _baseUrl => 'http://${widget.localIp}:8000';

  bool get _rangeValid =>
      (_settings['auto_learn_min'] as int) <=
      (_settings['auto_learn_max'] as int);

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
          .get(Uri.parse('$_baseUrl/recognition/settings'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200 && mounted) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        setState(() {
          for (final key in _settings.keys) {
            if (data.containsKey(key)) {
              _settings[key] = ((data[key] as num).toDouble() * 100).round();
            }
          }
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

  Future<void> _postSetting(String key, int value) async {
    if (!mounted) return;
    setState(() => _saving = true);
    try {
      await http
          .post(
            Uri.parse('$_baseUrl/recognition/settings'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({key: value / 100.0}),
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
          'RECOGNITION',
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
                        _sectionLabel('VISION API'),
                        const SizedBox(height: 12),
                        _SliderRow(
                          label: 'CONFIDENCE GATE',
                          value: (_settings['vision_confidence_gate'] as int)
                              .toDouble(),
                          onChanged: (v) =>
                              _onSliderChanged('vision_confidence_gate', v),
                        ),
                        _description(
                          'Minimum Vision API confidence required to trust a make/model result. Lower values accept weaker matches.',
                        ),
                        const SizedBox(height: 28),
                        _sectionLabel('AUTO-LEARN'),
                        const SizedBox(height: 12),
                        _SliderRow(
                          label: 'MIN SCORE',
                          value:
                              (_settings['auto_learn_min'] as int).toDouble(),
                          onChanged: (v) =>
                              _onSliderChanged('auto_learn_min', v),
                        ),
                        _description(
                          'Fingerprint score lower bound. Frames scoring above this but below the max are captured for auto-learning.',
                        ),
                        const SizedBox(height: 8),
                        _SliderRow(
                          label: 'MAX SCORE',
                          value:
                              (_settings['auto_learn_max'] as int).toDouble(),
                          onChanged: (v) =>
                              _onSliderChanged('auto_learn_max', v),
                        ),
                        _description(
                          'Fingerprint score upper bound. Frames already scoring above this already match without needing Vision.',
                        ),
                        if (!_rangeValid) ...[
                          const SizedBox(height: 8),
                          const Text(
                            'Warning: min score exceeds max score — no frames will qualify for auto-learning.',
                            style: TextStyle(
                              color: Colors.orangeAccent,
                              fontSize: 11,
                              height: 1.5,
                            ),
                          ),
                        ],
                        const SizedBox(height: 28),
                        _sectionLabel('OFFLINE MODE'),
                        const SizedBox(height: 12),
                        _SliderRow(
                          label: 'FINGERPRINT THRESHOLD',
                          value: (_settings['offline_fp_threshold'] as int)
                              .toDouble(),
                          onChanged: (v) =>
                              _onSliderChanged('offline_fp_threshold', v),
                        ),
                        _description(
                          'Fingerprint match threshold used when the device has no internet connection. Lower values are more permissive.',
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

  Widget _description(String text) => Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 4),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white24,
            fontSize: 11,
            height: 1.5,
          ),
        ),
      );
}

// ---------------------------------------------------------------------------
// Slider row
// ---------------------------------------------------------------------------

class _SliderRow extends StatelessWidget {
  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  const _SliderRow({
    required this.label,
    required this.value,
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
                overlayShape:
                    const RoundSliderOverlayShape(overlayRadius: 14),
              ),
              child: Slider(
                value: value.clamp(0, 100),
                min: 0,
                max: 100,
                divisions: 100,
                onChanged: onChanged,
              ),
            ),
          ),
          SizedBox(
            width: 36,
            child: Text(
              '${value.round()}%',
              textAlign: TextAlign.end,
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}
