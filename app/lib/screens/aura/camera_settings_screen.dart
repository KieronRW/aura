import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class CameraSettingsScreen extends StatefulWidget {
  final Map<String, dynamic> installation;
  final String localIp;

  const CameraSettingsScreen({
    super.key,
    required this.installation,
    required this.localIp,
  });

  @override
  State<CameraSettingsScreen> createState() => _CameraSettingsScreenState();
}

class _CameraSettingsScreenState extends State<CameraSettingsScreen> {
  Map<String, dynamic> _settings = {
    'brightness': 50,
    'contrast': 50,
    'exposure': 0,
    'horizontal_flip': false,
    'vertical_flip': false,
    'rotation': 0,
    'motion_sensitivity': 50,
    'sharpness': 50,
    'denoise_mode': 'fast',
    'awb_mode': 'auto',
    'hdr_mode': 'off',
    'af_mode': 'continuous',
    'lens_position': 0.0,
    'flicker_period_us': 0,
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
          .get(Uri.parse('$_baseUrl/camera/settings'))
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

  void _onToggleChanged(String key, bool value) {
    setState(() => _settings[key] = value);
    _postSetting(key, value);
  }

  void _onRotationChanged(int value) {
    setState(() => _settings['rotation'] = value);
    _postSetting('rotation', value);
  }

  Future<void> _postSetting(String key, dynamic value) async {
    if (!mounted) return;
    setState(() => _saving = true);
    try {
      await http
          .post(
            Uri.parse('$_baseUrl/camera/settings'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({key: value}),
          )
          .timeout(const Duration(seconds: 5));
    } catch (_) {}
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _postSettings(Map<String, dynamic> values) async {
    if (!mounted) return;
    setState(() => _saving = true);
    try {
      await http
          .post(
            Uri.parse('$_baseUrl/camera/settings'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(values),
          )
          .timeout(const Duration(seconds: 5));
    } catch (_) {}
    if (mounted) setState(() => _saving = false);
  }

  void _onStringChanged(String key, String value) {
    setState(() => _settings[key] = value);
    _postSetting(key, value);
  }

  void _onFloatSliderChanged(String key, double value) {
    setState(() => _settings[key] = value);
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => _postSetting(key, value),
    );
  }

  void _onIntChoiceChanged(String key, int value) {
    setState(() => _settings[key] = value);
    _postSetting(key, value);
  }

  void _onAfModeChanged(String value) {
    setState(() => _settings['af_mode'] = value);
    if (value == 'manual') {
      _postSettings({
        'af_mode': value,
        'lens_position': (_settings['lens_position'] as num?)?.toDouble() ?? 0.0,
      });
    } else {
      _postSetting('af_mode', value);
    }
  }

  void _showInfo(String title, String body) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF111111),
        shape: const RoundedRectangleBorder(),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            letterSpacing: 2,
          ),
        ),
        content: Text(
          body,
          style: const TextStyle(color: Colors.white54, fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'OK',
              style: TextStyle(color: Colors.white38, letterSpacing: 2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabelWithInfo(String label, String info) => Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              letterSpacing: 3,
              color: Colors.white24,
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _showInfo(label, info),
            child: const Icon(Icons.info_outline, size: 12, color: Colors.white24),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'CAMERA',
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
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: _MjpegView(url: '$_baseUrl/camera/stream'),
                ),
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionLabel('IMAGE'),
                      const SizedBox(height: 12),
                      _SliderRow(
                        label: 'BRIGHTNESS',
                        value: (_settings['brightness'] as num).toDouble(),
                        min: 0,
                        max: 100,
                        divisions: 100,
                        onChanged: (v) => _onSliderChanged('brightness', v),
                      ),
                      _SliderRow(
                        label: 'CONTRAST',
                        value: (_settings['contrast'] as num).toDouble(),
                        min: 0,
                        max: 100,
                        divisions: 100,
                        onChanged: (v) => _onSliderChanged('contrast', v),
                      ),
                      _SliderRow(
                        label: 'EXPOSURE',
                        value: (_settings['exposure'] as num).toDouble(),
                        min: -50,
                        max: 50,
                        divisions: 100,
                        onChanged: (v) => _onSliderChanged('exposure', v),
                      ),
                      const SizedBox(height: 28),
                      _sectionLabel('MOTION'),
                      const SizedBox(height: 12),
                      _SliderRow(
                        label: 'SENSITIVITY',
                        value: (_settings['motion_sensitivity'] as num).toDouble(),
                        min: 0,
                        max: 100,
                        divisions: 100,
                        onChanged: (v) => _onSliderChanged('motion_sensitivity', v),
                      ),
                      const SizedBox(height: 28),
                      _sectionLabel('ORIENTATION'),
                      const SizedBox(height: 16),
                      _ToggleRow(
                        label: 'HORIZONTAL FLIP',
                        value: _settings['horizontal_flip'] as bool? ?? false,
                        onChanged: (v) => _onToggleChanged('horizontal_flip', v),
                      ),
                      _ToggleRow(
                        label: 'VERTICAL FLIP',
                        value: _settings['vertical_flip'] as bool? ?? false,
                        onChanged: (v) => _onToggleChanged('vertical_flip', v),
                      ),
                      const SizedBox(height: 20),
                      _RotationSelector(
                        value: _settings['rotation'] as int? ?? 0,
                        onChanged: _onRotationChanged,
                      ),
                      const SizedBox(height: 28),
                      _sectionLabelWithInfo(
                        'IMAGE QUALITY',
                        'Sharpness adjusts edge detail from smooth (0) to maximum (100). Denoise reduces sensor noise at the cost of fine detail.',
                      ),
                      const SizedBox(height: 12),
                      _SliderRow(
                        label: 'SHARPNESS',
                        value: (_settings['sharpness'] as num).toDouble(),
                        min: 0,
                        max: 100,
                        divisions: 100,
                        onChanged: (v) => _onSliderChanged('sharpness', v),
                      ),
                      const SizedBox(height: 16),
                      _ChoiceRow(
                        label: 'DENOISE',
                        options: const {
                          'off': 'OFF',
                          'fast': 'FAST',
                          'high_quality': 'HIGH QUALITY',
                        },
                        value: _settings['denoise_mode'] as String? ?? 'fast',
                        onChanged: (v) => _onStringChanged('denoise_mode', v),
                      ),
                      const SizedBox(height: 28),
                      _sectionLabelWithInfo(
                        'WHITE BALANCE',
                        'Corrects colour cast caused by the ambient light source. Auto adjusts continuously.',
                      ),
                      const SizedBox(height: 12),
                      _ChoiceRow(
                        options: const {
                          'auto': 'AUTO',
                          'daylight': 'DAYLIGHT',
                          'cloudy': 'CLOUDY',
                          'tungsten': 'TUNGSTEN',
                          'fluorescent': 'FLUOR.',
                          'indoor': 'INDOOR',
                          'incandescent': 'INCAND.',
                        },
                        value: _settings['awb_mode'] as String? ?? 'auto',
                        onChanged: (v) => _onStringChanged('awb_mode', v),
                      ),
                      const SizedBox(height: 28),
                      _sectionLabelWithInfo(
                        'HDR',
                        'High Dynamic Range blends multiple exposures to retain detail in highlights and shadows simultaneously.',
                      ),
                      const SizedBox(height: 12),
                      _ChoiceRow(
                        options: const {
                          'off': 'OFF',
                          'single': 'SINGLE',
                          'multi': 'MULTI',
                          'night': 'NIGHT',
                        },
                        value: _settings['hdr_mode'] as String? ?? 'off',
                        onChanged: (v) => _onStringChanged('hdr_mode', v),
                      ),
                      const SizedBox(height: 28),
                      _sectionLabelWithInfo(
                        'AUTOFOCUS',
                        'Continuous refocuses in real time. Auto triggers once on demand. Manual locks focus at the distance set by the slider below.',
                      ),
                      const SizedBox(height: 12),
                      _ChoiceRow(
                        options: const {
                          'continuous': 'CONT.',
                          'auto': 'AUTO',
                          'manual': 'MANUAL',
                        },
                        value: _settings['af_mode'] as String? ?? 'continuous',
                        onChanged: _onAfModeChanged,
                      ),
                      if (_settings['af_mode'] == 'manual') ...[
                        const SizedBox(height: 16),
                        _SliderRow(
                          label: 'FOCUS',
                          value: (_settings['lens_position'] as num).toDouble(),
                          min: 0.0,
                          max: 10.0,
                          divisions: 100,
                          labelFormatter: (v) => v.toStringAsFixed(1),
                          onChanged: (v) => _onFloatSliderChanged('lens_position', v),
                        ),
                      ],
                      const SizedBox(height: 28),
                      _sectionLabelWithInfo(
                        'FLICKER',
                        'Matches the camera shutter to your mains frequency to eliminate banding under fluorescent or LED lighting.',
                      ),
                      const SizedBox(height: 12),
                      _ChoiceRow(
                        options: const {
                          '0': 'OFF',
                          '20000': '50 HZ',
                          '16667': '60 HZ',
                        },
                        value: (_settings['flicker_period_us'] as int? ?? 0).toString(),
                        onChanged: (v) => _onIntChoiceChanged(
                          'flicker_period_us',
                          int.parse(v),
                        ),
                      ),
                      const SizedBox(height: 24),
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
// MJPEG stream widget
// ---------------------------------------------------------------------------

class _MjpegView extends StatefulWidget {
  final String url;

  const _MjpegView({required this.url});

  @override
  State<_MjpegView> createState() => _MjpegViewState();
}

class _MjpegViewState extends State<_MjpegView> {
  Uint8List? _frame;
  bool _error = false;
  http.Client? _client;
  StreamSubscription<List<int>>? _sub;
  final List<int> _buffer = [];

  @override
  void initState() {
    super.initState();
    _connect();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _client?.close();
    super.dispose();
  }

  Future<void> _connect() async {
    try {
      _client = http.Client();
      final request = http.Request('GET', Uri.parse(widget.url));
      final response = await _client!.send(request).timeout(const Duration(seconds: 10));
      _sub = response.stream.listen(
        _onData,
        onError: (_) {
          if (mounted) setState(() => _error = true);
        },
        onDone: () {
          if (mounted) setState(() => _error = true);
        },
        cancelOnError: true,
      );
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  void _onData(List<int> chunk) {
    _buffer.addAll(chunk);
    if (_buffer.length > 4 * 1024 * 1024) _buffer.clear();
    _parseFrames();
  }

  void _parseFrames() {
    while (true) {
      // Locate JPEG SOI marker (FF D8)
      int soi = -1;
      for (int i = 0; i < _buffer.length - 1; i++) {
        if (_buffer[i] == 0xFF && _buffer[i + 1] == 0xD8) {
          soi = i;
          break;
        }
      }
      if (soi == -1) {
        if (_buffer.length > 1) _buffer.removeRange(0, _buffer.length - 1);
        return;
      }
      if (soi > 0) _buffer.removeRange(0, soi);

      // Locate JPEG EOI marker (FF D9) after SOI
      int eoi = -1;
      for (int i = 2; i < _buffer.length - 1; i++) {
        if (_buffer[i] == 0xFF && _buffer[i + 1] == 0xD9) {
          eoi = i;
          break;
        }
      }
      if (eoi == -1) return; // Wait for more data

      final frame = Uint8List.fromList(_buffer.sublist(0, eoi + 2));
      _buffer.removeRange(0, eoi + 2);
      if (mounted) setState(() => _frame = frame);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error) {
      return Container(
        color: const Color(0xFF0A0A0A),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.videocam_off_outlined, color: Colors.white24, size: 32),
              SizedBox(height: 8),
              Text(
                'Stream unavailable',
                style: TextStyle(color: Colors.white24, fontSize: 12, letterSpacing: 1),
              ),
            ],
          ),
        ),
      );
    }
    if (_frame == null) {
      return Container(
        color: const Color(0xFF0A0A0A),
        child: const Center(
          child: CircularProgressIndicator(color: Colors.white24, strokeWidth: 1),
        ),
      );
    }
    return Image.memory(_frame!, gaplessPlayback: true, fit: BoxFit.cover);
  }
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
  final String Function(double)? labelFormatter;

  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    this.labelFormatter,
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
              labelFormatter != null
                  ? labelFormatter!(value)
                  : value.round().toString(),
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
// Toggle row
// ---------------------------------------------------------------------------

class _ToggleRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white12)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w300,
                letterSpacing: 0.5,
              ),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: Colors.white,
            activeTrackColor: Colors.white38,
            inactiveThumbColor: Colors.white38,
            inactiveTrackColor: Colors.white12,
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

// ---------------------------------------------------------------------------
// Choice row — wrapped pill buttons for enum settings
// ---------------------------------------------------------------------------

class _ChoiceRow extends StatelessWidget {
  final String? label;
  final Map<String, String> options;
  final String value;
  final ValueChanged<String> onChanged;

  const _ChoiceRow({
    this.label,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null && label!.isNotEmpty) ...[
          Text(
            label!,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 11,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 10),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.entries.map((e) {
            final selected = value == e.key;
            return GestureDetector(
              onTap: () => onChanged(e.key),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: selected ? Colors.white : Colors.transparent,
                  border: Border.all(
                    color: selected ? Colors.white : Colors.white24,
                  ),
                ),
                child: Text(
                  e.value,
                  style: TextStyle(
                    color: selected ? Colors.black : Colors.white38,
                    fontSize: 10,
                    letterSpacing: 1,
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
