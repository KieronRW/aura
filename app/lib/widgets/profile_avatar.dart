import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class InitialAvatar extends StatelessWidget {
  final String name;
  final double fontSize;

  const InitialAvatar({super.key, required this.name, this.fontSize = 18});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF111111),
      child: Center(
        child: Text(
          name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?',
          style: TextStyle(
            color: Colors.white,
            fontSize: fontSize,
            fontWeight: FontWeight.w200,
          ),
        ),
      ),
    );
  }
}

class ProfileAvatar extends StatefulWidget {
  final String? avatarPath;
  final String? avatarUpdatedAt;
  final String displayName;
  final double size;
  final double fontSize;

  const ProfileAvatar({
    super.key,
    this.avatarPath,
    this.avatarUpdatedAt,
    required this.displayName,
    required this.size,
    required this.fontSize,
  });

  @override
  State<ProfileAvatar> createState() => ProfileAvatarState();
}

class ProfileAvatarState extends State<ProfileAvatar> {
  String? _signedUrl;

  @override
  void initState() {
    super.initState();
    _loadAvatar();
  }

  @override
  void didUpdateWidget(ProfileAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.avatarPath != widget.avatarPath ||
        oldWidget.avatarUpdatedAt != widget.avatarUpdatedAt) {
      _signedUrl = null;
      _loadAvatar();
    }
  }

  Future<void> _loadAvatar() async {
    final path = widget.avatarPath;
    if (path == null || path.isEmpty) return;
    final capturedPath = path;
    final capturedUpdatedAt = widget.avatarUpdatedAt;
    try {
      await DefaultCacheManager().removeFile(path);
      final url = await Supabase.instance.client.storage
          .from('avatars')
          .createSignedUrl(path, 3600);
      if (mounted &&
          capturedPath == widget.avatarPath &&
          capturedUpdatedAt == widget.avatarUpdatedAt) {
        setState(() => _signedUrl = url);
      }
    } catch (e) {
      debugPrint('Avatar signed URL error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white24),
      ),
      child: ClipOval(
        child: _signedUrl != null
            ? CachedNetworkImage(
                imageUrl: _signedUrl!,
                cacheKey: widget.avatarPath,
                fit: BoxFit.cover,
                placeholder: (_, _) => InitialAvatar(
                  name: widget.displayName,
                  fontSize: widget.fontSize,
                ),
                errorWidget: (_, _, _) => InitialAvatar(
                  name: widget.displayName,
                  fontSize: widget.fontSize,
                ),
              )
            : InitialAvatar(
                name: widget.displayName,
                fontSize: widget.fontSize,
              ),
      ),
    );
  }
}
