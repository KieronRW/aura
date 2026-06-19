import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/aura_theme.dart';

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
        content: Text(message, style: kBody()),
        backgroundColor: kError,
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
              Navigator.pop(context);
              await _updateMirrorName(name);
              if (mounted) Navigator.pop(context, true);
            },
            child: Text('Done', style: kBody(kVioletText)),
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
      backgroundColor: kVoid,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text('Add Aura', style: kHeading()),
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          MobileScanner(controller: _scanner, onDetect: _onDetect),
          // Vignette overlay so text stays readable over camera
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.2,
                colors: [Colors.transparent, Color(0xCC000000)],
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 24),
                Text('Scan QR code', style: kLabel()),
                const SizedBox(height: 8),
                Text(
                  'Point your camera at the QR code\non your Aura mirror',
                  textAlign: TextAlign.center,
                  style: kCaption(),
                ),
                const Spacer(),
                Center(
                  child: Container(
                    width: 220,
                    height: 220,
                    decoration: BoxDecoration(
                      border: Border.all(color: kViolet, width: 2),
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                const Spacer(),
                if (_processing)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(
                      color: kCyan,
                      strokeWidth: 1.5,
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
