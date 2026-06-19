import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../widgets/skeleton.dart';
import '../../theme/aura_theme.dart';

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
    'fp_match_floor': 55,
    'fp_match_margin': 8,
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
      backgroundColor: kVoid,
      appBar: AppBar(
        backgroundColor: kVoid,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text('RECOGNITION', style: kHeading()),
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
                    color: kViolet,
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
        child: Container(
        decoration: const BoxDecoration(gradient: kBgGradient),
        child: _loading
            ? ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  const SkeletonSettingsRow(),
                  const SizedBox(height: 20),
                  const SkeletonSettingsRow(),
                  const SizedBox(height: 4),
                  const SkeletonSettingsRow(),
                  const SizedBox(height: 20),
                  const SkeletonSettingsRow(),
                  const SizedBox(height: 4),
                  const SkeletonSettingsRow(),
                  const SizedBox(height: 20),
                  const SkeletonSettingsRow(),
                ],
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
                          Text(
                            'Warning: min score exceeds max score — no frames will qualify for auto-learning.',
                            style: kCaption(kWarningText),
                          ),
                        ],
                        const SizedBox(height: 28),
                        _sectionLabel('FINGERPRINT CLASSIFIER'),
                        const SizedBox(height: 12),
                        _SliderRow(
                          label: 'SENSITIVITY',
                          value: (_settings['fp_match_floor'] as int).toDouble(),
                          onChanged: (v) =>
                              _onSliderChanged('fp_match_floor', v),
                        ),
                        _description(
                          'Minimum similarity score for a prototype match to be considered. Lower values accept weaker matches — increase if you see false positives.',
                        ),
                        const SizedBox(height: 8),
                        _SliderRow(
                          label: 'DISTINCTIVENESS',
                          value:
                              (_settings['fp_match_margin'] as int).toDouble(),
                          onChanged: (v) =>
                              _onSliderChanged('fp_match_margin', v),
                        ),
                        _description(
                          'Required gap between the best and second-best vehicle score. Higher values demand a clearer winner, reducing ambiguous matches between similar vehicles.',
                        ),
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
                          'Overrides the Sensitivity floor when the device has no internet connection. Lower values are more permissive.',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
        ),
    );
  }

  Widget _sectionLabel(String text) => Text(text, style: kLabel());

  Widget _description(String text) => Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 4),
        child: Text(text, style: kCaption()),
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
            child: Text(label, style: kCaption()),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: kViolet,
                inactiveTrackColor: const Color(0x1FFFFFFF),
                thumbColor: Colors.white,
                overlayColor: kViolet.withAlpha(40),
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
              style: kBody(),
            ),
          ),
        ],
      ),
    );
  }
}
