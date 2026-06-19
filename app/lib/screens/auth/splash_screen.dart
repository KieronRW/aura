import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../home/home_screen.dart';
import 'register_screen.dart';

// ─── Design tokens ────────────────────────────────────────────────────────────
const _kVoid = Color(0xFF050506);
const _kBase = Color(0xFF0A0A0D);
const _kSurface = Color(0xFF1A1C24);
const _kCyan = Color(0xFF3AA8E0);
const _kViolet = Color(0xFF6F6CE8);
const _kVioletText = Color(0xFF8B8CE8);
const _kErrorText = Color(0xFFEC8079);

// ─── Shader state ─────────────────────────────────────────────────────────────
// Lives outside the widget tree so the CustomPainter can listen to it directly
// and repaint without rebuilding the whole widget tree.
class _ShaderState extends ChangeNotifier {
  double time = 0;
  double brightness = 1.0;
  double targetBrightness = 1.0;

  void tick() {
    // Match the JS: uniforms.time.value += 0.05 per animation frame.
    // brightness lerps toward target at 0.045/frame (also from the JS).
    time += 0.05;
    brightness += (targetBrightness - brightness) * 0.045;
    notifyListeners();
  }
}

// ─── Screen ───────────────────────────────────────────────────────────────────
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // Shader
  final _shaderState = _ShaderState();
  ui.FragmentShader? _fragShader;
  late Ticker _shaderTicker;

  // Timeline: 5 000 ms, drives all UI animations.
  late AnimationController _timeline;
  late Animation<double> _logoOpacity;
  late Animation<double> _logoMorph; // 0 = centred full-size, 1 = top small
  late Animation<double> _overlayOpacity;

  // 8 form items staggered from t = 3 050 ms.
  final List<Animation<double>> _formOpacity = [];
  final List<Animation<double>> _formTranslate = [];

  // Login
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  String? _loginError;
  bool _obscurePassword = true;

  // ─── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _loadShader();
    _buildTimeline();

    _shaderTicker = createTicker((_) {
      _shaderState.targetBrightness = _timeline.value >= 0.46 ? 0.16 : 1.0;
      _shaderState.tick();
    });
    _shaderTicker.start();
    _timeline.forward();
  }

  Future<void> _loadShader() async {
    try {
      final program = await ui.FragmentProgram.fromAsset(
        'shaders/aura_shader.frag',
      );
      if (mounted) setState(() => _fragShader = program.fragmentShader());
    } catch (_) {
      // Shader unavailable – background gradient still shows, app is functional.
    }
  }

  void _buildTimeline() {
    _timeline = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5000),
    );

    // Logo fades in at t = 150 ms over ~400 ms.
    _logoOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _timeline,
        curve: const Interval(0.030, 0.110, curve: Curves.easeOut),
      ),
    );

    // Logo morphs at 2 300 ms over 1 150 ms using the spec cubic.
    _logoMorph = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _timeline,
        curve: const Interval(0.46, 0.69, curve: Cubic(0.65, 0, 0.2, 1)),
      ),
    );

    // Dark glow overlay fades in at 2 300 ms over 1 200 ms.
    _overlayOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _timeline,
        curve: const Interval(0.46, 0.70, curve: Curves.easeOut),
      ),
    );

    // Form items: 8 children staggered from 3 050 ms.
    // HTML delays: 0 / 70 / 130 / 180 / 240 / 300 / 360 / 430 ms.
    // Each item transitions over 600 ms (0.120 of the 5 s timeline).
    const delays = [0.000, 0.014, 0.026, 0.036, 0.048, 0.060, 0.072, 0.086];
    for (final d in delays) {
      final s = 0.610 + d;
      final e = (s + 0.120).clamp(0.0, 1.0);
      _formOpacity.add(
        Tween<double>(begin: 0, end: 1).animate(
          CurvedAnimation(
            parent: _timeline,
            curve: Interval(s, e, curve: Curves.easeOut),
          ),
        ),
      );
      _formTranslate.add(
        Tween<double>(begin: 16, end: 0).animate(
          CurvedAnimation(
            parent: _timeline,
            curve: Interval(s, e, curve: Curves.easeOut),
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _shaderTicker.dispose();
    _timeline.dispose();
    _shaderState.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  // ─── Auth ───────────────────────────────────────────────────────────────────
  Future<void> _signIn() async {
    setState(() {
      _loading = true;
      _loginError = null;
    });
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text.trim(),
      );
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    } on AuthException catch (e) {
      setState(() => _loginError = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ─── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final safePad = MediaQuery.of(context).padding;
    final keyboardBottom = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      backgroundColor: _kVoid,
      resizeToAvoidBottomInset: false,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Stack(
          children: [
            // 1 ── Background radial gradient (always visible; shader fallback)
            Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -0.6),
                  radius: 1.3,
                  colors: [_kSurface, _kBase, _kVoid],
                  stops: [0.0, 0.55, 1.0],
                ),
              ),
            ),

            // 2 ── Animated shader (filled, drawn as a CustomPainter for efficiency)
            if (_fragShader != null)
              Positioned.fill(
                child: CustomPaint(
                  painter: _AuraShaderPainter(_fragShader!, _shaderState),
                ),
              ),

            // 3 ── Dark glow overlay (fades in during morph)
            AnimatedBuilder(
              animation: _overlayOpacity,
              builder: (context, child) => Opacity(
                opacity: _overlayOpacity.value,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, -0.92),
                      radius: 1.5,
                      colors: [
                        const Color(0xFF38468C).withValues(alpha: 0.30),
                        const Color(0xFF0A0A10).withValues(alpha: 0.92),
                        const Color(0xFF060608),
                      ],
                      stops: const [0.0, 0.42, 0.78],
                    ),
                  ),
                ),
              ),
            ),

            // 4 ── Logo: fades in at centre, morphs to top-small at 2 300 ms
            AnimatedBuilder(
              animation: _timeline,
              builder: (context, child) {
                final morph = _logoMorph.value;
                final scale = 1.0 - 0.0 * morph;
                // 272 / 842 ≈ 0.323 – the proportion from the design spec
                final yOffset = -0.323 * size.height * morph;
                return Opacity(
                  opacity: _logoOpacity.value,
                  child: Transform.translate(
                    offset: Offset(0, yOffset),
                    child: Transform.scale(
                      scale: scale,
                      child: Center(
                        child: Image.asset(
                          'assets/images/aura-logo.png',
                          width: 200,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),

            // 5 ── Sign-in form (bottom-anchored, rises above keyboard)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  30,
                  0,
                  30,
                  46 + safePad.bottom + keyboardBottom,
                ),
                child: AnimatedBuilder(
                  animation: _timeline,
                  builder: (context, child) => Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _rise(0, _buildHeading()),
                      const SizedBox(height: 20),
                      _rise(
                        1,
                        _buildField(
                          controller: _emailCtrl,
                          hint: 'Email address',
                          prefixIcon: const Icon(
                            Icons.mail_outline,
                            color: Color(0x66FFFFFF),
                            size: 19,
                          ),
                          keyboardType: TextInputType.emailAddress,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _rise(
                        2,
                        _buildField(
                          controller: _passwordCtrl,
                          hint: 'Password',
                          prefixIcon: const Icon(
                            Icons.lock_outline,
                            color: Color(0x66FFFFFF),
                            size: 19,
                          ),
                          obscureText: _obscurePassword,
                          suffix: GestureDetector(
                            onTap: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                            child: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color: const Color(0x66FFFFFF),
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _rise(
                        3,
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            'Forgot password?',
                            style: GoogleFonts.manrope(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w500,
                              color: const Color(0x99FFFFFF),
                            ),
                          ),
                        ),
                      ),
                      if (_loginError != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _loginError!,
                          style: GoogleFonts.manrope(
                            fontSize: 13,
                            color: _kErrorText,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      _rise(4, _buildSignInButton()),
                      const SizedBox(height: 20),
                      _rise(5, _buildDivider()),
                      const SizedBox(height: 14),
                      _rise(6, _buildSocialRow()),
                      const SizedBox(height: 20),
                      _rise(7, _buildRegisterLink()),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Form helpers ────────────────────────────────────────────────────────────

  Widget _rise(int i, Widget child) {
    return Opacity(
      opacity: _formOpacity[i].value,
      child: Transform.translate(
        offset: Offset(0, _formTranslate[i].value),
        child: child,
      ),
    );
  }

  Widget _buildHeading() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'Welcome back',
          textAlign: TextAlign.center,
          style: GoogleFonts.manrope(
            fontSize: 23,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          'Sign in to continue your journey',
          textAlign: TextAlign.center,
          style: GoogleFonts.manrope(
            fontSize: 14,
            color: const Color(0x80FFFFFF),
          ),
        ),
      ],
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String hint,
    required Widget prefixIcon,
    bool obscureText = false,
    TextInputType? keyboardType,
    Widget? suffix,
  }) {
    return Container(
      height: 54,
      decoration: BoxDecoration(
        color: const Color(0x0EFFFFFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x1FFFFFFF)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 15),
          prefixIcon,
          const SizedBox(width: 11),
          Expanded(
            child: TextField(
              controller: controller,
              obscureText: obscureText,
              keyboardType: keyboardType,
              style: GoogleFonts.manrope(color: Colors.white, fontSize: 15),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: GoogleFonts.manrope(
                  color: const Color(0x66FFFFFF),
                  fontSize: 15,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          if (suffix != null) ...[
            const SizedBox(width: 8),
            suffix,
            const SizedBox(width: 12),
          ],
        ],
      ),
    );
  }

  Widget _buildSignInButton() {
    return GestureDetector(
      onTap: _loading ? null : _signIn,
      child: Container(
        height: 55,
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [_kCyan, _kViolet]),
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
        child: _loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(
                'Sign in',
                style: GoogleFonts.manrope(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
      ),
    );
  }

  Widget _buildDivider() {
    const line = Color(0x1FFFFFFF);
    return Row(
      children: [
        Expanded(child: Container(height: 1, color: line)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            'or continue with',
            style: GoogleFonts.manrope(
              fontSize: 12.5,
              color: const Color(0x59FFFFFF),
            ),
          ),
        ),
        Expanded(child: Container(height: 1, color: line)),
      ],
    );
  }

  Widget _buildSocialRow() {
    return Row(
      children: [
        Expanded(child: _buildSocialButton('Google', _googleIconWidget())),
        const SizedBox(width: 12),
        Expanded(
          child: _buildSocialButton(
            'Apple',
            const Icon(Icons.apple, color: Colors.white, size: 19),
          ),
        ),
      ],
    );
  }

  Widget _buildSocialButton(String label, Widget icon) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: const Color(0x0EFFFFFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x21FFFFFF)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          icon,
          const SizedBox(width: 9),
          Text(
            label,
            style: GoogleFonts.manrope(
              fontSize: 14.5,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRegisterLink() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          "Don't have an account?  ",
          style: GoogleFonts.manrope(
            fontSize: 13,
            color: const Color(0x66FFFFFF),
          ),
        ),
        GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const RegisterScreen()),
          ),
          child: Text(
            'Create account',
            style: GoogleFonts.manrope(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _kVioletText,
            ),
          ),
        ),
      ],
    );
  }

  // Colour-faithful Google G rendered via canvas
  Widget _googleIconWidget() {
    return SizedBox(
      width: 19,
      height: 19,
      child: CustomPaint(painter: _GoogleGPainter()),
    );
  }
}

// ─── Shader CustomPainter ─────────────────────────────────────────────────────
class _AuraShaderPainter extends CustomPainter {
  final ui.FragmentShader shader;
  final _ShaderState state;

  _AuraShaderPainter(this.shader, this.state) : super(repaint: state);

  @override
  void paint(Canvas canvas, Size size) {
    // Uniform layout (matches aura_shader.frag declaration order):
    // 0–1: uResolution (vec2), 2: uTime, 3: uBrightness
    shader.setFloat(0, size.width);
    shader.setFloat(1, size.height);
    shader.setFloat(2, state.time);
    shader.setFloat(3, state.brightness);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_AuraShaderPainter old) => true;
}

// ─── Google G painter ─────────────────────────────────────────────────────────
class _GoogleGPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h / 2;
    final r = w * 0.46;
    final stroke = w * 0.18;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;

    // Red (top-right → bottom-right)
    paint.color = const Color(0xFFEA4335);
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r),
      -1.1,
      1.3,
      false,
      paint,
    );

    // Blue (top-left → top-right, wraps through bottom)
    paint.color = const Color(0xFF4285F4);
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r),
      -3.1,
      2.0,
      false,
      paint,
    );

    // Yellow (bottom-left)
    paint.color = const Color(0xFFFBBC05);
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r),
      2.2,
      0.9,
      false,
      paint,
    );

    // Green (bottom-right)
    paint.color = const Color(0xFF34A853);
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r),
      0.2,
      1.0,
      false,
      paint,
    );

    // Horizontal bar of the G (white fill to cut the circle open)
    final barPaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.fill;
    canvas.drawRect(
      Rect.fromLTWH(cx, cy - stroke * 0.5, r + stroke * 0.5, stroke),
      barPaint,
    );
  }

  @override
  bool shouldRepaint(_) => false;
}
