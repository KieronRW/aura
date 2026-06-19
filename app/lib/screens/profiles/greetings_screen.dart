// Greetings screen — greeting settings for a profile (used as tab content)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../providers/profile_provider.dart';
import '../../theme/aura_theme.dart';

class GreetingsScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> profile;

  const GreetingsScreen({super.key, required this.profile});

  @override
  ConsumerState<GreetingsScreen> createState() => _GreetingsScreenState();
}

class _GreetingsScreenState extends ConsumerState<GreetingsScreen> {
  late final TextEditingController _greetingCtrl;
  bool _aiVaried = false;
  bool _showSmartHome = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _greetingCtrl = TextEditingController(
      text: widget.profile['greeting'] as String? ?? '',
    );
    _aiVaried = widget.profile['ai_greeting_enabled'] as bool? ?? false;
    _showSmartHome = widget.profile['show_smart_home'] as bool? ?? false;
  }

  @override
  void dispose() {
    _greetingCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveToggle(String column, bool value) async {
    try {
      await Supabase.instance.client
          .from('profiles')
          .update({column: value}).eq('id', widget.profile['id']);
      ref.read(profilesProvider.notifier).refresh();
    } catch (e) {
      debugPrint('Toggle save error ($column): $e');
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await Supabase.instance.client.from('profiles').update({
        'greeting': _greetingCtrl.text.trim(),
      }).eq('id', widget.profile['id']);
      ref.read(profilesProvider.notifier).refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Greeting saved', style: kBody()),
            backgroundColor: kCard,
          ),
        );
      }
    } catch (e) {
      debugPrint('Save greetings error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save. Please try again.', style: kBody()),
            backgroundColor: kError,
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
        Text(
          'BASE MESSAGE',
          style: kLabel(),
        ),
        const SizedBox(height: 4),
        Text(
          'Displayed on the mirror when this profile is recognised.',
          style: kCaption(),
        ),
        const SizedBox(height: 12),
        Container(
          height: 54,
          decoration: BoxDecoration(
            color: const Color(0x0EFFFFFF),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kInputBorder),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _greetingCtrl,
            style: kBody(),
            maxLines: 2,
            decoration: InputDecoration(
              hintText: 'e.g. Welcome home',
              hintStyle: kBody(const Color(0x66FFFFFF)),
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
        const SizedBox(height: 32),
        Text(
          'OPTIONS',
          style: kLabel(),
        ),
        const SizedBox(height: 4),
        _ToggleRow(
          title: 'AI-varied',
          subtitle: 'Greeting is uniquely phrased each time',
          value: _aiVaried,
          onChanged: (v) {
            setState(() => _aiVaried = v);
            _saveToggle('ai_greeting_enabled', v);
          },
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
            height: 55,
            decoration: BoxDecoration(
              gradient: kPrimaryGradient,
              borderRadius: BorderRadius.circular(15),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x8C6366E8),
                  blurRadius: 22,
                  offset: Offset(0, 8),
                  spreadRadius: -12,
                ),
              ],
            ),
            alignment: Alignment.center,
            child: _saving
                ? const Center(
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: kViolet,
                      ),
                    ),
                  )
                : Text(
                    'SAVE',
                    textAlign: TextAlign.center,
                    style: kBody(),
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
        border: Border(bottom: BorderSide(color: kRowDivider)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: enabled ? kBody() : kBody(const Color(0x66FFFFFF)),
                ),
                Text(
                  subtitle,
                  style: kCaption(),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: enabled ? onChanged : null,
            activeThumbColor: Colors.white,
            activeTrackColor: kViolet,
            inactiveThumbColor: Colors.white38,
            inactiveTrackColor: const Color(0x1FFFFFFF),
          ),
        ],
      ),
    );
  }
}
