// Recognition history for a profile — used as tab content in profile detail

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/aura_theme.dart';

class RecognitionHistoryScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> profile;

  const RecognitionHistoryScreen({super.key, required this.profile});

  @override
  ConsumerState<RecognitionHistoryScreen> createState() =>
      _RecognitionHistoryScreenState();
}

class _RecognitionHistoryScreenState
    extends ConsumerState<RecognitionHistoryScreen> {
  List<Map<String, dynamic>> _events = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  static const int _pageSize = 20;

  final Map<String, String> _signedUrlCache = {};

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  Future<void> _loadEvents({bool loadMore = false}) async {
    if (loadMore && (!_hasMore || _loadingMore)) return;
    if (loadMore) {
      setState(() => _loadingMore = true);
    } else {
      setState(() {
        _loading = true;
        _events = [];
        _hasMore = true;
      });
    }

    try {
      final vehiclesResp = await Supabase.instance.client
          .from('vehicles')
          .select('id')
          .eq('profile_id', widget.profile['id'])
          .eq('is_active', true);
      final vehicleIds =
          (vehiclesResp as List).map((v) => v['id'] as String).toList();

      if (vehicleIds.isEmpty) {
        if (mounted) setState(() { _loading = false; _loadingMore = false; _hasMore = false; });
        return;
      }

      final offset = loadMore ? _events.length : 0;
      final response = await Supabase.instance.client
          .from('recognition_events')
          .select('*')
          .inFilter('vehicle_id', vehicleIds)
          .order('arrived_at', ascending: false)
          .range(offset, offset + _pageSize - 1);

      final newEvents = List<Map<String, dynamic>>.from(response as List);
      if (mounted) {
        setState(() {
          if (loadMore) {
            _events.addAll(newEvents);
          } else {
            _events = newEvents;
          }
          _hasMore = newEvents.length == _pageSize;
          _loading = false;
          _loadingMore = false;
        });
      }
    } catch (e) {
      debugPrint('Recognition history error: $e');
      if (mounted) setState(() { _loading = false; _loadingMore = false; });
    }
  }

  Future<String?> _getSignedUrl(String path) async {
    if (_signedUrlCache.containsKey(path)) return _signedUrlCache[path];
    try {
      final url = await Supabase.instance.client.storage
          .from('recognition-images')
          .createSignedUrl(path, 3600);
      _signedUrlCache[path] = url;
      return url;
    } catch (_) {
      return null;
    }
  }

  String _formatTs(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.parse(iso).toLocal();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} ${months[dt.month - 1]}, $h:$m';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: kViolet, strokeWidth: 1.5),
      );
    }

    if (_events.isEmpty) {
      return Center(
        child: Text(
          'No recognition history yet',
          style: kCaption(const Color(0x1AFFFFFF)),
        ),
      );
    }

    return Container(
      decoration: const BoxDecoration(gradient: kBgGradient),
      child: NotificationListener<ScrollNotification>(
        onNotification: (scroll) {
          if (scroll.metrics.pixels >= scroll.metrics.maxScrollExtent - 200) {
            _loadEvents(loadMore: true);
          }
          return false;
        },
        child: ListView.builder(
          padding: const EdgeInsets.all(24),
          itemCount: _events.length + (_loadingMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == _events.length) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(
                    color: kViolet,
                    strokeWidth: 1.5,
                  ),
                ),
              );
            }
            final event = _events[index];
            return _HistoryEventRow(
              event: event,
              getSignedUrl: _getSignedUrl,
              formatTs: _formatTs,
            );
          },
        ),
      ),
    );
  }
}

class _HistoryEventRow extends StatefulWidget {
  final Map<String, dynamic> event;
  final Future<String?> Function(String) getSignedUrl;
  final String Function(String?) formatTs;

  const _HistoryEventRow({
    required this.event,
    required this.getSignedUrl,
    required this.formatTs,
  });

  @override
  State<_HistoryEventRow> createState() => _HistoryEventRowState();
}

class _HistoryEventRowState extends State<_HistoryEventRow> {
  String? _imageUrl;

  @override
  void initState() {
    super.initState();
    final path = widget.event['image_path'] as String?;
    if (path != null) {
      widget.getSignedUrl(path).then((url) {
        if (mounted && url != null) setState(() => _imageUrl = url);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final make = widget.event['detected_make'] as String? ?? 'Unknown';
    final model = widget.event['detected_model'] as String?;
    final arrivedAt = widget.event['arrived_at'] as String?;
    final departedAt = widget.event['departed_at'] as String?;

    final vehicleLabel = model != null ? '$make · $model' : make;
    String timeLabel = widget.formatTs(arrivedAt);
    if (departedAt != null) {
      timeLabel += ' → ${widget.formatTs(departedAt)}';
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: kRowDivider)),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: kCardDim,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: kCardBorder),
            ),
            child: _imageUrl != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: CachedNetworkImage(
                      imageUrl: _imageUrl!,
                      fit: BoxFit.cover,
                      placeholder: (_, _) => const Center(
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: kViolet,
                          ),
                        ),
                      ),
                      errorWidget: (_, _, _) => const Icon(
                        Icons.directions_car_outlined,
                        color: Color(0x40FFFFFF),
                        size: 24,
                      ),
                    ),
                  )
                : const Icon(
                    Icons.directions_car_outlined,
                    color: Color(0x40FFFFFF),
                    size: 24,
                  ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  vehicleLabel,
                  style: kBody(),
                ),
                const SizedBox(height: 4),
                Text(
                  timeLabel,
                  style: kCaption(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
