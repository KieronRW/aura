import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class NetworkSettingsScreen extends StatefulWidget {
  final Map<String, dynamic> installation;
  final String localIp;

  const NetworkSettingsScreen({
    super.key,
    required this.installation,
    required this.localIp,
  });

  @override
  State<NetworkSettingsScreen> createState() => _NetworkSettingsScreenState();
}

class _NetworkSettingsScreenState extends State<NetworkSettingsScreen> {
  bool _loading = true;
  bool _saving = false;
  bool _reconnecting = false;
  Timer? _reconnectTimer;

  String _connectionType = '';
  String _interface = '';
  String _method = 'dhcp';
  late String _currentBaseIp;

  final _ipCtrl = TextEditingController();
  final _subnetCtrl = TextEditingController();
  final _gatewayCtrl = TextEditingController();
  final _dns1Ctrl = TextEditingController();
  final _dns2Ctrl = TextEditingController();

  String get _baseUrl => 'http://$_currentBaseIp:8000';

  @override
  void initState() {
    super.initState();
    _currentBaseIp = widget.localIp;
    _loadSettings();
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _ipCtrl.dispose();
    _subnetCtrl.dispose();
    _gatewayCtrl.dispose();
    _dns1Ctrl.dispose();
    _dns2Ctrl.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    if (mounted) setState(() => _loading = true);
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/network/settings'))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200 && mounted) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        _applyData(data);
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  void _applyData(Map<String, dynamic> data) {
    _connectionType = data['connection_type'] as String? ?? '';
    _interface = data['interface'] as String? ?? '';
    _method = data['method'] as String? ?? 'dhcp';
    _ipCtrl.text = data['ip_address'] as String? ?? '';
    _subnetCtrl.text = data['subnet_mask'] as String? ?? '';
    _gatewayCtrl.text = data['gateway'] as String? ?? '';
    _dns1Ctrl.text = data['dns_primary'] as String? ?? '';
    _dns2Ctrl.text = data['dns_secondary'] as String? ?? '';
  }

  String? _validate() {
    if (_method == 'dhcp') return null;
    final ip = _ipCtrl.text.trim();
    final subnet = _subnetCtrl.text.trim();
    final gw = _gatewayCtrl.text.trim();
    final dns1 = _dns1Ctrl.text.trim();
    final dns2 = _dns2Ctrl.text.trim();
    if (ip.isEmpty) return 'IP address is required';
    if (subnet.isEmpty) return 'Subnet mask is required';
    if (gw.isEmpty) return 'Gateway is required';
    if (!_isValidIp(ip)) return 'Invalid IP address';
    if (!_isValidIp(subnet)) return 'Invalid subnet mask';
    if (!_isValidIp(gw)) return 'Invalid gateway';
    if (dns1.isNotEmpty && !_isValidIp(dns1)) return 'Invalid primary DNS';
    if (dns2.isNotEmpty && !_isValidIp(dns2)) return 'Invalid secondary DNS';
    return null;
  }

  bool _isValidIp(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    return parts.every((p) {
      final n = int.tryParse(p);
      return n != null && n >= 0 && n <= 255;
    });
  }

  Future<void> _onSaveTap() async {
    final error = _validate();
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error, style: const TextStyle(color: Colors.white)),
          backgroundColor: const Color(0xFF222222),
        ),
      );
      return;
    }

    final confirmed = await _showWarningDialog();
    if (!confirmed || !mounted) return;

    setState(() => _saving = true);
    try {
      final body = <String, dynamic>{'method': _method};
      if (_method == 'static') {
        body['ip_address'] = _ipCtrl.text.trim();
        body['subnet_mask'] = _subnetCtrl.text.trim();
        body['gateway'] = _gatewayCtrl.text.trim();
        body['dns_primary'] = _dns1Ctrl.text.trim();
        body['dns_secondary'] = _dns2Ctrl.text.trim();
      }
      await http
          .post(
            Uri.parse('$_baseUrl/network/settings'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {}
    if (!mounted) return;

    setState(() {
      _saving = false;
      _reconnecting = true;
    });

    _reconnectTimer = Timer(const Duration(seconds: 10), () async {
      if (!mounted) return;
      setState(() => _reconnecting = false);

      // Query Supabase for the Pi's current IP (updated by its own heartbeat).
      Future<String?> fetchFreshIp() async {
        try {
          final status = await Supabase.instance.client
              .from('device_status')
              .select('local_ip')
              .eq('installation_id', widget.installation['id'])
              .maybeSingle();
          return status?['local_ip'] as String?;
        } catch (e) {
          debugPrint('NetworkSettingsScreen: device_status fetch error: $e');
          return null;
        }
      }

      var freshIp = await fetchFreshIp();
      if (!mounted) return;

      if (freshIp != null && freshIp != widget.localIp) {
        // Pi has already re-heartbeated with its new IP.
        setState(() => _currentBaseIp = freshIp!);
        await _loadSettings();
      } else {
        // IP hasn't changed yet — show a message and poll every 5s for up to 60s.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Aura is reconnecting with a new network configuration. '
              'This may take up to a minute.',
            ),
            backgroundColor: Color(0xFF222222),
            duration: Duration(seconds: 60),
          ),
        );

        final deadline = DateTime.now().add(const Duration(seconds: 60));
        while (mounted && DateTime.now().isBefore(deadline)) {
          await Future.delayed(const Duration(seconds: 5));
          if (!mounted) return;
          freshIp = await fetchFreshIp();
          if (!mounted) return;
          if (freshIp != null && freshIp != widget.localIp) {
            setState(() => _currentBaseIp = freshIp!);
            break;
          }
        }

        if (mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();
          await _loadSettings();
        }
      }
    });
  }

  Future<bool> _showWarningDialog() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF111111),
        title: const Text(
          'APPLY CHANGES',
          style: TextStyle(
            color: Colors.white,
            fontSize: 13,
            letterSpacing: 3,
            fontWeight: FontWeight.w300,
          ),
        ),
        content: Text(
          _method == 'dhcp'
              ? 'Switching to DHCP will assign a new IP address automatically. '
                'Your Aura may become temporarily unreachable until the app reconnects. '
                'Make sure you have an alternative way to access the device '
                '(e.g. physical access or Tailscale).'
              : 'Changing network settings may temporarily disconnect your Aura. '
                'The app will attempt to reconnect automatically.',
          style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.6),
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
              'APPLY',
              style: TextStyle(color: Colors.white, letterSpacing: 2),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
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
          'NETWORK',
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
        child: Stack(
        children: [
          if (_loading)
            const Center(
              child: CircularProgressIndicator(
                color: Colors.white24,
                strokeWidth: 1,
              ),
            )
          else
            ListView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 100),
              children: [
                _sectionLabel('CONNECTION'),
                const SizedBox(height: 12),
                _infoRow(
                  'TYPE',
                  _connectionType == 'wifi'
                      ? 'Wi-Fi'
                      : _connectionType == 'ethernet'
                          ? 'Ethernet'
                          : '—',
                ),
                _infoRow('INTERFACE', _interface.isNotEmpty ? _interface : '—'),

                const SizedBox(height: 28),
                _sectionLabel('IP MODE'),
                const SizedBox(height: 12),
                _ModeSelector(
                  value: _method,
                  onChanged: (v) => setState(() => _method = v),
                ),

                if (_method == 'dhcp') ...[
                  const SizedBox(height: 28),
                  _sectionLabel('CURRENT NETWORK'),
                  const SizedBox(height: 12),
                  _infoRow('IP ADDRESS', _ipCtrl.text.isNotEmpty ? _ipCtrl.text : '—'),
                  _infoRow('SUBNET MASK', _subnetCtrl.text.isNotEmpty ? _subnetCtrl.text : '—'),
                  _infoRow('GATEWAY', _gatewayCtrl.text.isNotEmpty ? _gatewayCtrl.text : '—'),
                  _infoRow('DNS PRIMARY', _dns1Ctrl.text.isNotEmpty ? _dns1Ctrl.text : '—'),
                  _infoRow('DNS SECONDARY', _dns2Ctrl.text.isNotEmpty ? _dns2Ctrl.text : '—'),
                ],

                if (_method == 'static') ...[
                  const SizedBox(height: 28),
                  _sectionLabel('STATIC CONFIGURATION'),
                  const SizedBox(height: 16),
                  _IpField(
                    label: 'IP ADDRESS',
                    controller: _ipCtrl,
                    hint: '192.168.0.200',
                  ),
                  _IpField(
                    label: 'SUBNET MASK',
                    controller: _subnetCtrl,
                    hint: '255.255.255.0',
                  ),
                  _IpField(
                    label: 'GATEWAY',
                    controller: _gatewayCtrl,
                    hint: '192.168.0.1',
                  ),
                  _IpField(
                    label: 'DNS PRIMARY',
                    controller: _dns1Ctrl,
                    hint: '8.8.8.8',
                  ),
                  _IpField(
                    label: 'DNS SECONDARY',
                    controller: _dns2Ctrl,
                    hint: '8.8.4.4',
                  ),
                ],
              ],
            ),

          // Save button
          if (!_loading)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                child: Container(
                  color: Colors.black,
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                  child: GestureDetector(
                    onTap: _saving || _reconnecting ? null : _onSaveTap,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      color: Colors.white,
                      child: const Text(
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
                ),
              ),
            ),

          // Reconnecting overlay
          if (_reconnecting) _buildReconnectingOverlay(),
        ],
        ),
      ),
    );
  }

  Widget _buildReconnectingOverlay() {
    return Container(
      color: Colors.black.withAlpha(217),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white38, strokeWidth: 1),
            SizedBox(height: 20),
            Text(
              'RECONNECTING',
              style: TextStyle(
                color: Colors.white38,
                fontSize: 11,
                letterSpacing: 3,
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

  Widget _infoRow(String label, String value) => Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.white12)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                  letterSpacing: 1.5,
                ),
              ),
            ),
            Text(
              value,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ],
        ),
      );
}

// ---------------------------------------------------------------------------
// Mode selector: DHCP / STATIC
// ---------------------------------------------------------------------------

class _ModeSelector extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _ModeSelector({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: ['dhcp', 'static'].map((mode) {
        final selected = value == mode;
        final isLast = mode == 'static';
        return Expanded(
          child: GestureDetector(
            onTap: () => onChanged(mode),
            child: Container(
              margin: isLast ? EdgeInsets.zero : const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: selected ? Colors.white : Colors.transparent,
                border: Border.all(
                  color: selected ? Colors.white : Colors.white24,
                ),
              ),
              child: Text(
                mode.toUpperCase(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: selected ? Colors.black : Colors.white38,
                  fontSize: 12,
                  letterSpacing: 2,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// IP address text field
// ---------------------------------------------------------------------------

class _IpField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String hint;

  const _IpField({
    required this.label,
    required this.controller,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 10,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
            ],
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: Colors.white12),
              enabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white24),
              ),
              focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white),
              ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
            ),
          ),
        ],
      ),
    );
  }
}
