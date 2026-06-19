// Vehicle detail screen — view vehicle info and manage reference images

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../providers/profile_provider.dart';
import '../../theme/aura_theme.dart';

class VehicleDetailScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> vehicle;

  const VehicleDetailScreen({super.key, required this.vehicle});

  @override
  ConsumerState<VehicleDetailScreen> createState() =>
      _VehicleDetailScreenState();
}

class _VehicleDetailScreenState extends ConsumerState<VehicleDetailScreen> {
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
          .or('angle.is.null,angle.neq.auto')
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
          SnackBar(
            content: Text('Failed to upload image. Please try again.', style: kBody()),
            backgroundColor: kError,
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
      backgroundColor: kCard,
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
                color: kCardBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(
                Icons.camera_alt_outlined,
                color: Color(0x80FFFFFF),
              ),
              title: Text(
                'Take photo',
                style: kBody(),
              ),
              onTap: () {
                Navigator.pop(context);
                _addImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.photo_library_outlined,
                color: Color(0x80FFFFFF),
              ),
              title: Text(
                'Choose from library',
                style: kBody(),
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
        backgroundColor: kCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: kCardBorder),
        ),
        title: Text(
          'Delete Vehicle',
          style: kHeading(),
        ),
        content: const Text(
          'This will permanently delete this vehicle and all its reference images. This cannot be undone.',
          style: TextStyle(color: Color(0xD9FFFFFF), fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'CANCEL',
              style: kBody(kVioletText),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'DELETE',
              style: kBody(kErrorText),
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

      if (mounted) {
        ref.invalidate(profilesProvider);
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint('Delete vehicle error: $e');
      if (mounted) {
        setState(() => _deleting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete vehicle. Please try again.', style: kBody()),
            backgroundColor: kError,
          ),
        );
      }
    }
  }

  String get _enrollmentStatus {
    final count = _referenceImages.length;
    final score = (_vehicleData['fingerprint_score'] as num?)?.toDouble();
    if (_vehicleData['fingerprint_seeded'] == true) {
      if (score != null && score >= 0.65) return 'ENROLLED';
      return 'ENROLLED (LOW QUALITY)';
    }
    if (count >= 3) return 'READY TO ENROL';
    return 'PENDING ($count/3 images)';
  }

  Color get _enrollmentColor {
    final score = (_vehicleData['fingerprint_score'] as num?)?.toDouble();
    if (_vehicleData['fingerprint_seeded'] == true) {
      if (score != null && score >= 0.65) return kOnlineText;
      return kWarningText;
    }
    if (_referenceImages.length >= 3) return kWarningText;
    return const Color(0x80FFFFFF);
  }

  @override
  Widget build(BuildContext context) {
    final vehicleName =
        _vehicleData['nickname'] ??
        '${_vehicleData['make'] ?? ''} ${_vehicleData['model'] ?? ''}'.trim();

    return Scaffold(
      backgroundColor: kVoid,
      appBar: AppBar(
        backgroundColor: kVoid,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          vehicleName.toUpperCase(),
          style: kHeading(),
        ),
      ),
      body: _deleting
          ? const Center(
              child: CircularProgressIndicator(
                color: kViolet,
                strokeWidth: 1.5,
              ),
            )
          : Container(
              decoration: const BoxDecoration(gradient: kBgGradient),
              child: SafeArea(
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    Text(
                      'VEHICLE INFO',
                      style: kLabel(),
                    ),
                    const SizedBox(height: 12),
                    _InfoRow('Make', _vehicleData['make'] ?? '—'),
                    _InfoRow('Model', _vehicleData['model'] ?? '—'),
                    _InfoRow('Colour', _vehicleData['colour'] ?? '—', mono: true),
                    _InfoRow('Registration', _vehicleData['registration'] ?? '—', mono: true),
                    _InfoRow('Greeting', _vehicleData['owner_greeting'] ?? '—'),

                    const SizedBox(height: 32),

                    Text(
                      'RECOGNITION',
                      style: kLabel(),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: kCard,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: kCardBorder),
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
                          Expanded(
                            child: Text(
                              _enrollmentStatus,
                              style: kLabel(_enrollmentColor),
                            ),
                          ),
                          if (_vehicleData['fingerprint_score'] != null)
                            Text(
                              '${((_vehicleData['fingerprint_score'] as num).toDouble() * 100).toStringAsFixed(0)}%',
                              style: kCaption(const Color(0x40FFFFFF)),
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'REFERENCE IMAGES',
                          style: kLabel(),
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
                              strokeWidth: 1.5,
                              color: kViolet,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Minimum 3 images required from different angles for fingerprint recognition.',
                      style: kCaption(),
                    ),
                    const SizedBox(height: 16),

                    if (_loading)
                      const Center(
                        child: CircularProgressIndicator(
                          color: kViolet,
                          strokeWidth: 1.5,
                        ),
                      )
                    else if (_referenceImages.isEmpty)
                      Text(
                        'No reference images yet. Add at least 3 to enable fingerprint recognition.',
                        style: kCaption(),
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
                    const Divider(color: kRowDivider),
                    const SizedBox(height: 24),

                    TextButton(
                      onPressed: _deleteVehicle,
                      child: Text(
                        'DELETE VEHICLE',
                        style: kBody(kErrorText),
                      ),
                    ),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool mono;

  const _InfoRow(this.label, this.value, {this.mono = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: kRowDivider)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: kCaption(),
          ),
          Text(
            value,
            style: mono ? kMono() : kBody(),
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
  static final Map<String, String> _signedUrlCache = {};

  String? _url;

  @override
  void initState() {
    super.initState();
    _loadUrl();
  }

  Future<void> _loadUrl() async {
    final cached = _signedUrlCache[widget.storagePath];
    if (cached != null) {
      if (mounted) setState(() => _url = cached);
      return;
    }
    try {
      final url = await Supabase.instance.client.storage
          .from('reference-images')
          .createSignedUrl(widget.storagePath, 3600);
      _signedUrlCache[widget.storagePath] = url;
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
          color: kCardDim,
          child: _url != null
              ? Image.network(_url!, fit: BoxFit.cover)
              : const Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: kViolet,
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
              child: Icon(Icons.close, color: kErrorText, size: 14),
            ),
          ),
        ),
      ],
    );
  }
}
