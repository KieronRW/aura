import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bonsoir/bonsoir.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../providers/installation_provider.dart';
import '../../providers/property_provider.dart';
import '../../theme/aura_theme.dart';
import '../home/home_screen.dart';
import 'add_mirror_screen.dart';

class DiscoverMirrorScreen extends ConsumerStatefulWidget {
  final String? propertyId;
  final Set<String> ownedKeys;

  const DiscoverMirrorScreen({
    super.key,
    this.propertyId,
    this.ownedKeys = const {},
  });

  @override
  ConsumerState<DiscoverMirrorScreen> createState() => _DiscoverMirrorScreenState();
}

class _DiscoverMirrorScreenState extends ConsumerState<DiscoverMirrorScreen> {
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
    debugPrint(
      'Discovery: eventStream is null: ${_discovery!.eventStream == null}',
    );

    // Set up listener BEFORE start() so no events are missed
    _discovery!.eventStream?.listen((event) async {
      debugPrint('Discovery event: ${event.runtimeType}');

      if (event is BonsoirDiscoveryServiceFoundEvent) {
        final service = event.service;
        final attributes = service.attributes;
        final ip = attributes['ip'];
        final port = int.tryParse(attributes['port'] ?? '8000') ?? 8000;
        final key = attributes['installation_key'];

        debugPrint('Discovery: ip=$ip key=$key ownedKeys=${widget.ownedKeys}');

        if (ip == null || key == null) return;

        if (widget.ownedKeys.contains(key)) {
          debugPrint('Discovery: SKIPPING $key — already owned');
          return;
        }

        String displayName = 'Aura';
        try {
          final response = await http
              .get(Uri.parse('http://$ip:$port/info'))
              .timeout(const Duration(seconds: 3));
          if (response.statusCode == 200) {
            final info = json.decode(response.body);
            displayName = info['name'] ?? 'Aura';
          }
        } catch (_) {}

        final device = {
          'host': ip,
          'port': port,
          'installation_key': key,
          'display_name': displayName,
        };

        if (mounted && !_discovered.any((d) => d['host'] == ip)) {
          setState(() => _discovered.add(device));
        }
      }
    });

    await _discovery!.start();
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

      final existingProperty = await client
          .from('properties')
          .select('id')
          .eq('user_id', userId)
          .eq('is_active', true)
          .limit(1)
          .maybeSingle();

      String propertyId;
      if (existingProperty != null) {
        propertyId = existingProperty['id'] as String;
      } else {
        final newProperty = await client
            .from('properties')
            .insert({
              'user_id': userId,
              'name': 'My Home',
              'is_active': true,
            })
            .select('id')
            .single();
        propertyId = newProperty['id'] as String;
      }

      await client
          .from('installations')
          .update({
            'status': 'active',
            'claimed_at': DateTime.now().toUtc().toIso8601String(),
            'claimed_by': userId,
            'property_id': propertyId,
          })
          .eq('id', installation['id']);

      if (mounted) {
        _showNameDialog(installation['name'] ?? 'My Aura', propertyId);
      }
    } catch (e) {
      debugPrint('Claim error: $e');
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
        content: Text(message, style: kBody()),
        backgroundColor: kError,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _showNameDialog(String defaultName, String propertyId) {
    final nav = Navigator.of(context);
    final controller = TextEditingController(text: defaultName);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: kCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Name your Aura', style: kHeading()),
        content: Container(
          height: 54,
          decoration: BoxDecoration(
            color: const Color(0x0EFFFFFF),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kInputBorder),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Center(
            child: TextField(
              controller: controller,
              autofocus: true,
              style: kBody(),
              decoration: InputDecoration(
                hintText: 'e.g. Front Gate, Garage',
                hintStyle: kBody(const Color(0x66FFFFFF)),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final name = controller.text.trim();
              nav.pop();
              await _updateAuraName(name);
              ref.invalidate(propertiesProvider);
              ref.invalidate(installationsProvider(propertyId));
              if (mounted) {
                Navigator.popUntil(context, (route) => route.isFirst);
                HomeScreen.switchToTab(0);
              }
            },
            child: Text('Done', style: kBody(kVioletText)),
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
      backgroundColor: kVoid,
      appBar: AppBar(
        backgroundColor: kVoid,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text('Add Aura', style: kHeading()),
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: kBgGradient),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Nearby', style: kLabel()),
                const SizedBox(height: 8),
                Text(
                  'Make sure your phone is on the same WiFi network as your Aura.',
                  style: kCaption(),
                ),
                const SizedBox(height: 32),

                if (_scanning && _discovered.isEmpty)
                  Center(
                    child: Column(
                      children: [
                        const CircularProgressIndicator(
                          color: kViolet,
                          strokeWidth: 1.5,
                        ),
                        const SizedBox(height: 16),
                        Text('Scanning network…', style: kCaption()),
                      ],
                    ),
                  )
                else if (_discovered.isEmpty)
                  Center(
                    child: Column(
                      children: [
                        Text('No Aura found nearby', style: kBody()),
                        const SizedBox(height: 8),
                        Text(
                          'Make sure your Aura is powered on\nand connected to the same WiFi.',
                          textAlign: TextAlign.center,
                          style: kCaption(),
                        ),
                        const SizedBox(height: 28),
                        TextButton(
                          onPressed: _rescan,
                          child: Text('Scan again', style: kBody(kVioletText)),
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
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: kCard,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: kCardBorder),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.sensors,
                                  color: kVioletText,
                                  size: 22,
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        device['display_name'] ?? 'Aura',
                                        style: kBody(),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        device['host'] ?? '',
                                        style: kMono(const Color(0x80FFFFFF)),
                                      ),
                                    ],
                                  ),
                                ),
                                if (_claiming)
                                  const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.5,
                                      color: kViolet,
                                    ),
                                  )
                                else
                                  const Icon(
                                    Icons.chevron_right,
                                    color: Color(0x40FFFFFF),
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
                    child: Text(
                      "Can't find your Aura? Scan QR code",
                      style: kCaption(kVioletText),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
