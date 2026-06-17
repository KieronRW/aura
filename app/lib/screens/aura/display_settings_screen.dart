import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../widgets/skeleton.dart';

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
    'display_rotation': 0,
    'show_time': false,
    'show_weather': false,
    'status_bar_scale': 100,
    'auto_update': true,
    'dev_mode': false,
  };
  bool _loading = true;
  bool _saving = false;

  String get _baseUrl => 'http://${widget.localIp}:8000';

  @override
  void initState() {
    super.initState();
    _loadSettings();
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

  void _onRotationChanged(int value) {
    setState(() => _settings['display_rotation'] = value);
    _postSetting('display_rotation', value);
  }

  void _onShowTimeChanged(bool value) {
    setState(() => _settings['show_time'] = value);
    _postSetting('show_time', value);
  }

  void _onShowWeatherChanged(bool value) {
    setState(() => _settings['show_weather'] = value);
    _postSetting('show_weather', value);
  }

  void _onAutoUpdateChanged(bool value) {
    setState(() => _settings['auto_update'] = value);
    _postSetting('auto_update', value);
  }

  void _onDevModeChanged(bool value) {
    setState(() => _settings['dev_mode'] = value);
    _postSetting('dev_mode', value);
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
                ],
              )
            : ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionLabel('ORIENTATION'),
                        const SizedBox(height: 16),
                        _RotationSelector(
                          value: _settings['display_rotation'] as int? ?? 0,
                          onChanged: _onRotationChanged,
                        ),
                        const SizedBox(height: 32),
                        _sectionLabel('STATUS BAR'),
                        const SizedBox(height: 4),
                        _ToggleRow(
                          title: 'Show time',
                          subtitle: 'Display clock in the bottom bar',
                          value: _settings['show_time'] as bool? ?? false,
                          onChanged: _onShowTimeChanged,
                        ),
                        _ToggleRow(
                          title: 'Show weather',
                          subtitle: 'Display temperature and conditions',
                          value: _settings['show_weather'] as bool? ?? false,
                          onChanged: _onShowWeatherChanged,
                        ),
                        const SizedBox(height: 24),
                        _sectionLabel('STATUS BAR SIZE'),
                        const SizedBox(height: 4),
                        _SliderRow(
                          title: 'Scale',
                          subtitle: 'Resize the status bar and its content',
                          value: (_settings['status_bar_scale'] as num? ?? 100).toDouble(),
                          min: 50,
                          max: 200,
                          divisions: 15,
                          label: '${(_settings['status_bar_scale'] as num? ?? 100).round()}%',
                          onChanged: (v) => setState(
                            () => _settings['status_bar_scale'] = v.round(),
                          ),
                          onChangeEnd: (v) =>
                              _postSetting('status_bar_scale', v.round()),
                        ),
                        const SizedBox(height: 32),
                        _sectionLabel('UPDATES'),
                        const SizedBox(height: 4),
                        _ToggleRow(
                          title: 'Automatic Updates',
                          subtitle: 'Mirror updates automatically between 2–4 AM',
                          value: _settings['auto_update'] as bool? ?? true,
                          onChanged: _onAutoUpdateChanged,
                          disabled: _settings['dev_mode'] as bool? ?? false,
                          disabledReason: 'Disabled in Developer Mode',
                        ),
                        const SizedBox(height: 32),
                        _sectionLabel('DEVELOPER'),
                        const SizedBox(height: 4),
                        Container(
                          color: (_settings['dev_mode'] as bool? ?? false)
                              ? Colors.amber.withValues(alpha: 0.05)
                              : Colors.transparent,
                          child: _ToggleRow(
                            title: 'Developer Mode',
                            subtitle:
                                'Suppresses update notifications and disables auto-updates. For development units only.',
                            value: _settings['dev_mode'] as bool? ?? false,
                            onChanged: _onDevModeChanged,
                          ),
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
// Toggle row
// ---------------------------------------------------------------------------

class _ToggleRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool disabled;
  final String? disabledReason;

  const _ToggleRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.disabled = false,
    this.disabledReason,
  });

  @override
  Widget build(BuildContext context) {
    Widget sw = Switch(
      value: value,
      onChanged: disabled ? null : onChanged,
      activeThumbColor: Colors.white,
      activeTrackColor: Colors.white38,
      inactiveThumbColor: Colors.white38,
      inactiveTrackColor: Colors.white12,
    );

    if (disabled && disabledReason != null) {
      sw = Tooltip(message: disabledReason!, child: sw);
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white12)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: disabled ? Colors.white24 : Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w300,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: disabled ? Colors.white12 : Colors.white38,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          sw,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Slider row
// ---------------------------------------------------------------------------

class _SliderRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String label;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  const _SliderRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
    required this.label,
    required this.onChanged,
    required this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ],
              ),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 13,
                  fontWeight: FontWeight.w300,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 1.5,
              thumbColor: Colors.white,
              activeTrackColor: Colors.white38,
              inactiveTrackColor: Colors.white12,
              overlayColor: Colors.white10,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
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
