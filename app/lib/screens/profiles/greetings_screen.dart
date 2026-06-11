// Greetings screen — greeting settings for a profile (used as tab content)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../providers/profile_provider.dart';

class GreetingsScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> profile;

  const GreetingsScreen({super.key, required this.profile});

  @override
  ConsumerState<GreetingsScreen> createState() => _GreetingsScreenState();
}

class _GreetingsScreenState extends ConsumerState<GreetingsScreen> {
  late final TextEditingController _greetingCtrl;
  bool _aiVaried = false;
  bool _showWeather = false;
  bool _showTime = false;
  bool _showSmartHome = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _greetingCtrl = TextEditingController(
      text: widget.profile['greeting'] as String? ?? '',
    );
    _aiVaried = widget.profile['ai_greeting_enabled'] as bool? ?? false;
    _showWeather = widget.profile['show_weather'] as bool? ?? false;
    _showTime = widget.profile['show_time'] as bool? ?? false;
    _showSmartHome = widget.profile['show_smart_home'] as bool? ?? false;
  }

  @override
  void dispose() {
    _greetingCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await Supabase.instance.client.from('profiles').update({
        'greeting': _greetingCtrl.text.trim(),
        'ai_greeting_enabled': _aiVaried,
        'show_weather': _showWeather,
        'show_time': _showTime,
        'show_smart_home': _showSmartHome,
      }).eq('id', widget.profile['id']);
      ref.read(profilesProvider.notifier).refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Greetings settings saved'),
            backgroundColor: Color(0xFF222222),
          ),
        );
      }
    } catch (e) {
      debugPrint('Save greetings error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to save. Please try again.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'BASE MESSAGE',
          style: TextStyle(fontSize: 10, letterSpacing: 3, color: Colors.white24),
        ),
        const SizedBox(height: 4),
        const Text(
          'Displayed on the mirror when this profile is recognised.',
          style: TextStyle(color: Colors.white24, fontSize: 12, height: 1.5),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _greetingCtrl,
          style: const TextStyle(color: Colors.white),
          maxLines: 2,
          decoration: const InputDecoration(
            hintText: 'e.g. Welcome home',
            hintStyle: TextStyle(color: Colors.white24),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white24),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white),
            ),
          ),
        ),
        const SizedBox(height: 32),
        const Text(
          'OPTIONS',
          style: TextStyle(fontSize: 10, letterSpacing: 3, color: Colors.white24),
        ),
        const SizedBox(height: 4),
        _ToggleRow(
          title: 'AI-varied',
          subtitle: 'Greeting is uniquely phrased each time',
          value: _aiVaried,
          onChanged: (v) => setState(() => _aiVaried = v),
        ),
        _ToggleRow(
          title: 'Show weather',
          subtitle: 'Display current weather on the mirror',
          value: _showWeather,
          onChanged: (v) => setState(() => _showWeather = v),
        ),
        _ToggleRow(
          title: 'Show time',
          subtitle: 'Display current time on the mirror',
          value: _showTime,
          onChanged: (v) => setState(() => _showTime = v),
        ),
        _ToggleRow(
          title: 'Smart home status',
          subtitle: 'No integration connected',
          value: _showSmartHome,
          onChanged: null,
          enabled: false,
        ),
        const SizedBox(height: 32),
        GestureDetector(
          onTap: _saving ? null : _save,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            color: Colors.white,
            child: _saving
                ? const Center(
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: Colors.black,
                      ),
                    ),
                  )
                : const Text(
                    'SAVE',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 11,
                      letterSpacing: 4,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool enabled;

  const _ToggleRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
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
                    color: enabled ? Colors.white : Colors.white38,
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
          ),
          Switch(
            value: value,
            onChanged: enabled ? onChanged : null,
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
