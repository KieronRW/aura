import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app_links/app_links.dart';
import 'config/supabase_config.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/terms_screen.dart';
import 'screens/home/home_screen.dart';
import 'providers/terms_provider.dart';
import 'package:flutter/services.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.anonKey,
  );

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  runApp(const ProviderScope(child: AuraApp()));
}

class AuraApp extends ConsumerStatefulWidget {
  const AuraApp({super.key});

  @override
  ConsumerState<AuraApp> createState() => _AuraAppState();
}

class _AuraAppState extends ConsumerState<AuraApp> {
  final _appLinks = AppLinks();
  String? _lastCheckedUserId;
  Future<bool>? _termsFuture;

  @override
  void initState() {
    super.initState();
    _handleDeepLinks();
    _handleAuthStateChanges();
  }

  void _handleDeepLinks() {
    _appLinks.uriLinkStream.listen((uri) {
      Supabase.instance.client.auth.getSessionFromUrl(uri);
    });
  }

  void _handleAuthStateChanges() {
    Supabase.instance.client.auth.onAuthStateChange.listen((state) {
      if (state.session == null) {
        // User signed out — reset terms gate so next login re-checks.
        ref.read(termsAcceptedProvider.notifier).state = false;
        setState(() {
          _lastCheckedUserId = null;
          _termsFuture = null;
        });
      }
    });
  }

  Future<bool> _checkTermsAccepted(String userId) async {
    final rows = await Supabase.instance.client
        .from('user_agreements')
        .select('terms_accepted_at')
        .eq('user_id', userId)
        .limit(1);
    final accepted = (rows as List).isNotEmpty;
    if (accepted && mounted) {
      ref.read(termsAcceptedProvider.notifier).state = true;
    }
    return accepted;
  }

  Widget _buildHome(Session session) {
    final termsAccepted = ref.watch(termsAcceptedProvider);
    if (termsAccepted) return const HomeScreen();

    final userId = session.user.id;
    if (userId != _lastCheckedUserId) {
      _lastCheckedUserId = userId;
      _termsFuture = _checkTermsAccepted(userId);
    }

    return FutureBuilder<bool>(
      future: _termsFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            backgroundColor: Colors.black,
            body: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: Colors.white24,
                  strokeWidth: 1.5,
                ),
              ),
            ),
          );
        }
        return snapshot.data! ? const HomeScreen() : const TermsScreen();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aura',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        colorScheme: const ColorScheme.dark(
          primary: Colors.white,
          surface: Color(0xFF111111),
        ),
      ),
      home: StreamBuilder<AuthState>(
        stream: Supabase.instance.client.auth.onAuthStateChange,
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            final session = snapshot.data!.session;
            if (session != null) {
              return _buildHome(session);
            }
          }
          return const LoginScreen();
        },
      ),
    );
  }
}
