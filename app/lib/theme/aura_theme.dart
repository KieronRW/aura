// Shared design tokens and common widgets for the Aura app.
// All values derived from the Claude Design handoff (June 2026).

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ─── Colors ───────────────────────────────────────────────────────────────────
const kVoid = Color(0xFF050506);
const kBase = Color(0xFF0A0A0D);
const kSurface = Color(0xFF1A1C24);
const kCard = Color(0xFF16171B);
const kCardDim = Color(0xFF141418);
const kCyan = Color(0xFF3AA8E0);
const kViolet = Color(0xFF6F6CE8);
const kVioletText = Color(0xFF8B8CE8);
const kMagenta = Color(0xFFC24DD9);
const kOnline = Color(0xFF34C77B);
const kOnlineText = Color(0xFF5FD99B);
const kWarning = Color(0xFFE0B341);
const kWarningText = Color(0xFFE8C66E);
const kError = Color(0xFFE0574E);
const kErrorText = Color(0xFFEC8079);
const kInfo = Color(0xFF5A8DE0);
const kInfoText = Color(0xFF86AAE8);

// ─── Gradient ─────────────────────────────────────────────────────────────────
const kPrimaryGradient = LinearGradient(colors: [kCyan, kViolet]);

const kBgGradient = RadialGradient(
  center: Alignment(0, -0.6),
  radius: 1.3,
  colors: [kSurface, kBase, kVoid],
  stops: [0.0, 0.55, 1.0],
);

// ─── Text styles (Manrope) ────────────────────────────────────────────────────
TextStyle kDisplay([Color color = Colors.white]) =>
    GoogleFonts.manrope(fontSize: 40, fontWeight: FontWeight.w700, letterSpacing: -1, color: color);

TextStyle kScreenTitle([Color color = Colors.white]) =>
    GoogleFonts.manrope(fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.4, color: color);

TextStyle kTitle([Color color = Colors.white]) =>
    GoogleFonts.manrope(fontSize: 23, fontWeight: FontWeight.w600, letterSpacing: -0.2, color: color);

TextStyle kHeading([Color color = Colors.white]) =>
    GoogleFonts.manrope(fontSize: 17, fontWeight: FontWeight.w600, color: color);

TextStyle kBody([Color color = const Color(0xD9FFFFFF)]) =>
    GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w400, color: color);

TextStyle kCaption([Color color = const Color(0x80FFFFFF)]) =>
    GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w500, color: color);

TextStyle kLabel([Color color = const Color(0x73FFFFFF)]) =>
    GoogleFonts.manrope(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 2, color: color);

TextStyle kMono([Color color = const Color(0xD9FFFFFF)]) =>
    TextStyle(fontFamily: 'Menlo', fontSize: 13, color: color, letterSpacing: 0.3);

// ─── Background ───────────────────────────────────────────────────────────────
Widget auraBackground({Widget? child}) => Container(
  decoration: const BoxDecoration(gradient: kBgGradient),
  child: child,
);

// ─── Hairline border ──────────────────────────────────────────────────────────
const kCardBorder = Color(0x14FFFFFF);     // rgba(255,255,255,0.08)
const kInputBorder = Color(0x1FFFFFFF);    // rgba(255,255,255,0.12)
const kRowDivider = Color(0x0FFFFFFF);     // rgba(255,255,255,0.06)

// ─── Common widgets ───────────────────────────────────────────────────────────

/// Styled input field matching the design spec.
class AuraField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final Widget? prefixIcon;
  final Widget? suffix;
  final bool obscureText;
  final TextInputType? keyboardType;
  final bool readOnly;
  final VoidCallback? onTap;

  const AuraField({
    super.key,
    required this.controller,
    required this.hint,
    this.prefixIcon,
    this.suffix,
    this.obscureText = false,
    this.keyboardType,
    this.readOnly = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      decoration: BoxDecoration(
        color: const Color(0x0EFFFFFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kInputBorder),
      ),
      child: Row(
        children: [
          if (prefixIcon != null) ...[
            const SizedBox(width: 15),
            prefixIcon!,
            const SizedBox(width: 11),
          ] else
            const SizedBox(width: 16),
          Expanded(
            child: TextField(
              controller: controller,
              obscureText: obscureText,
              keyboardType: keyboardType,
              readOnly: readOnly,
              onTap: onTap,
              style: kBody(),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: kBody(const Color(0x66FFFFFF)),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          if (suffix != null) ...[
            const SizedBox(width: 8),
            suffix!,
            const SizedBox(width: 12),
          ],
        ],
      ),
    );
  }
}

/// Gradient primary button.
class AuraPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool loading;
  final Widget? icon;

  const AuraPrimaryButton({
    super.key,
    required this.label,
    this.onTap,
    this.loading = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        height: 55,
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [kCyan, kViolet]),
          borderRadius: BorderRadius.circular(15),
          boxShadow: const [
            BoxShadow(
              color: Color(0x8C6366E8),
              blurRadius: 22,
              offset: Offset(0, 8),
              spreadRadius: -12,
            ),
          ],
        ),
        alignment: Alignment.center,
        child: loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[icon!, const SizedBox(width: 8)],
                  Text(label, style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                ],
              ),
      ),
    );
  }
}

