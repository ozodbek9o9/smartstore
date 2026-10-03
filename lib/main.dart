import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:smart_store/screens/theme_controller.dart';
import 'firebase_options.dart';
import 'screens/layout_page.dart';
import 'login_page.dart';
import 'widgets/update_layer.dart';

Object? _firebaseInitError;
final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // EasyLocalizationni initialize qilish - BU JUDDA MUHIM!
  await EasyLocalization.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint('✅ Firebase initialized successfully');
  } catch (e, st) {
    debugPrint('❌ Firebase initialization failed: $e');
    debugPrint('$st');
    _firebaseInitError = e;
  }

  // Ilova ishga tushishidan oldin saqlangan dark-mode holatini yuklaymiz
  await ThemeController.instance.load();

  runApp(
    EasyLocalization(
      supportedLocales: const [
        Locale('en', 'US'),
        Locale('ru', 'RU'),
        Locale('uz', 'UZ'),
      ],
      path: 'assets/translations', // BU PAPKA MANZILI TO'G'RI BO'LISHI KERAK
      fallbackLocale: const Locale('en', 'US'),
      saveLocale: true,
      child: const SmartStoreApp(),
    ),
  );
}

// ── Brand palette ────────────────────────────────────────────────────────
class SmartStoreColors {
  static const Color primary = Color(0xFF2563EB);
  static const Color primaryLight = Color(0xFF3B82F6);
  static const Color primaryDark = Color(0xFF1D4ED8);
  static const Color secondary = Color(0xFF8B5CF6);
  static const Color accent = Color(0xFF06B6D4);
  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFEF4444);

  static const Color lightBackground = Color(0xFFF3F4F6);
  static const Color lightSurface = Color(0xFFF1F5F9);
  static const Color lightSurfaceVariant = Color(0xFFFFFFFF);
  static const Color lightTextPrimary = Color(0xFF0F172A);
  static const Color lightTextSecondary = Color(0xFF475569);
  static const Color lightTextMuted = Color(0xFF64748B);
  static const Color lightDivider = Color(0xFFCBD5E1);
  static const Color lightShadow = Color(0x12000000);

  static const Color darkBackground = Color(0xFF0F172A);
  static const Color darkSurface = Color(0xFF1E293B);
  static const Color darkSurfaceVariant = Color(0xFF2D3B52);
  static const Color darkTextPrimary = Color(0xFFF1F5F9);
  static const Color darkTextSecondary = Color(0xFF94A3B8);
  static const Color darkTextMuted = Color(0xFF64748B);
  static const Color darkDivider = Color(0x33FFFFFF);
  static const Color darkShadow = Color(0x40000000);
}

