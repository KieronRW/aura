import 'dart:async';
import 'package:flutter/material.dart';
import 'package:bonsoir/bonsoir.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'add_mirror_screen.dart';

class DiscoverMirrorScreen extends StatefulWidget {
  final String? propertyId;

  const DiscoverMirrorScreen({super.key, this.propertyId});

  @override
  State<DiscoverMirrorScreen> createState() => _DiscoverMirrorScreenState();
}

class _DiscoverMirrorScreenState extends State<DiscoverMirrorScreen> {
  final List<Map<String, dynamic>> _discovered = [];
  bool _scanning = true;
  bool _claiming = false;
  BonsoirDiscovery? _discovery;
  Timer? _scanTimer;

  @override
  void initState() {
    super.initState();
    _startDiscovery();
    _scanTimer = Timer(const Duration(seconds: 20), () {
      if (mounted) setState(() => _scanning = false);
    });
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    _discovery?.stop();
    super.dispose();
  }

  Future<void> _startDiscovery() async {
    _discovery = BonsoirDiscovery(type: '_aura._tcp');
    await _discovery!.initialize();
    await _discovery!.start();

    _discovery!.eventStream?.listen((event) async {
      if (event is BonsoirDiscoveryServiceFoundEvent) {
        final service = event.service;
        final attributes = service.attributes;
        final ip = attributes['ip'];
        final port = int.tryParse(attributes['port'] ?? '8000') ?? 8000;

        if (ip == null) return;

        try {
          final response = await http
              .get(Uri.parse('http://$ip:$port/info'))
              .timeout(const Duration(seconds: 3));

          if (response.statusCode == 200) {
            final info = json.decode(response.body);
            if (info['installation_key'] != null) {
              // Skip if already claimed by current user
              final existing = await Supabase.instance.client
                  .from('installations')
                  .select('id, status, claimed_by')
                  .eq('installation_key', info['installation_key'])
                  .maybeSingle();

              final userId = Supabase.instance.client.auth.currentUser?.id;
              if (existing != null &&
                  existing['status'] == 'active' &&
                  existing['claimed_by'] == userId) {
                return;
              }

              final device = {
                'host': ip,
                'port': port,
                'installation_key': info['installation_key'],
                'display_name': info['name'] ?? 'Aura',
                'software_version': info['software_version'],
              };
              if (mounted && !_discovered.any((d) => d['host'] == ip)) {
                setState(() => _discovered.add(device));
              }
            }
          }
        } catch (_) {}
      }
    });
  }

