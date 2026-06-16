import 'package:flutter/material.dart';

// Internal pulsing wrapper — shared animation to keep all skeleton variants in sync.
class _Pulse extends StatefulWidget {
  final Widget child;
  const _Pulse({required this.child});

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _opacity = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: _opacity, child: widget.child);
}

// ── Public widgets ────────────────────────────────────────────────────────────

class SkeletonBox extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;

  const SkeletonBox({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 8,
  });

  @override
  Widget build(BuildContext context) => _Pulse(
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: const Color(0xFF222222),
            borderRadius: BorderRadius.circular(borderRadius),
          ),
        ),
      );
}

class SkeletonText extends StatelessWidget {
  final double width;
  final int lines;
  final bool heading;

  const SkeletonText({
    super.key,
    required this.width,
    this.lines = 1,
    this.heading = false,
  });

  @override
  Widget build(BuildContext context) {
    final h = heading ? 24.0 : 16.0;
    if (lines == 1) {
      return SkeletonBox(width: width, height: h, borderRadius: 4);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(lines, (i) {
        final lineWidth = i == lines - 1 ? width * 0.7 : width;
        return Padding(
          padding: EdgeInsets.only(bottom: i < lines - 1 ? 6 : 0),
          child: SkeletonBox(width: lineWidth, height: h, borderRadius: 4),
        );
      }),
    );
  }
}

class SkeletonCard extends StatelessWidget {
  final double? height;
  final EdgeInsets padding;

  const SkeletonCard({
    super.key,
    this.height,
    this.padding = const EdgeInsets.all(20),
  });

  @override
  Widget build(BuildContext context) => _Pulse(
        child: Container(
          height: height,
          padding: padding,
          decoration: BoxDecoration(
            color: const Color(0xFF111111),
            border: Border.all(color: const Color(0xFF222222)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 13,
                width: 140,
                decoration: BoxDecoration(
                  color: const Color(0xFF222222),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                height: 11,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1C1C),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
        ),
      );
}

class SkeletonAvatar extends StatelessWidget {
  final double size;

  const SkeletonAvatar({super.key, this.size = 40});

  @override
  Widget build(BuildContext context) => _Pulse(
        child: Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(
            color: Color(0xFF222222),
            shape: BoxShape.circle,
          ),
        ),
      );
}

class SkeletonList extends StatelessWidget {
  final int itemCount;
  final Widget Function(BuildContext, int)? itemBuilder;

  const SkeletonList({
    super.key,
    this.itemCount = 5,
    this.itemBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(itemCount, (i) {
        return Padding(
          padding: EdgeInsets.only(bottom: i < itemCount - 1 ? 12 : 0),
          child: itemBuilder != null
              ? itemBuilder!(context, i)
              : const SkeletonCard(),
        );
      }),
    );
  }
}

/// Placeholder that matches the visual shape of a settings slider row.
class SkeletonSettingsRow extends StatelessWidget {
  const SkeletonSettingsRow({super.key});

  @override
  Widget build(BuildContext context) => _Pulse(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Container(
                width: 90,
                height: 11,
                decoration: BoxDecoration(
                  color: const Color(0xFF222222),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  height: 2,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C1C1C),
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 32,
                height: 11,
                decoration: BoxDecoration(
                  color: const Color(0xFF222222),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ],
          ),
        ),
      );
}