/// Glass / secondary button.
class AuraSecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final Widget? icon;

  const AuraSecondaryButton({
    super.key,
    required this.label,
    this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: const Color(0x0EFFFFFF),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: kInputBorder),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[icon!, const SizedBox(width: 8)],
            Text(label, style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w500, color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

/// Card container with hairline border.
class AuraCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final BorderRadius? radius;
  final VoidCallback? onTap;

  const AuraCard({
    super.key,
    required this.child,
    this.padding,
    this.color,
    this.radius,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: padding ?? const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color ?? kCard,
          borderRadius: radius ?? BorderRadius.circular(18),
          border: Border.all(color: kCardBorder),
        ),
        child: child,
      ),
    );
  }
}

/// Status chip (Online / Offline / etc.)
class AuraChip extends StatelessWidget {
  final String label;
  final Color color;
  final Color textColor;

  const AuraChip({
    super.key,
    required this.label,
    required this.color,
    required this.textColor,
  });

  factory AuraChip.online() =>
      const AuraChip(label: 'Online', color: Color(0x2934C77B), textColor: kOnlineText);

  factory AuraChip.offline() =>
      const AuraChip(label: 'Offline', color: Color(0x29E0574E), textColor: kErrorText);

  factory AuraChip.ready() =>
      const AuraChip(label: 'Ready', color: Color(0x2934C77B), textColor: kOnlineText);

  factory AuraChip.claimed() =>
      const AuraChip(label: 'Claimed', color: Color(0x295A8DE0), textColor: kInfoText);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: GoogleFonts.manrope(fontSize: 12, fontWeight: FontWeight.w600, color: textColor)),
    );
  }
}

/// List row with icon, title, subtitle, trailing chevron.
class AuraListRow extends StatelessWidget {
  final IconData? icon;
  final Widget? iconWidget;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showDivider;

  const AuraListRow({
    super.key,
    this.icon,
    this.iconWidget,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                if (iconWidget != null) iconWidget!
                else if (icon != null)
                  Icon(icon, color: const Color(0x80FFFFFF), size: 20),
                if (icon != null || iconWidget != null) const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: kBody()),
                      if (subtitle != null && subtitle!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(subtitle!, style: kCaption()),
                        ),
                    ],
                  ),
                ),
                if (trailing != null)
                  trailing!
                else if (onTap != null)
                  const Icon(Icons.chevron_right, color: Color(0x40FFFFFF), size: 20),
              ],
            ),
          ),
          if (showDivider)
            Container(height: 1, margin: const EdgeInsets.only(left: 16), color: kRowDivider),
        ],
      ),
    );
  }
}

/// Section header label (UPPERCASE, spaced).
class AuraSectionHeader extends StatelessWidget {
  final String title;

  const AuraSectionHeader({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8, left: 4),
      child: Text(title.toUpperCase(), style: kLabel()),
    );
  }
}

/// Back-button screen header used by settings sub-screens.
class AuraScreenHeader extends StatelessWidget {
  final String title;
  final bool saving;

  const AuraScreenHeader({super.key, required this.title, this.saving = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: kCard,
                  shape: BoxShape.circle,
                  border: Border.all(color: kCardBorder),
                ),
                child: const Icon(Icons.arrow_back, color: Colors.white, size: 18),
              ),
            ),
          ),
          Text(title, style: kTitle()),
          Align(
            alignment: Alignment.centerRight,
            child: AnimatedOpacity(
              opacity: saving ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(color: kCyan, strokeWidth: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Standard dark snackbar.
SnackBar auraSnackBar(String message, {bool isError = false}) => SnackBar(
  content: Text(message, style: GoogleFonts.manrope(color: Colors.white, fontSize: 14)),
  backgroundColor: isError ? kError.withValues(alpha: 0.9) : kCard,
  behavior: SnackBarBehavior.floating,
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
);

/// Styled AlertDialog for dark theme.
Future<T?> showAuraDialog<T>({
  required BuildContext context,
  required String title,
  required Widget content,
  required List<Widget> actions,
}) => showDialog<T>(
  context: context,
  barrierColor: Colors.black54,
  builder: (_) => AlertDialog(
    backgroundColor: kCard,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: const BorderSide(color: kCardBorder),
    ),
    title: Text(title, style: kHeading()),
    content: content,
    actions: actions,
  ),
);

/// Toggle switch styled to spec: cyan→violet when ON, muted when OFF.
class AuraToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const AuraToggle({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 46,
        height: 28,
        decoration: BoxDecoration(
          gradient: value ? const LinearGradient(colors: [kCyan, kViolet]) : null,
          color: value ? null : const Color(0x1FFFFFFF),
          borderRadius: BorderRadius.circular(14),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 22,
            height: 22,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: value ? 1.0 : 0.7),
              shape: BoxShape.circle,
              boxShadow: const [
                BoxShadow(color: Color(0x80000000), blurRadius: 8, offset: Offset(0, 2)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Styled slider matching spec: cyan→violet fill, white thumb.
class AuraSlider extends StatelessWidget {
  final double value;
  final double min;
  final double max;
  final ValueChanged<double>? onChanged;
  final String? label;

  const AuraSlider({
    super.key,
    required this.value,
    this.min = 0,
    this.max = 1,
    this.onChanged,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    return SliderTheme(
      data: SliderThemeData(
        activeTrackColor: kViolet,
        inactiveTrackColor: const Color(0x1FFFFFFF),
        thumbColor: Colors.white,
        overlayColor: kViolet.withValues(alpha: 0.2),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 11),
        trackHeight: 4,
        trackShape: const RoundedRectSliderTrackShape(),
      ),
      child: Slider(value: value, min: min, max: max, onChanged: onChanged),
    );
  }
}