  Future<void> _claimDevice(Map<String, dynamic> device) async {
    final installationKey = device['installation_key'];
    if (installationKey == null) return;

    setState(() => _claiming = true);

    final client = Supabase.instance.client;
    final userId = client.auth.currentUser!.id;

    try {
      final installation = await client
          .from('installations')
          .select('id, status, name')
          .eq('installation_key', installationKey)
          .maybeSingle();

      if (installation == null) {
        _showError('Aura not found in system.');
        return;
      }

      if (installation['status'] == 'stolen') {
        _showError('This Aura has been reported stolen.');
        return;
      }

      if (installation['status'] == 'active') {
        _showError('This Aura is already registered.');
        return;
      }

      Map<String, dynamic>? property;

      if (widget.propertyId != null) {
        property = {'id': widget.propertyId};
      } else {
        property = await client
            .from('properties')
            .select('id')
            .eq('user_id', userId)
            .maybeSingle();

        if (property == null) {
          final newProperty = await client
              .from('properties')
              .insert({'user_id': userId, 'name': 'My Home', 'timezone': 'UTC'})
              .select('id')
              .single();
          property = newProperty;
        }
      }

      await client
          .from('installations')
          .update({
            'property_id': property['id'],
            'status': 'active',
            'claimed_at': DateTime.now().toUtc().toIso8601String(),
            'claimed_by': userId,
          })
          .eq('id', installation['id']);

      if (mounted) {
        _showNameDialog(installation['name'] ?? 'My Aura');
      }
    } catch (e) {
      _showError('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _claiming = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() => _claiming = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.withValues(alpha: 0.8),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _showNameDialog(String defaultName) {
    final nav = Navigator.of(context);
    final controller = TextEditingController(text: defaultName);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF111111),
        title: const Text(
          'NAME YOUR AURA',
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            letterSpacing: 3,
            fontWeight: FontWeight.w300,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'e.g. Front Gate, Garage',
            hintStyle: TextStyle(color: Colors.white24),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white24),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final name = controller.text.trim();
              nav.pop();
              await _updateAuraName(name);
              nav.pop(true);
            },
            child: const Text(
              'DONE',
              style: TextStyle(color: Colors.white, letterSpacing: 2),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _updateAuraName(String name) async {
    if (name.isEmpty) return;
    try {
      final client = Supabase.instance.client;
      await client
          .from('installations')
          .update({'name': name})
          .eq('claimed_by', client.auth.currentUser!.id)
          .eq('status', 'active');
    } catch (_) {}
  }

  Future<void> _rescan() async {
    await _discovery?.stop();
    setState(() {
      _discovered.clear();
      _scanning = true;
    });
    _startDiscovery();
    _scanTimer?.cancel();
    _scanTimer = Timer(const Duration(seconds: 20), () {
      if (mounted) setState(() => _scanning = false);
    });
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
          'ADD AURA',
          style: TextStyle(
            fontSize: 13,
            letterSpacing: 4,
            fontWeight: FontWeight.w300,
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'NEARBY',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 4,
                  color: Colors.white38,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Make sure your phone is on the same\nWiFi network as your Aura.',
                style: TextStyle(
                  color: Colors.white24,
                  fontSize: 13,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 32),

              if (_scanning && _discovered.isEmpty)
                const Center(
                  child: Column(
                    children: [
                      CircularProgressIndicator(
                        color: Colors.white24,
                        strokeWidth: 1,
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Scanning network...',
                        style: TextStyle(color: Colors.white38, fontSize: 13),
                      ),
                    ],
                  ),
                )
              else if (_discovered.isEmpty)
                Center(
                  child: Column(
                    children: [
                      const Text(
                        'No Aura found nearby',
                        style: TextStyle(color: Colors.white38, fontSize: 14),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Make sure your Aura is powered on\nand connected to the same WiFi.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white24,
                          fontSize: 13,
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 32),
                      TextButton(
                        onPressed: _rescan,
                        child: const Text(
                          'SCAN AGAIN',
                          style: TextStyle(
                            color: Colors.white38,
                            letterSpacing: 3,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Expanded(
                  child: ListView.builder(
                    itemCount: _discovered.length,
                    itemBuilder: (context, index) {
                      final device = _discovered[index];
                      return GestureDetector(
                        onTap: _claiming ? null : () => _claimDevice(device),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: const Color(0xFF111111),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.sensors,
                                color: Colors.white38,
                                size: 24,
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      device['display_name'] ?? 'Aura',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w300,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      device['host'] ?? '',
                                      style: const TextStyle(
                                        color: Colors.white38,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (_claiming)
                                const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1,
                                    color: Colors.white38,
                                  ),
                                )
                              else
                                const Icon(
                                  Icons.chevron_right,
                                  color: Colors.white24,
                                  size: 20,
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),

              const Spacer(),

              Center(
                child: TextButton(
                  onPressed: () async {
                    final nav = Navigator.of(context);
                    final added = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AddMirrorScreen(),
                      ),
                    );
                    if (added == true && mounted) {
                      nav.pop(true);
                    }
                  },
                  child: const Text(
                    "Can't find your Aura? Scan QR code",
                    style: TextStyle(
                      color: Colors.white24,
                      fontSize: 13,
                      decoration: TextDecoration.underline,
                      decorationColor: Colors.white24,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
