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
      body: _loading
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
                    ],
                  ),
                ),
              ],
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
