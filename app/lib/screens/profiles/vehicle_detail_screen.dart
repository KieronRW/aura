// Vehicle detail screen — view vehicle info and manage reference images

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class VehicleDetailScreen extends StatefulWidget {
  final Map<String, dynamic> vehicle;

  const VehicleDetailScreen({super.key, required this.vehicle});

  @override
  State<VehicleDetailScreen> createState() => _VehicleDetailScreenState();
}

class _VehicleDetailScreenState extends State<VehicleDetailScreen> {
  late Map<String, dynamic> _vehicleData;
  List<Map<String, dynamic>> _referenceImages = [];
  bool _loading = true;
  bool _uploading = false;
  bool _deleting = false;
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _vehicleData = Map<String, dynamic>.from(widget.vehicle);
    _loadReferenceImages();
    _refreshVehicle();
  }

  Future<void> _refreshVehicle() async {
    try {
      final response = await Supabase.instance.client
          .from('vehicles')
          .select('*')
          .eq('id', widget.vehicle['id'])
          .single();
      if (mounted) setState(() => _vehicleData = response);
    } catch (e) {
      debugPrint('Refresh vehicle error: $e');
    }
  }

  Future<void> _loadReferenceImages() async {
    try {
      final response = await Supabase.instance.client
          .from('vehicle_reference_images')
          .select('*')
          .eq('vehicle_id', widget.vehicle['id'])
          .order('created_at');
      if (mounted) {
        setState(() {
          _referenceImages = List<Map<String, dynamic>>.from(response);
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Load reference images error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addImage(ImageSource source) async {
    try {
      final file = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1920,
      );
      if (file == null) return;

      setState(() => _uploading = true);

      final bytes = await File(file.path).readAsBytes();
      final vehicleId = widget.vehicle['id'] as String;
      final fileName =
          '$vehicleId/${DateTime.now().millisecondsSinceEpoch}.jpg';

      await Supabase.instance.client.storage
          .from('reference-images')
          .uploadBinary(
            fileName,
            bytes,
            fileOptions: const FileOptions(contentType: 'image/jpeg'),
          );

      await Supabase.instance.client.from('vehicle_reference_images').insert({
        'vehicle_id': vehicleId,
        'storage_path': fileName,
        'is_active': true,
      });

      await Supabase.instance.client
          .from('vehicles')
          .update({
            'reference_image_count': _referenceImages.length + 1,
            'fingerprint_seeded': false,
          })
          .eq('id', vehicleId);

      await _loadReferenceImages();
      await _refreshVehicle();
    } catch (e) {
      debugPrint('Upload reference image error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to upload image. Please try again.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _showImageSourceDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111111),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(
                Icons.camera_alt_outlined,
                color: Colors.white38,
              ),
              title: const Text(
                'Take photo',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                _addImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.photo_library_outlined,
                color: Colors.white38,
              ),
              title: const Text(
                'Choose from library',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                _addImage(ImageSource.gallery);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteImage(Map<String, dynamic> image) async {
    try {
      await Supabase.instance.client.storage.from('reference-images').remove([
        image['storage_path'],
      ]);

      await Supabase.instance.client
          .from('vehicle_reference_images')
          .delete()
          .eq('id', image['id']);

      await Supabase.instance.client
          .from('vehicles')
          .update({
            'reference_image_count': (_referenceImages.length - 1).clamp(
              0,
              999,
            ),
            'fingerprint_seeded': false,
          })
          .eq('id', widget.vehicle['id']);

      await _loadReferenceImages();
      await _refreshVehicle();
    } catch (e) {
      debugPrint('Delete reference image error: $e');
    }
  }

  Future<void> _deleteVehicle() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF111111),
        title: const Text(
          'Delete Vehicle',
          style: TextStyle(color: Colors.white, fontSize: 15, letterSpacing: 1),
        ),
        content: const Text(
          'This will permanently delete this vehicle and all its reference images. This cannot be undone.',
          style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'CANCEL',
              style: TextStyle(color: Colors.white38, letterSpacing: 1),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'DELETE',
              style: TextStyle(color: Colors.redAccent, letterSpacing: 1),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _deleting = true);

    try {
      if (_referenceImages.isNotEmpty) {
        final paths = _referenceImages
            .map((img) => img['storage_path'] as String)
            .toList();
        await Supabase.instance.client.storage
            .from('reference-images')
            .remove(paths);
      }

      await Supabase.instance.client
          .from('vehicle_reference_images')
          .delete()
          .eq('vehicle_id', widget.vehicle['id']);

      await Supabase.instance.client
          .from('vehicles')
          .delete()
          .eq('id', widget.vehicle['id']);

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint('Delete vehicle error: $e');
      if (mounted) {
        setState(() => _deleting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to delete vehicle. Please try again.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  String get _enrollmentStatus {
    final count = _referenceImages.length;
    if (_vehicleData['fingerprint_seeded'] == true) return 'ENROLLED';
    if (count >= 3) return 'READY TO ENROL';
    return 'PENDING ($count/3 images)';
  }

  Color get _enrollmentColor {
    if (_vehicleData['fingerprint_seeded'] == true) return Colors.greenAccent;
    if (_referenceImages.length >= 3) return Colors.orangeAccent;
    return Colors.white24;
  }

  @override
  Widget build(BuildContext context) {
    final vehicleName =
        _vehicleData['nickname'] ??
        '${_vehicleData['make'] ?? ''} ${_vehicleData['model'] ?? ''}'.trim();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          vehicleName.toUpperCase(),
          style: const TextStyle(
            fontSize: 13,
            letterSpacing: 4,
            fontWeight: FontWeight.w300,
          ),
        ),
      ),
      body: _deleting
          ? const Center(
              child: CircularProgressIndicator(
                color: Colors.white24,
                strokeWidth: 1,
              ),
            )
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  const Text(
                    'VEHICLE INFO',
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 3,
                      color: Colors.white24,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _InfoRow('Make', _vehicleData['make'] ?? '—'),
                  _InfoRow('Model', _vehicleData['model'] ?? '—'),
                  _InfoRow('Colour', _vehicleData['colour'] ?? '—'),
                  _InfoRow('Registration', _vehicleData['registration'] ?? '—'),
                  _InfoRow('Greeting', _vehicleData['owner_greeting'] ?? '—'),

                  const SizedBox(height: 32),

                  const Text(
                    'RECOGNITION',
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 3,
                      color: Colors.white24,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF111111),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: _enrollmentColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _enrollmentStatus,
                          style: TextStyle(
                            color: _enrollmentColor,
                            fontSize: 12,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'REFERENCE IMAGES',
                        style: TextStyle(
                          fontSize: 10,
                          letterSpacing: 3,
                          color: Colors.white24,
                        ),
                      ),
                      if (!_uploading)
                        GestureDetector(
                          onTap: _showImageSourceDialog,
                          child: const Icon(
                            Icons.add_a_photo_outlined,
                            color: Colors.white,
                            size: 20,
                          ),
                        )
                      else
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 1,
                            color: Colors.white24,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Minimum 3 images required from different angles for fingerprint recognition.',
                    style: TextStyle(
                      color: Colors.white24,
                      fontSize: 12,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 16),

                  if (_loading)
                    const Center(
                      child: CircularProgressIndicator(
                        color: Colors.white24,
                        strokeWidth: 1,
                      ),
                    )
                  else if (_referenceImages.isEmpty)
                    const Text(
                      'No reference images yet. Add at least 3 to enable fingerprint recognition.',
                      style: TextStyle(color: Colors.white24, fontSize: 13),
                    )
                  else
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 4,
                            mainAxisSpacing: 4,
                          ),
                      itemCount: _referenceImages.length,
                      itemBuilder: (context, index) {
                        final image = _referenceImages[index];
                        return _ReferenceImageTile(
                          key: ValueKey(image['id']),
                          storagePath: image['storage_path'],
                          onDelete: () => _deleteImage(image),
                        );
                      },
                    ),

                  const SizedBox(height: 48),
                  const Divider(color: Colors.white12),
                  const SizedBox(height: 24),

                  TextButton(
                    onPressed: _deleteVehicle,
                    child: const Text(
                      'DELETE VEHICLE',
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontSize: 13,
                        letterSpacing: 2,
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white12)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white38, fontSize: 13),
          ),
          Text(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _ReferenceImageTile extends StatefulWidget {
  final String storagePath;
  final VoidCallback onDelete;

  const _ReferenceImageTile({
    super.key,
    required this.storagePath,
    required this.onDelete,
  });

  @override
  State<_ReferenceImageTile> createState() => _ReferenceImageTileState();
}

class _ReferenceImageTileState extends State<_ReferenceImageTile> {
  String? _url;

  @override
  void initState() {
    super.initState();
    _loadUrl();
  }

  Future<void> _loadUrl() async {
    try {
      final url = await Supabase.instance.client.storage
          .from('reference-images')
          .createSignedUrl(widget.storagePath, 3600);
      if (mounted) setState(() => _url = url);
    } catch (e) {
      debugPrint('Signed URL error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          color: const Color(0xFF111111),
          child: _url != null
              ? Image.network(_url!, fit: BoxFit.cover)
              : const Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 1,
                    color: Colors.white24,
                  ),
                ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: widget.onDelete,
            child: Container(
              width: 24,
              height: 24,
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, color: Colors.redAccent, size: 14),
            ),
          ),
        ),
      ],
    );
  }
}
