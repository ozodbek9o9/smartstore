import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'screens/layout_page.dart';
import 'services/auth_service.dart';
import 'utils/activity_logger.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LoginPage – tizim o'zi aniqlaydi: sign-in yoki sign-up kerakligini
// ─────────────────────────────────────────────────────────────────────────────
class LoginPage extends StatefulWidget {
  final bool showSignUp;
  const LoginPage({super.key, this.showSignUp = false});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

enum _AuthMode { unknown, signIn, signUp }

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  // 0 = username step, 1 = password/details step
  int _currentStep = 0;

  // Detected mode after username check
  _AuthMode _authMode = _AuthMode.unknown;

  final AuthService _authService = AuthService();

  late final AnimationController _slideController;
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero).animate(
          CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
        );
    _fadeAnimation = CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOut,
    );
    _slideController.forward();

    // If opened after account deletion, skip straight to sign-up step
    if (widget.showSignUp) {
      _authMode = _AuthMode.signUp;
      _currentStep = 1;
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _fullNameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  // ── Username tekshirish – tizim o'zi hal qiladi ──────────────────────────
  Future<void> _checkUsername() async {
    if (_formKey.currentState == null) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final username = _usernameController.text.trim();
    debugPrint('LOGIN: checking username "$username"');
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('usernameLower', isEqualTo: username.toLowerCase())
          .limit(1)
          .get();

      final exists = snapshot.docs.isNotEmpty;
      debugPrint('LOGIN: username exists = $exists');

      setState(() {
        _authMode = exists ? _AuthMode.signIn : _AuthMode.signUp;
        _currentStep = 1;
        _isLoading = false;
      });

      _slideController.reset();
      _slideController.forward();
    } on FirebaseException catch (e, stack) {
      debugPrint('LOGIN_CHECK_FIREBASE_ERROR: code=${e.code} msg=${e.message}');
      debugPrintStack(stackTrace: stack);
      setState(() => _isLoading = false);
      _showError('Xatolik yuz berdi: ${e.message ?? e.code}');
    } catch (e, stack) {
      debugPrint('LOGIN_CHECK_GENERIC_ERROR: $e');
      debugPrintStack(stackTrace: stack);
      setState(() => _isLoading = false);
      _showError('Xatolik yuz berdi: ${e.toString()}');
    }
  }

  // ── Kirish yoki ro'yxatdan o'tish ─────────────────────────────────────────
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    final fullName = _fullNameController.text.trim();

    debugPrint(
      'AUTH_SUBMIT: mode=${_authMode.name} username=$username fullName=$fullName passwordLength=${password.length}',
    );

    try {
      AuthResult result;

      if (_authMode == _AuthMode.signIn) {
        final email = AuthService.emailForUsername(username);
        debugPrint('AUTH_SUBMIT_SIGNIN: email=$email');
        final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
        result = AuthResult(user: cred.user!, created: false);
      } else {
        debugPrint(
          'AUTH_SUBMIT_SIGNUP: email=${AuthService.emailForUsername(username)}',
        );
        result = await _authService.registerOrSignIn(
          username: username,
          fullName: fullName,
          password: password,
        );
      }

      await ActivityLogger.log(
        username: username,
        type: result.created ? 'user_registered' : 'user_login',
        result: 'success',
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.created
                ? 'Xush kelibsiz, $fullName! 🎉'
                : 'Qaytib keldingiz! 👋',
          ),
          backgroundColor: const Color(0xFF22C55E),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );

      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, _, _) => const LayoutPage(),
            transitionsBuilder: (_, anim, _, child) =>
                FadeTransition(opacity: anim, child: child),
            transitionDuration: const Duration(milliseconds: 400),
          ),
        );
      }
    } on FirebaseAuthException catch (e, stack) {
      debugPrint('AUTH_FIREBASE_ERROR: code=${e.code} msg=${e.message}');
      debugPrintStack(stackTrace: stack);

      if (_authMode == _AuthMode.signIn &&
          (e.code == 'wrong-password' ||
              e.code == 'invalid-credential' ||
              e.code == 'user-not-found')) {
        _showError('Parol noto\'g\'ri. Qaytadan urinib ko\'ring.');
        return;
      }

      if (_authMode == _AuthMode.signUp &&
          (e.code == 'email-already-in-use' || e.code == 'account-exists')) {
        _showError(
          'Bu hisob mavjud. Iltimos, to\'g\'ri parolni kiriting yoki boshqa foydalanuvchi nomi ishlating.',
        );
        return;
      }

      if (e.code == 'weak-password') {
        _showError(
          'Parol juda zaif. Kamida 6 ta belgidan iborat, harf va raqam bo\'lishi kerak.',
        );
        return;
      }

      if (e.code == 'invalid-email') {
        _showError(
          'Email formati noto\'g\'ri. Foydalanuvchi nomini tekshiring.',
        );
        return;
      }

      _showError('Xatolik: ${e.message ?? e.toString()}');
    } catch (e, stack) {
      debugPrint('AUTH_GENERIC_ERROR: $e');
      debugPrintStack(stackTrace: stack);
      _showError('Xatolik yuz berdi: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _goBack() {
    _slideController.reset();
    _slideController.forward();
    setState(() {
      _currentStep = 0;
      _authMode = _AuthMode.unknown;
      _passwordController.clear();
      _fullNameController.clear();
      _confirmPasswordController.clear();
      _isLoading = false;
    });
  }

  void _switchToSignUp() {
    _slideController.reset();
    _slideController.forward();
    setState(() {
      _authMode = _AuthMode.signUp;
      _currentStep = 1;
      _passwordController.clear();
      _fullNameController.clear();
      _confirmPasswordController.clear();
      _obscurePassword = true;
      _obscureConfirmPassword = true;
      _isLoading = false;
    });
  }

  void _switchToSignIn() {
    _slideController.reset();
    _slideController.forward();
    setState(() {
      _authMode = _AuthMode.signIn;
      _currentStep = 1;
      _passwordController.clear();
      _fullNameController.clear();
      _confirmPasswordController.clear();
      _obscurePassword = true;
      _obscureConfirmPassword = true;
      _isLoading = false;
    });
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: const Color(0xFFEF4444),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDarkMode
                ? const [
                    Color(0xFF0F172A),
                    Color(0xFF1E293B),
                    Color(0xFF0F172A),
                  ]
                : const [
                    Color(0xFF2563EB),
                    Color(0xFF1D4ED8),
                    Color(0xFF1E3A5F),
                  ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Card(
                elevation: 8,
                shadowColor: Colors.black.withOpacity(0.2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 420),
                  padding: const EdgeInsets.all(32),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // ── Logo ──
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            color: const Color(0xFF2563EB),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF2563EB).withOpacity(0.3),
                                blurRadius: 20,
                                spreadRadius: 5,
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: Image.asset(
                              'assets/logo.png',
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'SmartStore',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: isDarkMode
                                ? Colors.white
                                : const Color(0xFF1E293B),
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 280),
                          child: Text(
                            _authMode == _AuthMode.signIn
                                ? 'Hisobingizga kiring'
                                : _authMode == _AuthMode.signUp
                                ? 'Yangi hisob yarating'
                                : 'Foydalanuvchi nomingizni kiriting',
                            key: ValueKey(_authMode),
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade500,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),
                        Divider(color: Colors.grey.shade200),
                        const SizedBox(height: 24),

                        // ── Mode badge (sign-in / sign-up indicator) ──
                        if (_authMode != _AuthMode.unknown) ...[
                          _AuthModeBadge(mode: _authMode, isDark: isDarkMode),
                          const SizedBox(height: 20),
                        ],

                        // ── Step 0: Username ──
                        if (_currentStep == 0) _buildUsernameStep(isDarkMode),

                        // ── Step 1: Password / Full info ──
                        if (_currentStep == 1) ...[
                          FadeTransition(
                            opacity: _fadeAnimation,
                            child: SlideTransition(
                              position: _slideAnimation,
                              child: _authMode == _AuthMode.signIn
                                  ? _buildSignInStep(isDarkMode)
                                  : _buildSignUpStep(isDarkMode),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Step 0: Username input ────────────────────────────────────────────────
  Widget _buildUsernameStep(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _usernameController,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _checkUsername(),
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Foydalanuvchi nomi',
            hintText: 'username yoki login',
            prefixIcon: const Icon(Icons.person_outline_rounded),
            suffixIcon: _isLoading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
          ),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Foydalanuvchi nomini kiriting';
            }
            if (value.length < 3) {
              return 'Kamida 3 ta belgi bo\'lishi kerak';
            }
            if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(value)) {
              return 'Faqat harf, raqam va _ belgisi';
            }
            return null;
          },
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _checkUsername,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            child: _isLoading
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Davom etish',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(width: 8),
                      Icon(Icons.arrow_forward_rounded, size: 18),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  // ── Step 1 Sign In: only password ─────────────────────────────────────────
  Widget _buildSignInStep(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Username display chip
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFF2563EB).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.person_rounded,
                  color: Color(0xFF2563EB),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _usernameController.text.trim(),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : const Color(0xFF1E293B),
                    ),
                  ),
                  Text(
                    'Hisob topildi',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                ],
              ),
              const Spacer(),
              InkWell(
                onTap: _goBack,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    Icons.edit_outlined,
                    size: 16,
                    color: Colors.grey.shade500,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Password
        TextFormField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          textInputAction: TextInputAction.done,
          autofocus: true,
          onFieldSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            labelText: 'Parol',
            hintText: 'Parolingizni kiriting',
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
              ),
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
          validator: (value) {
            if (value == null || value.isEmpty) return 'Parolni kiriting';
            return null;
          },
        ),
        const SizedBox(height: 24),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            child: _isLoading
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.login_rounded, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Kirish',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 18),
        Align(
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Hisob yo\'qmi?',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              ),
              TextButton(
                onPressed: _switchToSignUp,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Sign up',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF2563EB),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Step 1 Sign Up: full name + password + confirm ────────────────────────
  Widget _buildSignUpStep(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Username display chip
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF0FDF4),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? const Color(0xFF334155) : const Color(0xFFBBF7D0),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFF22C55E).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.person_add_rounded,
                  color: Color(0xFF22C55E),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _usernameController.text.trim(),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : const Color(0xFF1E293B),
                    ),
                  ),
                  Text(
                    'Yangi foydalanuvchi',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                ],
              ),
              const Spacer(),
              InkWell(
                onTap: _goBack,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    Icons.edit_outlined,
                    size: 16,
                    color: Colors.grey.shade500,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Full Name
        TextFormField(
          controller: _fullNameController,
          textInputAction: TextInputAction.next,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'To\'liq ism',
            hintText: 'Ism va familiya',
            prefixIcon: Icon(Icons.badge_outlined),
          ),
          validator: (value) {
            if (value == null || value.isEmpty) return 'Ismingizni kiriting';
            if (value.length < 2) return 'Kamida 2 ta belgi';
            return null;
          },
        ),
        const SizedBox(height: 16),

        // Password
        TextFormField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: 'Parol yarating',
            hintText: 'Kuchli parol kiriting',
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
              ),
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
          validator: (value) {
            if (value == null || value.isEmpty) return 'Parol yarating';
            if (value.length < 6) return 'Kamida 6 ta belgi';
            if (!RegExp(r'^(?=.*[A-Za-z])(?=.*\d)').hasMatch(value)) {
              return 'Harf va raqam bo\'lishi kerak';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),

        // Confirm Password
        TextFormField(
          controller: _confirmPasswordController,
          obscureText: _obscureConfirmPassword,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            labelText: 'Parolni tasdiqlang',
            hintText: 'Parolni qayta kiriting',
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            suffixIcon: IconButton(
              icon: Icon(
                _obscureConfirmPassword
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
              ),
              onPressed: () => setState(
                () => _obscureConfirmPassword = !_obscureConfirmPassword,
              ),
            ),
          ),
          validator: (value) {
            if (value == null || value.isEmpty) return 'Parolni tasdiqlang';
            if (value != _passwordController.text) return 'Parollar mos emas';
            return null;
          },
        ),
        const SizedBox(height: 24),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF22C55E),
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            child: _isLoading
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.person_add_rounded, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Ro\'yxatdan o\'tish',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 18),
        Align(
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Allaqachon hisobingiz bormi?',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              ),
              TextButton(
                onPressed: _switchToSignIn,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Sign in',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF22C55E),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Auth Mode Badge – sign-in yoki sign-up ekanligini ko'rsatuvchi badge
// ─────────────────────────────────────────────────────────────────────────────
class _AuthModeBadge extends StatelessWidget {
  final _AuthMode mode;
  final bool isDark;

  const _AuthModeBadge({required this.mode, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final bool isSignIn = mode == _AuthMode.signIn;

    final Color bgColor = isSignIn
        ? const Color(0xFF2563EB).withOpacity(isDark ? 0.18 : 0.08)
        : const Color(0xFF22C55E).withOpacity(isDark ? 0.18 : 0.08);

    final Color borderColor = isSignIn
        ? const Color(0xFF2563EB).withOpacity(0.25)
        : const Color(0xFF22C55E).withOpacity(0.25);

    final Color iconColor = isSignIn
        ? const Color(0xFF2563EB)
        : const Color(0xFF22C55E);

    final IconData icon = isSignIn
        ? Icons.login_rounded
        : Icons.person_add_rounded;

    final String text = isSignIn
        ? 'Mavjud hisob aniqlandi'
        : 'Yangi hisob yaratiladi';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 18),
          const SizedBox(width: 10),
          Text(
            text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: iconColor,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              isSignIn ? 'Sign In' : 'Sign Up',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: iconColor,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
