import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'screens/layout_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;

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
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    debugPrint('AUTH_SUBMIT: username=$username');

    try {
      await FirebaseAuth.instance.signOut();
      final customerLoginResult = await _tryCustomerLogin(username, password);
      if (customerLoginResult == true) {
        _openHome();
        return;
      }
      if (customerLoginResult == false) return;

      _showError('Username yoki parol noto\'g\'ri.');
    } on FirebaseAuthException catch (e, stack) {
      debugPrint('AUTH_FIREBASE_ERROR: code=${e.code} msg=${e.message}');
      debugPrintStack(stackTrace: stack);

      if (e.code == 'wrong-password' ||
          e.code == 'invalid-credential' ||
          e.code == 'user-not-found' ||
          e.code == 'invalid-login-credentials') {
        _showError('Username yoki parol noto\'g\'ri.');
        return;
      }

      if (e.code == 'invalid-email') {
        _showError('Username formatini tekshiring.');
        return;
      }

      final firebaseMessage = e.message?.toLowerCase() ?? '';
      if (e.code == 'operation-not-allowed' ||
          firebaseMessage.contains('restricted to administrators') ||
          firebaseMessage.contains('anonymous')) {
        _showError(
          'Firebase Console’da Anonymous sign-in yoqilmagan. Admin uni yoqishi kerak.',
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

  /// Supports accounts created by the separate admin console. Those accounts
  /// are stored in the top-level `customers` collection, not Firebase Auth.
  Future<bool?> _tryCustomerLogin(String username, String password) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('customers')
        .where('username', isEqualTo: username)
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) return null;

    final customer = snapshot.docs.first.data();
    if (customer['password']?.toString() != password) {
      _showError('Username yoki parol noto\'g\'ri.');
      return false;
    }
    if (_isBlocked(customer)) {
      await _showBlockedDialog();
      return false;
    }

    final credential = await FirebaseAuth.instance.signInAnonymously();
    final user = credential.user;
    if (user == null) {
      throw StateError('Firebase anonymous sessiyasi ochilmadi.');
    }

    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'uid': user.uid,
      'username': username,
      'usernameLower': username.toLowerCase(),
      'fullName': customer['name']?.toString() ?? 'SmartStore user',
      'customerId': snapshot.docs.first.id,
      'isBlocked': false,
      'authProvider': 'anonymous_customer',
    }, SetOptions(merge: true));
    return true;
  }

  bool _isBlocked(Map<String, dynamic>? data) {
    final status = data?['status']?.toString().trim().toLowerCase();
    return data?['isBlocked'] == true ||
        data?['blocked'] == true ||
        data?['is_blocked'] == true ||
        status == 'blocked' ||
        status == 'block' ||
        status == 'bloklangan';
  }

  Future<void> _showBlockedDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Akkaunt bloklangan'),
        content: const Text(
          'Admin ushbu akkauntni bloklagan. Blok olib tashlangandan keyin qayta urinib ko‘ring.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Tushunarli'),
          ),
        ],
      ),
    );
  }

  void _openHome() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Tizimga muvaffaqiyatli kirdingiz.'),
        backgroundColor: const Color(0xFF22C55E),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, _, _) => const LayoutPage(),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
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
                shadowColor: Colors.black.withValues(alpha: 0.2),
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
                                color: const Color(
                                  0xFF2563EB,
                                ).withValues(alpha: 0.3),
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
                        Text(
                          'Hisobingizga kiring',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade500,
                            fontWeight: FontWeight.w500,
                          ),
                        ),

                        const SizedBox(height: 24),
                        Divider(color: Colors.grey.shade200),
                        const SizedBox(height: 24),

                        FadeTransition(
                          opacity: _fadeAnimation,
                          child: SlideTransition(
                            position: _slideAnimation,
                            child: _buildCredentialsSignInStep(),
                          ),
                        ),
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

  Widget _buildCredentialsSignInStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _usernameController,
          textInputAction: TextInputAction.next,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Username',
            hintText: 'Username kiriting',
            prefixIcon: Icon(Icons.person_outline_rounded),
          ),
          validator: (value) {
            final username = value?.trim() ?? '';
            if (username.isEmpty) return 'Username kiriting';
            if (!RegExp(r'^[a-zA-Z0-9_]{3,}$').hasMatch(username)) {
              return 'Kamida 3 ta belgi: harf, raqam yoki _';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            labelText: 'Password',
            hintText: 'Parolingizni kiriting',
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            suffixIcon: IconButton(
              tooltip: _obscurePassword
                  ? 'Parolni ko\'rsatish'
                  : 'Parolni yashirish',
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
              ),
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
          validator: (value) =>
              value == null || value.isEmpty ? 'Password kiriting' : null,
        ),
        const SizedBox(height: 24),
        _primaryAuthButton(
          label: 'Kirish',
          icon: Icons.login_rounded,
          color: const Color(0xFF2563EB),
        ),
      ],
    );
  }

  Widget _primaryAuthButton({
    required String label,
    required IconData icon,
    required Color color,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _isLoading ? null : _submit,
        icon: _isLoading ? const SizedBox.shrink() : Icon(icon, size: 19),
        label: _isLoading
            ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
      ),
    );
  }
}
