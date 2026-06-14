import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'models/app_state.dart';
import 'models/army_state.dart';
import 'services/game_data_service.dart';
import 'services/subscription_service.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'game/notifiers/game_notifier.dart';
import '../app_theme.dart';
import 'widgets/aetherra_text_field.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  await Supabase.initialize(
    url: 'https://llcbrxbhuhokystueojd.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxsY2JyeGJodWhva3lzdHVlb2pkIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzc5Nzc1OTIsImV4cCI6MjA5MzU1MzU5Mn0.QIuDX5rGNh92UNlQhBF3f2oauL6uZy4YeVgXxQ6ubN4',
  );
  runApp(const AetherraApp());
}

final _sb = Supabase.instance.client;

class AetherraApp extends StatelessWidget {
  const AetherraApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ArmyState()),
        ChangeNotifierProvider(create: (_) => GameNotifier()),
      ],
      child: MaterialApp(
        title: 'Aetherra',
        debugShowCheckedModeBanner: false,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en')],
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: AppColors.dark,
          colorScheme: const ColorScheme.dark(
            primary:   AppColors.gold,
            surface:   AppColors.dark,
            onSurface: AppColors.textLight,
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor:      AppColors.dark,
            surfaceTintColor:     Colors.transparent,
            scrolledUnderElevation: 0,
            elevation:            0,
            shadowColor:          Colors.transparent,
          ),
          tabBarTheme: TabBarThemeData(
            dividerColor:  Colors.transparent,
            overlayColor:  WidgetStateProperty.all(Colors.transparent),
            indicatorColor: AppColors.gold,
            labelColor:    AppColors.gold,
            unselectedLabelColor: AppColors.grey,
          ),
          dialogTheme: const DialogThemeData(
            backgroundColor:  AppColors.dark,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
          ),
          bottomSheetTheme: const BottomSheetThemeData(
            backgroundColor:  AppColors.dark,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
          ),
          cardTheme: const CardThemeData(
            color:            AppColors.dark,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
          ),
          drawerTheme: const DrawerThemeData(
            backgroundColor:  AppColors.dark,
            surfaceTintColor: Colors.transparent,
          ),
          popupMenuTheme: const PopupMenuThemeData(
            color:            AppColors.dark,
            surfaceTintColor: Colors.transparent,
          ),
          menuTheme: const MenuThemeData(
            style: MenuStyle(
              backgroundColor:  WidgetStatePropertyAll(AppColors.dark),
              surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
            ),
          ),
          iconButtonTheme: IconButtonThemeData(
            style: IconButton.styleFrom(overlayColor: Colors.transparent),
          ),
        ),
        home: const AuthGate(),
      ),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool? _ready;
  bool  _onboardingDone = true;

  @override
  void initState() {
    super.initState();
    _init();
    _sb.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.signedIn) {
        _loadAll();
      } else if (data.event == AuthChangeEvent.signedOut) {
        AppState.reset();
        SubscriptionService.reset();
        if (mounted) setState(() => _ready = false);
      }
    });
  }

  Future<void> _init() async {
    final session = _sb.auth.currentSession;
    if (session != null) {
      await _loadAll();
    } else {
      if (mounted) setState(() => _ready = false);
    }
  }

  Future<void> _loadAll() async {
    final user = _sb.auth.currentUser;
    if (user == null) return;
    final prefs = await SharedPreferences.getInstance();
    final localDone = prefs.getBool('onboarding_done') ?? false;
    final metaDone  = user.userMetadata?['onboarding_done'] == true;
    final done = localDone || metaDone;
    // Load role, subscription status, and game data in parallel
    await Future.wait([
      _loadRole(user.id),
      SubscriptionService.load(),
      GameDataService.load(),
    ]);
    if (mounted) setState(() { _ready = true; _onboardingDone = done; });
  }

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
    try {
      await _sb.auth.updateUser(UserAttributes(data: {'onboarding_done': true}));
    } catch (_) {}
    if (mounted) setState(() => _onboardingDone = true);
  }

  Future<void> _loadRole(String userId) async {
    try {
      final data = await _sb
          .from('profiles').select('role').eq('id', userId).single();
      AppState.userRole = (data['role'] as String?) ?? 'user';
    } catch (_) {
      AppState.userRole = 'user';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ready == null) {
      return const Scaffold(
        backgroundColor: AppColors.dark,
        body: Center(child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: AppColors.gold),
            SizedBox(height: 16),
            Text('Loading Aetherra…',
              style: TextStyle(color: AppColors.greyLight,
                fontSize: 12, fontFamily: 'Cinzel')),
          ])),
      );
    }
    if (!_ready!) return const LoginScreen();
    if (!_onboardingDone) {
      return OnboardingScreen(onComplete: _completeOnboarding);
    }
    return const HomeScreen();
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const gold  = AppColors.gold;
  static const grey  = AppColors.grey;

  final _email       = TextEditingController();
  final _pass        = TextEditingController();
  final _displayName = TextEditingController();
  bool   _isLogin = true;
  bool   _loading = false;
  String _error   = '';

  Future<void> _forgotPassword() async {
    if (_email.text.trim().isEmpty) {
      setState(() => _error = 'Enter your email first.');
      return;
    }
    setState(() { _loading = true; _error = ''; });
    try {
      await _sb.auth.resetPasswordForEmail(_email.text.trim());
      if (mounted) setState(() => _error = 'Password reset email sent!');
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not send reset email.');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _submit() async {
    setState(() { _loading = true; _error = ''; });
    try {
      if (_isLogin) {
        await _sb.auth.signInWithPassword(
          email: _email.text.trim(), password: _pass.text);
      } else {
        if (_displayName.text.trim().isEmpty) {
          setState(() { _error = 'Enter a display name.'; _loading = false; });
          return;
        }
        await _sb.auth.signUp(
          email: _email.text.trim(), password: _pass.text,
          data: {'display_name': _displayName.text.trim()});
        if (mounted) {
          setState(() {
          _error = 'Account created! You can now log in.';
          _isLogin = true; _loading = false;
        });
        }
        return;
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'An error occurred.');
    }
    if (mounted) setState(() => _loading = false);
  }

  Widget _input(TextEditingController ctrl, String hint, bool obscure) =>
    AetherraTextField(
      controller: ctrl,
      obscureText: obscure,
      hintText: hint,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onSubmitted: (_) => _submit());

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final narrow = w < 600;
    return Scaffold(
      backgroundColor: AppColors.dark,
      body: Center(child: SingleChildScrollView(
        padding: EdgeInsets.all(narrow ? 24 : 48),
        child: SizedBox(width: 380, child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Logo
            Center(child: Image.asset('assets/logo.png', width: narrow ? 110.0 : 190.0, height: narrow ? 110.0 : 190.0)),
            const SizedBox(height: 20),

            // Decorative line
            Container(height: 1, width: 48, color: gold.withValues(alpha: 0.35)),
            const SizedBox(height: 20),

            // Title
            Text('AETHERRA',
              style: GoogleFonts.cinzel(
                color: gold, fontSize: 38, fontWeight: FontWeight.w700,
                letterSpacing: 6,
                shadows: [Shadow(color: gold.withValues(alpha: 0.3), blurRadius: 20)])),
            const SizedBox(height: 4),
            Text('War Council',
              style: GoogleFonts.cinzel(
                color: grey.withValues(alpha: 0.5), fontSize: 12, letterSpacing: 4)),

            const SizedBox(height: 48),

            // Mode tabs
            Row(children: [
              _tab('Sign In', _isLogin,
                () => setState(() { _isLogin = true;  _error = ''; })),
              const SizedBox(width: 4),
              _tab('Register', !_isLogin,
                () => setState(() { _isLogin = false; _error = ''; })),
            ]),
            const SizedBox(height: 20),

            // Fields
            if (!_isLogin) ...[
              Text('PROFILE',
                style: GoogleFonts.cinzel(
                  color: gold,
                  fontSize: 10, letterSpacing: 2)),
              const SizedBox(height: 8),
              _input(_displayName, 'Display name', false),
              const SizedBox(height: 20),
              Container(height: 1, width: 48, color: gold.withValues(alpha: 0.35)),
              const SizedBox(height: 16),
              Text('ACCOUNT',
                style: GoogleFonts.cinzel(
                  color: gold,
                  fontSize: 10, letterSpacing: 2)),
              const SizedBox(height: 8),
            ],
            _input(_email, 'Email address', false),
            const SizedBox(height: 8),
            _input(_pass, 'Password', true),
            const SizedBox(height: 10),
            Align(alignment: Alignment.centerRight,
              child: _ForgotPasswordBtn(
                visible: _isLogin,
                onTap: _forgotPassword)),
            const SizedBox(height: 20),

            // Submit button
            SizedBox(width: double.infinity,
              child: _loading
                ? Center(child: SizedBox(width: 22, height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2,
                      color: gold.withValues(alpha: 0.7))))
                : _SubmitBtn(
                    label: _isLogin ? 'Enter' : 'Create Account',
                    onTap: _submit)),

            // Error / success
            if (_error.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _error.contains('created') || _error.contains('sent')
                      ? Colors.green.withValues(alpha: 0.4)
                      : Colors.red.withValues(alpha: 0.4))),
                child: Text(_error, textAlign: TextAlign.center,
                  style: GoogleFonts.cinzel(fontSize: 11,
                    color: _error.contains('created') || _error.contains('sent')
                      ? Colors.green.withValues(alpha: 0.8)
                      : Colors.red.withValues(alpha: 0.8)))),
            ],
          ])))));
  }

  Widget _tab(String label, bool active, VoidCallback onTap) =>
    _TabBtn(label: label, active: active, onTap: onTap);
}

