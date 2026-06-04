import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AddMirrorScreen extends StatefulWidget {
  const AddMirrorScreen({super.key});

  @override
  State<AddMirrorScreen> createState() => _AddMirrorScreenState();
}

class _AddMirrorScreenState extends State<AddMirrorScreen> {
  final MobileScannerController _scanner = MobileScannerController();
  bool _processing = false;
  bool _scanned = false;

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_processing || _scanned) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode?.rawValue == null) return;

    _scanned = true;
    setState(() => _processing = true);
    await _scanner.stop();

    final installationKey = barcode!.rawValue!;
    await _claimMirror(installationKey);
  }

  Future<void> _claimMirror(String installationKey) async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser!.id;

    try {
      final installation = await client
          .from('installations')
          .select('id, status, name')
          .eq('installation_key', installationKey)
          .maybeSingle();

      if (installation == null) {
        _showError('Mirror not found. Please check the QR code and try again.');
        return;
      }

      if (installation['status'] == 'stolen') {
        _showError(
          'This mirror has been reported stolen and cannot be registered.',
        );
        return;
      }

      if (installation['status'] == 'active') {
        _showError('This mirror is already registered to another account.');
        return;
      }

      var property = await client
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
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() {
      _processing = false;
      _scanned = false;
    });
    _scanner.start();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.withValues(alpha: 0.8),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _showNameDialog(String defaultName) {
    final controller = TextEditingController(text: defaultName);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF111111),
        title: const Text(
          'NAME YOUR MIRROR',
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
              Navigator.pop(context);
              await _updateMirrorName(name);
              if (mounted) Navigator.pop(context, true);
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

  Future<void> _updateMirrorName(String name) async {
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
      body: Stack(
        children: [
          MobileScanner(controller: _scanner, onDetect: _onDetect),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 32),
                const Text(
                  'SCAN QR CODE',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    letterSpacing: 4,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Point your camera at the QR code\non your Aura mirror',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 13,
                    height: 1.6,
                  ),
                ),
                const Spacer(),
                Center(
                  child: Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white38, width: 2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const Spacer(),
                if (_processing)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 1,
                    ),
                  ),
                const SizedBox(height: 48),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