class SmartStoreApp extends StatelessWidget {
  const SmartStoreApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ThemeController.instance,
      builder: (context, _) {
        return MaterialApp(
          navigatorKey: _rootNavigatorKey,
          title: 'SmartStore Console',
          debugShowCheckedModeBanner: false,
          locale: context.locale,
          supportedLocales: context.supportedLocales,
          localizationsDelegates: context.localizationDelegates,
          theme: _buildLightTheme(),
          darkTheme: _buildDarkTheme(),
          themeMode: ThemeController.instance.isDarkMode
              ? ThemeMode.dark
              : ThemeMode.light,
          builder: (context, child) =>
              UpdateLayer(child: child ?? const SizedBox.shrink()),
          home: _firebaseInitError == null
              ? const SplashScreen()
              : _FirebaseInitErrorScreen(error: _firebaseInitError!),
          routes: {
            '/login': (context) => const LoginPage(),
            '/home': (context) => const LayoutPage(),
          },
        );
      },
    );
  }

  ThemeData _buildLightTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme:
          ColorScheme.fromSeed(
            seedColor: SmartStoreColors.primary,
            brightness: Brightness.light,
          ).copyWith(
            primary: SmartStoreColors.primary,
            secondary: SmartStoreColors.secondary,
            surface: SmartStoreColors.lightSurface,
            onSurface: SmartStoreColors.lightTextPrimary,
          ),
      scaffoldBackgroundColor: SmartStoreColors.lightBackground,
      appBarTheme: const AppBarTheme(
        backgroundColor: SmartStoreColors.lightSurface,
        foregroundColor: SmartStoreColors.lightTextPrimary,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: SmartStoreColors.lightSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        shadowColor: SmartStoreColors.lightShadow,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: SmartStoreColors.lightSurfaceVariant,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: SmartStoreColors.lightDivider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: SmartStoreColors.lightDivider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: SmartStoreColors.primary,
            width: 2,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: SmartStoreColors.danger,
            width: 2,
          ),
        ),
        labelStyle: TextStyle(color: SmartStoreColors.lightTextSecondary),
        hintStyle: TextStyle(color: SmartStoreColors.lightTextMuted),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: SmartStoreColors.primary,
          foregroundColor: Colors.white,
          // A global button style must not force an infinite width: buttons
          // can also be placed inside a Row (for example, dialog actions).
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: SmartStoreColors.primary),
      ),
      drawerTheme: const DrawerThemeData(
        backgroundColor: SmartStoreColors.lightSurface,
        width: 280,
      ),
    );
  }

  ThemeData _buildDarkTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme:
          ColorScheme.fromSeed(
            seedColor: SmartStoreColors.primary,
            brightness: Brightness.dark,
          ).copyWith(
            primary: SmartStoreColors.primaryLight,
            secondary: SmartStoreColors.secondary,
            surface: SmartStoreColors.darkSurface,
            onSurface: SmartStoreColors.darkTextPrimary,
          ),
      scaffoldBackgroundColor: SmartStoreColors.darkBackground,
      appBarTheme: const AppBarTheme(
        backgroundColor: SmartStoreColors.darkSurface,
        foregroundColor: SmartStoreColors.darkTextPrimary,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: SmartStoreColors.darkSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        shadowColor: SmartStoreColors.darkShadow,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: SmartStoreColors.darkSurfaceVariant,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: SmartStoreColors.darkDivider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: SmartStoreColors.darkDivider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: SmartStoreColors.primaryLight,
            width: 2,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: SmartStoreColors.danger,
            width: 2,
          ),
        ),
        labelStyle: TextStyle(color: SmartStoreColors.darkTextSecondary),
        hintStyle: TextStyle(color: SmartStoreColors.darkTextMuted),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: SmartStoreColors.primaryLight,
          foregroundColor: Colors.white,
          // Keep the shared style usable in unconstrained horizontal layouts.
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: SmartStoreColors.primaryLight,
        ),
      ),
      drawerTheme: const DrawerThemeData(
        backgroundColor: SmartStoreColors.darkSurface,
        width: 280,
      ),
    );
  }
}

// ── Firebase init error screen ──────────────────────────────────────────
class _FirebaseInitErrorScreen extends StatelessWidget {
  final Object error;
  const _FirebaseInitErrorScreen({required this.error});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SmartStoreColors.lightBackground,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: SmartStoreColors.danger,
                size: 64,
              ),
              const SizedBox(height: 16),
              const Text(
                'Firebase Initialization Failed',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: SmartStoreColors.lightTextPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                error.toString(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: SmartStoreColors.lightTextMuted,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── SplashScreen ─────────────────────────────────────────────────────────
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _scale = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
    _controller.forward();

    _checkLoginStatus();
  }

  Future<void> _checkLoginStatus() async {
    await Future.delayed(const Duration(milliseconds: 1500));

    if (!mounted) return;

    final isLoggedIn = FirebaseAuth.instance.currentUser != null;

    Navigator.of(context).pushReplacementNamed(isLoggedIn ? '/home' : '/login');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: const [
              SmartStoreColors.primary,
              SmartStoreColors.primaryDark,
              Color(0xFF1E3A5F),
            ],
          ),
        ),
        child: Center(
          child: FadeTransition(
            opacity: _fade,
            child: ScaleTransition(
              scale: _scale,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(30),
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 40,
                          spreadRadius: 10,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(30),
                      child: Image.asset('assets/logo.png', fit: BoxFit.cover),
                    ),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    'app_name'.tr(),
                    style: const TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const SizedBox(height: 12),
                  Text(
                    'update.starting'.tr(),
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 40),
                  SizedBox(
                    width: 200,
                    height: 3,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        backgroundColor: Colors.white.withOpacity(0.2),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