class _TabBtn extends StatefulWidget {
  final String label; final bool active; final VoidCallback onTap;
  const _TabBtn({required this.label, required this.active, required this.onTap});
  @override State<_TabBtn> createState() => _TabBtnState();
}
class _TabBtnState extends State<_TabBtn> {
  bool _hovered = false;
  static const gold = AppColors.gold;
  static const grey = AppColors.grey;
  @override Widget build(BuildContext context) =>
    MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(
              color: widget.active ? gold : Colors.transparent,
              width: 1.5))),
          child: Text(widget.label, style: GoogleFonts.cinzel(
            fontSize: 12, letterSpacing: 1.5,
            color: widget.active
              ? gold
              : _hovered ? gold.withValues(alpha: 0.6) : grey.withValues(alpha: 0.4))))));
}

class _SubmitBtn extends StatefulWidget {
  final String label; final VoidCallback onTap;
  const _SubmitBtn({required this.label, required this.onTap});
  @override State<_SubmitBtn> createState() => _SubmitBtnState();
}
class _SubmitBtnState extends State<_SubmitBtn> {
  bool _hovered = false, _pressed = false;
  static const gold = AppColors.gold;
  @override Widget build(BuildContext context) =>
    MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown:   (_) => setState(() => _pressed = true),
        onTapUp:     (_) { setState(() => _pressed = false); widget.onTap(); },
        onTapCancel: ()  => setState(() => _pressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          transform: _pressed ? (Matrix4.identity()..scaleByDouble(0.97, 0.97, 1.0, 1.0)) : Matrix4.identity(),
          transformAlignment: Alignment.center,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: _pressed
              ? gold.withValues(alpha: 0.45)
              : gold.withValues(alpha: _hovered ? 0.65 : 1.0)),
          child: Text(widget.label, textAlign: TextAlign.center,
            style: GoogleFonts.cinzel(
              color: AppColors.dark,
              fontSize: 13, letterSpacing: 3, fontWeight: FontWeight.w600)))));
}


class _ForgotPasswordBtn extends StatefulWidget {
  final bool visible;
  final VoidCallback onTap;
  const _ForgotPasswordBtn({required this.visible, required this.onTap});
  @override State<_ForgotPasswordBtn> createState() => _ForgotPasswordBtnState();
}
class _ForgotPasswordBtnState extends State<_ForgotPasswordBtn> {
  bool _hovered = false;
  static const grey = AppColors.grey;
  @override Widget build(BuildContext context) =>
    MouseRegion(
      onEnter: (_) { if (widget.visible) setState(() => _hovered = true); },
      onExit:  (_) => setState(() => _hovered = false),
      cursor: widget.visible ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.visible ? widget.onTap : null,
        child: Text('Forgot password?',
          style: GoogleFonts.cinzel(
            color: !widget.visible
              ? Colors.transparent
              : _hovered
                ? AppColors.goldBright
                : grey.withValues(alpha: 0.5),
            fontSize: 12,
            decoration: widget.visible ? TextDecoration.underline : TextDecoration.none,
            decorationColor: _hovered
              ? AppColors.goldBright.withValues(alpha: 0.5)
              : grey.withValues(alpha: 0.2)))));
}